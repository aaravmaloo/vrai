import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct MergeStoreTests {
    static let lane = "Sources/VraiGit/Graph/LaneLayout.swift"
    static let cell = "Sources/VraiUI/History/GraphCell.swift"
    static let branch = "refs/heads/feature/graph-renderer"

    @Test func conflictScenarioResolvesBlockByBlockAndCommitsTheMerge() async throws {
        let scratch = try await Scratch.copy("conflict")
        defer { scratch.remove() }
        let store = try scratch.store()
        try await store.refresh()
        guard case .merging(let source) = store.snapshot?.state else {
            Issue.record("expected a merge in progress, got \(String(describing: store.snapshot?.state))")
            return
        }
        #expect(source == "mira/spike/metal-graph")
        #expect(store.snapshot?.conflicts.map(\.path).sorted() == [Self.lane, Self.cell])
        let head = try await scratch.oid("HEAD")
        let incoming = try await scratch.oid("MERGE_HEAD")
        let original = try scratch.file(Self.lane)
        #expect(ConflictResolver.conflicts(in: original).count == 2)
        let expected = try ConflictResolver.resolve(try ConflictResolver.resolve(original, block: 1, with: .ours), block: 1, with: .theirs)

        let early = await #expect(throws: GitError.self) { try await store.markResolved(path: Self.lane) }
        #expect(early?.code == .conflictMarkersRemain)

        try await store.resolve(path: Self.lane, block: 1, with: .ours)
        #expect(ConflictResolver.conflicts(in: try scratch.file(Self.lane)).count == 1)
        try await store.resolve(path: Self.lane, block: 1, with: .theirs)
        #expect(try scratch.file(Self.lane) == expected)
        try await store.markResolved(path: Self.lane)
        #expect(store.snapshot?.conflicts.map(\.path) == [Self.cell])

        let cellText = try scratch.file(Self.cell)
        try await store.resolve(path: Self.cell, block: 1, with: .both)
        #expect(try scratch.file(Self.cell) == ConflictResolver.resolve(cellText, block: 1, with: .both))
        try await store.markResolved(path: Self.cell)
        #expect(store.snapshot?.conflicts.isEmpty == true)

        let early2 = await store.recorded
        #expect(early2.isEmpty)
        try await store.continueOperation()
        #expect(try await scratch.git(["log", "-1", "--format=%P"]) == "\(head.rawValue) \(incoming.rawValue)")
        #expect(try await scratch.git(["log", "-1", "--format=%s"]) == "Merge branch 'mira/spike/metal-graph' into feature/graph-renderer")
        #expect(try await scratch.git(["show", "HEAD:" + Self.lane]) == expected.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(try await scratch.git(["diff", "--name-only", "--diff-filter=U"]).isEmpty)
        #expect(store.snapshot?.state == .clean)

        let entry = try #require(await store.recorded.first)
        #expect(entry.kind == .merge)
        #expect(entry.head == Self.branch)
        #expect(entry.refsBefore == [Self.branch: head])
        #expect(entry.label == "Merged mira/spike/metal-graph into feature/graph-renderer")
    }

    @Test func wholeFileChoicesUseCheckout() async throws {
        let scratch = try await Scratch.copy("conflict")
        defer { scratch.remove() }
        let store = try scratch.store()
        try await store.resolve(path: Self.lane, block: nil, with: .ours)
        #expect(try scratch.file(Self.lane).trimmingCharacters(in: .whitespacesAndNewlines) == (try await scratch.git(["show", "HEAD:" + Self.lane])))
        try await store.resolve(path: Self.cell, block: nil, with: .theirs)
        #expect(try scratch.file(Self.cell).trimmingCharacters(in: .whitespacesAndNewlines) == (try await scratch.git(["show", "MERGE_HEAD:" + Self.cell])))
        #expect(scratch.log.commands.contains("git checkout --ours -- \(Self.lane)"))
        try await store.markResolved(path: Self.lane)
        try await store.markResolved(path: Self.cell)
        #expect(try await scratch.git(["diff", "--name-only", "--diff-filter=U"]).isEmpty)
    }

    @Test func baseComesFromDiff3OrFromTheIndexStages() async throws {
        let scratch = try await Scratch.copy("edge", repository: "edge")
        defer { scratch.remove() }
        let store = try scratch.store()
        try await store.resolve(path: "conflict.txt", block: 1, with: .base)
        #expect(try scratch.file("conflict.txt").hasPrefix("line 1\nline 2\nline 3\n"))
        #expect(ConflictResolver.conflicts(in: try scratch.file("conflict.txt")).count == 1)

        try await scratch.git(["checkout", "--conflict=merge", "--", "conflict.txt"])
        #expect(ConflictResolver.needsBase(try scratch.file("conflict.txt"), block: nil))
        try await store.resolve(path: "conflict.txt", block: nil, with: .base)
        #expect(try scratch.file("conflict.txt") == (1...9).map { "line \($0)" }.joined(separator: "\n") + "\n")

        try await scratch.git(["checkout", "--conflict=merge", "--", "both-added.txt"])
        try await store.resolve(path: "both-added.txt", block: 1, with: .base)
        #expect(try scratch.file("both-added.txt") == "")
        try await store.markResolved(path: "both-added.txt")

        try await store.resolve(path: "deleted-by-them.txt", block: nil, with: .theirs)
        #expect(!scratch.exists("deleted-by-them.txt"))
        #expect(try await scratch.git(["status", "--porcelain", "--", "deleted-by-them.txt"]) == "D  deleted-by-them.txt")
    }

    @Test func abortPutsTheBranchBack() async throws {
        let scratch = try await Scratch.copy("conflict")
        defer { scratch.remove() }
        let store = try scratch.store()
        let head = try await scratch.oid("HEAD")
        try await store.abort()
        #expect(try await scratch.oid("HEAD") == head)
        #expect(!scratch.exists(".git/MERGE_HEAD"))
        #expect(try await scratch.git(["diff", "--name-only", "--diff-filter=U"]).isEmpty)
        #expect(store.snapshot?.state == .clean)
        #expect(scratch.log.commands.contains("git merge --abort"))
        try await store.abort()
        #expect(await store.recorded.isEmpty)
    }

    @Test func fastForwardOnly() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        try await scratch.clean()
        let store = try scratch.store()
        let diverged = await #expect(throws: GitError.self) { try await store.merge(source: "origin/main", mode: .fastForwardOnly) }
        #expect(diverged?.code == .notFastForward)
        try await scratch.git(["switch", "-q", "main"])
        let before = try await scratch.oid("main")
        let target = try await scratch.oid("origin/main")
        let outcome = try await store.merge(source: "origin/main", mode: .fastForwardOnly)
        #expect(outcome == .fastForwarded(to: target))
        #expect(try await scratch.oid("main") == target)
        let entry = try #require(await store.recorded.first)
        #expect(entry.kind == .merge)
        #expect(entry.head == "refs/heads/main")
        #expect(entry.refsBefore == ["refs/heads/main": before])
        #expect(entry.detail == "Fast-forward")
        #expect(await store.recorded.count == 1)
    }

    @Test func mergeCommitWithAMessageAndUpToDate() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        try await scratch.clean()
        let store = try scratch.store()
        let before = try await scratch.oid("HEAD")
        let outcome = try await store.merge(source: "origin/main", mode: .mergeCommit, message: "Merge the lane color docs")
        let tip = try await scratch.oid("HEAD")
        #expect(outcome == .merged(commit: tip))
        #expect(try await scratch.git(["log", "-1", "--format=%s"]) == "Merge the lane color docs")
        #expect(try await scratch.git(["log", "-1", "--format=%P"]) == "\(before.rawValue) \(try await scratch.oid("origin/main").rawValue)")
        #expect(scratch.log.commands.contains("git merge --no-ff -m \"Merge the lane color docs\" origin/main"))
        let entry = try #require(await store.recorded.first)
        #expect(entry.refsBefore == [Self.branch: before])
        #expect(entry.head == Self.branch)
        #expect(entry.detail == "Merge commit \(tip.short)")

        #expect(try await store.merge(source: "fix/rebase-banner") == .upToDate)
        #expect(await store.recorded.count == 1)
    }

    @Test func automaticMergeOfDivergedBranches() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        try await scratch.clean()
        let store = try scratch.store()
        let before = try await scratch.oid("HEAD")
        let outcome = try await store.merge(source: "feature/line-staging")
        guard case .merged(let commit) = outcome else {
            Issue.record("expected a merge commit, got \(outcome)")
            return
        }
        #expect(try await scratch.oid("HEAD^1") == before)
        #expect(try await scratch.oid("HEAD^2") == (try await scratch.oid("feature/line-staging")))
        #expect(commit == (try await scratch.oid("HEAD")))
        #expect(await store.recorded.first?.refsBefore == [Self.branch: before])
    }

    @Test func squashStagesTheChangesWithoutMovingTheBranch() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        try await scratch.clean()
        let store = try scratch.store()
        let before = try await scratch.oid("HEAD")
        #expect(try await store.merge(source: "feature/line-staging", mode: .squash) == .squashed)
        #expect(try await scratch.oid("HEAD") == before)
        let staged = try await scratch.git(["diff", "--cached", "--name-only"]).split(separator: "\n").map(String.init)
        #expect(staged.contains("Sources/VraiGit/Staging/LineSelection.swift"))
        #expect(staged.count == 4)
        #expect(await store.recorded.isEmpty)
    }

    @Test func mergeWithConflictsThrowsTheirPaths() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        try await scratch.clean()
        let store = try scratch.store()
        let error = await #expect(throws: GitError.self) { try await store.merge(source: "refs/remotes/mira/spike/metal-graph") }
        #expect(error?.code == .conflicts(paths: [Self.cell]))
        #expect(store.snapshot?.conflicts.map(\.path) == [Self.cell])
        guard case .merging = store.snapshot?.state else {
            Issue.record("expected the merge to stop")
            return
        }
        #expect(await store.recorded.isEmpty)
    }
}
