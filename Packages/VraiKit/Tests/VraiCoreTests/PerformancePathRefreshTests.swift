import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct PerformancePathRefreshTests {
    static let names = ["a.txt", "b c.txt", "d[1].txt", "dir/e.txt", "dir.txt", "z.txt"]

    let console = ConsoleLog()

    func makeRepository() async throws -> (URL, RepositoryStore) {
        let repo = Sandbox.root.appending(path: "tests/\(UUID().uuidString)/paths", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: repo.appending(path: "dir"), withIntermediateDirectories: true)
        let git = try Sandbox.git(at: repo)
        try await git.run(.write(["init", "-q", "-b", "main"]))
        for name in Self.names { try Data("one\ntwo\nthree\n".utf8).write(to: repo.appending(path: name)) }
        try await git.run(.write(["add", "-A"]))
        try await git.run(.write(["-c", "user.name=Vrai", "-c", "user.email=vrai@example.com", "commit", "-q", "-m", "Start"]))
        for name in Self.names { try Data("one\ntwo changed\nthree\nfour\n".utf8).write(to: repo.appending(path: name)) }
        try Data("new\n".utf8).write(to: repo.appending(path: "dir/new.txt"))
        try Data("new\n".utf8).write(to: repo.appending(path: "c new.txt"))
        let store = RepositoryStore(git: GitProcess(executable: git.executable, workingDirectory: repo, environment: git.environment, observer: console.observer))
        try await store.refresh()
        return (repo, store)
    }

    func statusCommands() async throws -> [String] {
        try await Task.sleep(for: .milliseconds(20))
        console.flush()
        let commands = console.entries.map(\.command).filter { $0.contains(" status ") }
        console.clear()
        return commands
    }

    func expectMatchesFullRefresh(_ store: RepositoryStore, _ comment: Comment) async throws {
        let statuses = try await statusCommands()
        #expect(!statuses.isEmpty && statuses.allSatisfy { $0.contains(" -- ") }, "\(comment) \(statuses)")
        let quick = try #require(store.snapshot).working
        try await store.refresh()
        let full = try #require(store.snapshot).working
        #expect(quick == full, comment)
        _ = try await statusCommands()
    }

    @Test func stagingFilesMatchesAFullRefresh() async throws {
        let (repo, store) = try await makeRepository()
        defer { try? FileManager.default.removeItem(at: repo.deletingLastPathComponent()) }
        #expect(!RepositoryStore.mayPairRenames(try #require(store.snapshot).working))
        _ = try await statusCommands()
        for path in Self.names + ["dir/new.txt", "c new.txt"] {
            try await store.stage(paths: [path])
            #expect(store.snapshot?.working.first { $0.path == path }?.staged == .full, "\(path)")
            try await expectMatchesFullRefresh(store, "stage \(path)")
        }
        for path in ["d[1].txt", "c new.txt", "dir/e.txt"] {
            try await store.unstage(paths: [path])
            try await expectMatchesFullRefresh(store, "unstage \(path)")
        }
        try await store.stage(paths: ["a.txt", "z.txt"])
        try await expectMatchesFullRefresh(store, "stage two")
    }

    @Test func stagingLinesMatchesAFullRefresh() async throws {
        let (repo, store) = try await makeRepository()
        defer { try? FileManager.default.removeItem(at: repo.deletingLastPathComponent()) }
        _ = try await statusCommands()
        let diff = try #require(try await store.workingDiff(path: "b c.txt", staged: false))
        let line = try #require(diff.hunks[0].lines.firstIndex { $0.kind == .add && $0.text == "four" })
        try await store.stage(lines: LineSelection(file: diff, side: .unstaged, lines: [LineID(hunk: 0, line: line)]))
        #expect(store.snapshot?.working.first { $0.path == "b c.txt" }?.staged == .partial)
        try await expectMatchesFullRefresh(store, "stage a line")
        let staged = try #require(try await store.workingDiff(path: "b c.txt", staged: true))
        let back = try #require(staged.hunks[0].lines.firstIndex { $0.kind == .add && $0.text == "four" })
        try await store.unstage(lines: LineSelection(file: staged, side: .staged, lines: [LineID(hunk: 0, line: back)]))
        try await expectMatchesFullRefresh(store, "unstage a line")
    }

    @Test func ownStagingDoesNotRefreshAgainButAnOutsideAddDoes() async throws {
        let (repo, store) = try await makeRepository()
        defer { try? FileManager.default.removeItem(at: repo.deletingLastPathComponent()) }
        await store.open(watch: true)
        defer { store.close() }
        try await Task.sleep(for: .milliseconds(300))
        _ = try await statusCommands()
        try await store.stage(paths: ["a.txt"])
        try await Task.sleep(for: .milliseconds(900))
        let after = try await statusCommands()
        #expect(after.allSatisfy { $0.contains(" -- ") }, "\(after)")
        let outside = try Sandbox.git(at: repo)
        try await outside.run(.write(["add", "--", "z.txt"]))
        try await waitUntil { store.snapshot?.working.first { $0.path == "z.txt" }?.staged == .full }
        #expect(store.snapshot?.working.first { $0.path == "z.txt" }?.staged == .full)
    }
}
