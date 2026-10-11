import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct PlacesSubmoduleStoreTests {
    static let libgit2 = "Vendor/libgit2"
    static let cmark = "Vendor/cmark-gfm"
    static let parser = "Vendor/swift-argument-parser"

    func open() async throws -> (Scratch, RepositoryStore) {
        let scratch = try await Scratch.copy("everyday")
        try await scratch.git(["submodule", "sync", "--recursive"])
        let store = try scratch.store()
        try await store.refresh()
        return (scratch, store)
    }

    func module(_ store: RepositoryStore, _ path: String) -> Submodule? {
        store.snapshot?.submodules.first { $0.path == path }
    }

    func head(_ scratch: Scratch, _ path: String) async throws -> String {
        let process = try scratch.process.process(at: scratch.repository.appending(path: path, directoryHint: .isDirectory))
        return try await process.run(.read(["rev-parse", "HEAD"])).output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func recorded(_ scratch: Scratch, _ path: String) async throws -> String {
        try await scratch.git(["rev-parse", "HEAD:" + path])
    }

    @Test func initializeChecksOutTheRecordedCommit() async throws {
        let (scratch, store) = try await open()
        defer { scratch.remove() }
        #expect(module(store, Self.parser)?.state == .uninitialized)
        #expect(store.submoduleCommand(path: Self.parser, action: .initUpdate).display == "git submodule update --init --recursive --progress -- Vendor/swift-argument-parser")
        let summary = try await store.submodule(path: Self.parser, action: .initUpdate)
        let expected = try await recorded(scratch, Self.parser)
        #expect(summary.message == "Initialized swift-argument-parser")
        #expect(summary.detail == "Checked out \(String(expected.prefix(7))).")
        #expect(try await head(scratch, Self.parser) == expected)
        #expect(module(store, Self.parser)?.state == .clean)
        #expect(module(store, Self.parser)?.checkedOut?.rawValue == expected)
    }

    @Test func updatePutsTheRecordedCommitBack() async throws {
        let (scratch, store) = try await open()
        defer { scratch.remove() }
        #expect(module(store, Self.libgit2)?.state == .ahead)
        #expect((module(store, Self.libgit2)?.ahead ?? 0) > 0)
        let summary = try await store.submodule(path: Self.libgit2, action: .update)
        let expected = try await recorded(scratch, Self.libgit2)
        #expect(summary.message == "Updated libgit2")
        #expect(try await head(scratch, Self.libgit2) == expected)
        #expect(module(store, Self.libgit2)?.state == .clean)
        #expect(scratch.log.commands.contains("git submodule update --recursive --progress -- Vendor/libgit2"))
    }

    @Test func updateFromTheRemoteBranch() async throws {
        let (scratch, store) = try await open()
        defer { scratch.remove() }
        try await store.submodule(path: Self.cmark, action: .updateRemote)
        let remote = scratch.root.appending(path: "remotes/cmark-gfm.git", directoryHint: .isDirectory)
        let bare = try scratch.process.process(at: remote)
        let tip = try await bare.run(.read(["rev-parse", "master"])).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let checkedOut = try await head(scratch, Self.cmark)
        let process = try scratch.process.process(at: scratch.repository.appending(path: Self.cmark, directoryHint: .isDirectory))
        let merged = try await process.runAllowingFailure(.read(["merge-base", "--is-ancestor", tip, checkedOut]))
        #expect(merged.exitCode == 0)
        #expect(scratch.log.commands.contains("git submodule update --init --remote --merge --progress -- Vendor/cmark-gfm"))
    }

    @Test func recordStagesTheNewCommit() async throws {
        let (scratch, store) = try await open()
        defer { scratch.remove() }
        let summary = try await store.submodule(path: Self.libgit2, action: .record)
        #expect(summary.message == "Staged the new commit for libgit2")
        #expect(summary.detail == "Commit to record it.")
        let staged = try await scratch.git(["diff", "--cached", "--name-only", "--", Self.libgit2])
        #expect(staged == Self.libgit2)
        #expect(try await scratch.git(["rev-parse", ":" + Self.libgit2]) == (try await head(scratch, Self.libgit2)))
    }

    @Test func syncRewritesTheConfiguredURL() async throws {
        let (scratch, store) = try await open()
        defer { scratch.remove() }
        let key = "submodule." + Self.cmark + ".url"
        let good = try await scratch.git(["config", "--get", key])
        #expect(good.hasSuffix("/remotes/cmark-gfm.git"))
        #expect(good.contains(scratch.root.lastPathComponent))
        try await scratch.git(["config", key, "file:///nowhere/cmark-gfm.git"])
        let summary = try await store.submodule(path: Self.cmark, action: .sync)
        #expect(summary.message == "Synced submodule URLs")
        #expect(try await scratch.git(["config", "--get", key]) == good)
        #expect(scratch.log.commands.contains("git submodule sync --recursive -- Vendor/cmark-gfm"))
    }

    @Test func deinitializeEmptiesTheFolderAndKeepsGitmodules() async throws {
        let (scratch, store) = try await open()
        defer { scratch.remove() }
        #expect(store.submoduleCommand(path: Self.cmark, action: .deinit).risk == .destructive)
        let summary = try await store.submodule(path: Self.cmark, action: .deinit)
        #expect(summary.message == "Deinitialized cmark-gfm")
        let folder = scratch.repository.appending(path: Self.cmark).path(percentEncoded: false)
        #expect((try FileManager.default.contentsOfDirectory(atPath: folder)).isEmpty)
        let url = try await scratch.result(["config", "--get", "submodule." + Self.cmark + ".url"])
        #expect(url.exitCode == 1)
        #expect(try scratch.file(".gitmodules").contains("[submodule \"Vendor/cmark-gfm\"]"))
        #expect(module(store, Self.cmark)?.state == .uninitialized)
        try await store.submodule(path: Self.cmark, action: .initUpdate)
        #expect(module(store, Self.cmark)?.state == .clean)
    }

    @Test func addASubmoduleFromALocalRemote() async throws {
        let (scratch, store) = try await open()
        defer { scratch.remove() }
        let url = scratch.root.appending(path: "remotes/swift-argument-parser.git", directoryHint: .isDirectory).absoluteString
        let command = store.addSubmoduleCommand(url: url, path: "Vendor/parser-copy")
        #expect(command.display == "git submodule add --progress -- \(url) Vendor/parser-copy")
        let summary = try await store.addSubmodule(url: url, path: "Vendor/parser-copy")
        #expect(summary.message == "Added submodule Vendor/parser-copy")
        #expect(summary.detail == "Commit .gitmodules to record it.")
        #expect(try scratch.file(".gitmodules").contains("[submodule \"Vendor/parser-copy\"]"))
        #expect(scratch.exists("Vendor/parser-copy/.git"))
        #expect(module(store, "Vendor/parser-copy")?.checkedOut?.rawValue == (try await head(scratch, "Vendor/parser-copy")))
        let staged = try await scratch.git(["diff", "--cached", "--name-only"]).split(separator: "\n").map(String.init)
        #expect(staged.contains(".gitmodules"))
        #expect(staged.contains("Vendor/parser-copy"))

        let branch = try await store.addSubmodule(url: url, path: "Vendor/parser-main", branch: "main")
        #expect(branch.message == "Added submodule Vendor/parser-main")
        #expect(try await scratch.git(["config", "-f", ".gitmodules", "--get", "submodule.Vendor/parser-main.branch"]) == "main")

        let taken = await #expect(throws: GitError.self) { try await store.addSubmodule(url: url, path: "Vendor/parser-copy") }
        #expect(taken?.code == .pathExists)
        let missing = await #expect(throws: GitError.self) { try await store.addSubmodule(url: scratch.root.appending(path: "remotes/missing.git").absoluteString, path: "Vendor/missing") }
        #expect(missing != nil)
    }
}
