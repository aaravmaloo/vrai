import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct StashBisectStoreTests {
    static let branch = "refs/heads/feature/graph-renderer"

    func stashSubjects(_ scratch: Scratch) async throws -> [String] {
        try await scratch.git(["stash", "list", "--format=%gs"]).split(separator: "\n").map(String.init)
    }

    @Test func stashSavesEverythingAndSaysWhenThereIsNothingLeft() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        let store = try scratch.store()
        try await store.stash(message: "wip in the test", includeUntracked: true)
        #expect(scratch.log.commands.contains("git stash push --include-untracked -m \"wip in the test\""))
        let subjects = try await stashSubjects(scratch)
        #expect(subjects.count == 4)
        #expect(subjects.first == "On feature/graph-renderer: wip in the test")
        #expect(try await scratch.git(["status", "--porcelain", "--ignore-submodules"]).isEmpty)
        #expect(store.snapshot?.stashes.count == 4)

        let empty = await #expect(throws: GitError.self) { try await store.stash() }
        #expect(empty?.code == .nothingToStash)
        let none = await #expect(throws: GitError.self) { try await store.stash(paths: ["README.md"]) }
        #expect(none?.code == .nothingToStash)
        #expect(try await stashSubjects(scratch).count == 4)
    }

    @Test func keepIndexAndOnlyStaged() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        let store = try scratch.store()
        let staged = try await scratch.git(["diff", "--cached", "--name-only"])
        try await store.stash(keepIndex: true)
        #expect(try await scratch.git(["diff", "--cached", "--name-only"]) == staged)
        #expect(try await scratch.git(["diff", "--name-only", "--ignore-submodules"]).isEmpty)

        try await scratch.clean()
        try Data("staged\n".utf8).write(to: scratch.repository.appending(path: "staged.txt"))
        try await scratch.git(["add", "--", "staged.txt"])
        try Data("changed\n".utf8).write(to: scratch.repository.appending(path: "README.md"))
        try await store.stash(message: "only the staged file", onlyStaged: true)
        #expect(try await scratch.git(["diff", "--cached", "--name-only"]).isEmpty)
        #expect(try await scratch.git(["diff", "--name-only", "--ignore-submodules"]) == "README.md")
        #expect(try await scratch.git(["stash", "show", "--name-only", "stash@{0}"]) == "staged.txt")

        try await scratch.clean()
        try await store.applyStash(index: 0, restoreIndex: true)
        #expect(try await scratch.git(["diff", "--cached", "--name-only"]) == "staged.txt")
        #expect(scratch.log.commands.contains("git stash apply --index stash@{0}"))
    }

    @Test func applyPopDropAndBranch() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        let store = try scratch.store()
        try await scratch.clean()
        try Data("stashed\n".utf8).write(to: scratch.repository.appending(path: "README.md"))
        try await store.stash(message: "readme")
        try Data("local\n".utf8).write(to: scratch.repository.appending(path: "README.md"))
        let blocked = await #expect(throws: GitError.self) { try await store.applyStash(index: 0) }
        #expect(blocked?.code == .localChangesWouldBeOverwritten(paths: ["README.md"]))
        try await scratch.clean()
        try await store.applyStash(index: 0, pop: true)
        #expect(try scratch.file("README.md") == "stashed\n")

        try await scratch.clean()
        try await store.applyStash(index: 0)
        #expect(!(try await scratch.git(["status", "--porcelain", "--ignore-submodules", "--untracked-files=no"])).isEmpty)
        #expect(try await stashSubjects(scratch).count == 3)
        try await scratch.clean()
        try await store.applyStash(index: 0, pop: true)
        #expect(try await stashSubjects(scratch) == ["On main: release notes draft", "WIP on feature/line-staging: 87f2f88 Diff: stage individual lines from the gutter"])
        #expect(scratch.log.commands.contains("git stash pop stash@{0}"))

        let dropped = try await scratch.oid("stash@{0}")
        try await store.dropStash(index: 0)
        #expect(try await stashSubjects(scratch).count == 1)
        let entry = try #require(await store.recorded.first)
        #expect(entry.kind == .stashDrop)
        #expect(entry.stashCommit == dropped)
        #expect(entry.message == "On main: release notes draft")
        #expect(entry.label == "Dropped stash \u{201C}release notes draft\u{201D}")

        try await scratch.clean()
        let base = try await scratch.oid("stash@{0}^1")
        let exists = await #expect(throws: GitError.self) { try await store.branchFromStash(index: 0, name: "main") }
        #expect(exists?.code == .refExists)
        try await store.branchFromStash(index: 0, name: "line-staging-wip")
        #expect(try await scratch.git(["symbolic-ref", "HEAD"]) == "refs/heads/line-staging-wip")
        #expect(try await scratch.oid("HEAD") == base)
        #expect(try await stashSubjects(scratch).isEmpty)
        #expect(await store.recorded.count == 1)
    }

    @Test func bisectFixtureRunsToTheFirstBadCommit() async throws {
        let scratch = try await Scratch.copy("bisect")
        defer { scratch.remove() }
        let firstBad = try await scratch.oid("feature/graph-renderer~1")
        let store = try scratch.store()
        try await store.refresh()
        guard case .bisecting = store.snapshot?.state else {
            Issue.record("expected the bisect fixture to be bisecting")
            return
        }
        var outcome = BisectOutcome.testing(current: nil, remaining: nil)
        var steps = 0
        while case .testing = outcome, steps < 20 {
            let current = try await scratch.oid("HEAD")
            let contains = try await scratch.result(["merge-base", "--is-ancestor", firstBad.rawValue, current.rawValue]).exitCode == 0
            outcome = try await store.markBisect(contains ? .bad : .good)
            steps += 1
        }
        #expect(outcome == .found(firstBad))
        #expect(steps > 1)
        guard case .bisecting = store.snapshot?.state else {
            Issue.record("bisect should stay open until it ends")
            return
        }
        try await store.endBisect()
        #expect(try await scratch.git(["symbolic-ref", "HEAD"]) == Self.branch)
        #expect(OperationInProgress.current(gitDir: try await scratch.gitDir()) == nil)
        #expect(store.snapshot?.state == .clean)
        #expect(scratch.log.commands.contains("git bisect reset"))
    }

    @Test func startBisectSkipAndAbort() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        try await scratch.clean()
        let store = try scratch.store()
        let started = try await store.startBisect(bad: "feature/graph-renderer", good: "v0.9.0")
        guard case .testing(let current, let remaining) = started else {
            Issue.record("expected the bisect to start testing, got \(started)")
            return
        }
        #expect(current == (try await scratch.oid("HEAD")))
        #expect((remaining ?? 0) > 0)
        #expect(scratch.log.commands.contains("git bisect start feature/graph-renderer v0.9.0"))
        let skipped = try await store.markBisect(.skip)
        if case .testing(let next, _) = skipped { #expect(next != current) } else { Issue.record("expected another commit to test") }
        try await store.abort()
        #expect(try await scratch.git(["symbolic-ref", "HEAD"]) == Self.branch)
        #expect(OperationInProgress.current(gitDir: try await scratch.gitDir()) == nil)
    }
}
