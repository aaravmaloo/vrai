import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct ReadSideTests {
    static func privateCopy(_ scenario: String) throws -> URL {
        let target = Sandbox.root.appending(path: "tests/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Sandbox.root.appending(path: "fixtures/\(scenario)", directoryHint: .isDirectory), to: target)
        return target
    }

    @Test func openLoadsHistoryWithTheWipRowAboveHead() async throws {
        let store = RepositoryStore(git: try Sandbox.git("everyday/vrai"))
        await store.open(watch: false)
        let snapshot = try #require(store.snapshot)
        #expect(store.history.phase == .loaded)
        #expect(store.history.isComplete)
        #expect(store.history.commits.count == 32)
        #expect(store.history.rows.count == store.history.commits.count)
        let wip = try #require(store.history.wipRow)
        #expect(wip.id == RepositoryStore.wipID)
        #expect(wip.bottom.contains { $0.kind == .outgoing })
        #expect(store.history.rows.first { $0.id == snapshot.headOID }?.isHead == true)
        #expect(store.selection == .wip)
        #expect(store.wipFiles.count == snapshot.working.count)
    }

    @Test func selectingACommitLoadsDetailPatchAndInspector() async throws {
        let store = RepositoryStore(git: try Sandbox.git("everyday/vrai"))
        await store.open(watch: false)
        let head = try #require(store.snapshot?.headOID)
        store.select(.commit(head))
        try await waitUntil { store.detailState == .loaded && store.patchState == .loaded && store.inspectorInfo != nil }
        let detail = try #require(store.detail)
        #expect(detail.commit.id == head)
        #expect(store.selectedPath == detail.files.first?.path)
        let patch = try #require(store.patch)
        #expect(!patch.hunks.isEmpty)
        #expect(store.inspectorInfo?.branches.contains("feature/graph-renderer") == true)
        #expect(store.inspectorInfo?.describe?.isEmpty == false)
    }

    @Test func wipPatchCoversTrackedAndUntrackedFiles() async throws {
        let store = RepositoryStore(git: try Sandbox.git("everyday/vrai"))
        await store.open(watch: false)
        let untracked = try #require(store.wipFiles.first { $0.status == .untracked && !$0.isSubmodule })
        store.selectFile(untracked.path)
        try await waitUntil { store.patchState == .loaded }
        #expect(store.patch?.hunks.first?.lines.allSatisfy { $0.kind == .add } == true)
        let modified = try #require(store.wipFiles.first { $0.status == .modified && !$0.isSubmodule })
        store.selectFile(modified.path)
        try await waitUntil { store.patchState == .loaded && store.patch?.path == modified.path }
        #expect(store.patch?.hunks.isEmpty == false)
    }

    @Test func showRefSelectsTheTipAndScrolls() async throws {
        let store = RepositoryStore(git: try Sandbox.git("everyday/vrai"))
        await store.open(watch: false)
        let main = try #require(store.snapshot?.branches.first { $0.name == "main" })
        store.showRef("main")
        #expect(store.selection == .commit(main.tip))
        #expect(store.scrollRequest?.target == .commit(main.tip))
    }

    @Test func detachedStateKnowsThePreviousBranch() async throws {
        let store = RepositoryStore(git: try Sandbox.git("detached/vrai"))
        await store.open(watch: false)
        #expect(store.stateDetails.previousBranch == "feature/graph-renderer")
        guard case .detached(let id, _)? = store.snapshot?.state else {
            Issue.record("expected a detached HEAD")
            return
        }
        #expect(store.selection == .commit(id))
    }

    @Test func bisectStateHasProgressAndSelectsTheCurrentCommit() async throws {
        let store = RepositoryStore(git: try Sandbox.git("bisect/vrai"))
        await store.open(watch: false)
        guard case .bisecting(_, _, let current?, _)? = store.snapshot?.state else {
            Issue.record("expected bisecting")
            return
        }
        #expect(store.selection == .commit(current))
        #expect((store.stateDetails.bisect?.steps ?? 0) > 0)
        #expect(store.stateDetails.subject?.isEmpty == false)
    }

    @Test func rebaseStateNamesOntoAndTheStoppedCommit() async throws {
        let store = RepositoryStore(git: try Sandbox.git("rebase/vrai"))
        await store.open(watch: false)
        #expect(store.stateDetails.ontoName == "origin/main")
        #expect(store.stateDetails.subject?.isEmpty == false)
    }

    @Test func emptyRepositoryHasNoRowsButAnUncommittedSelection() async throws {
        let store = RepositoryStore(git: try Sandbox.git("empty/pocket-notes"))
        await store.open(watch: false)
        #expect(store.history.phase == .loaded)
        #expect(store.history.commits.isEmpty)
        #expect(store.history.wipRow == nil)
        #expect(store.selection == .wip)
        try await waitUntil { store.patchState == .loaded }
        #expect(store.patch?.hunks.isEmpty == false)
    }

    @Test func signaturesLoadInASecondPass() async throws {
        let store = RepositoryStore(git: try Sandbox.git("everyday/vrai"))
        await store.open(watch: false)
        let ids = Array(store.history.commits.prefix(8).map(\.id))
        store.requestSignatures(for: ids)
        try await waitUntil { ids.allSatisfy { store.signatures[$0] != nil } }
        #expect(store.signatures.values.contains(.verified))
    }

    @Test func outsideCommitAppearsWithoutARefresh() async throws {
        let copy = try Self.privateCopy("everyday")
        defer { try? FileManager.default.removeItem(at: copy) }
        let repository = copy.appending(path: "vrai", directoryHint: .isDirectory)
        let store = RepositoryStore(git: try Sandbox.git(at: repository))
        await store.open(watch: true)
        defer { store.close() }
        #expect(store.isWatching)
        let before = store.history.commits.count
        try await Task.sleep(for: .milliseconds(200))
        let outside = try Sandbox.git(at: repository)
        try await outside.run(.write(["commit", "--allow-empty", "-m", "test"]))
        try await waitUntil(timeout: .seconds(20)) { store.history.commits.first?.subject == "test" }
        #expect(store.history.commits.count == before + 1)
    }

    @Test func watcherClassifiesGitPaths() {
        let root = URL(filePath: "/tmp/vrai-sandbox/r", directoryHint: .isDirectory)
        let watcher = RepositoryWatcher(root: root, gitDir: root.appending(path: ".git"), commonDir: root.appending(path: ".git")) { _ in }
        #expect(watcher.classify("/tmp/vrai-sandbox/r/.git/HEAD") == .head)
        #expect(watcher.classify("/private/tmp/vrai-sandbox/r/.git/refs/heads/main") == .refs)
        #expect(watcher.classify("/tmp/vrai-sandbox/r/.git/objects/ab/cdef") == nil)
        #expect(watcher.classify("/tmp/vrai-sandbox/r/.git/index.lock") == nil)
        #expect(watcher.classify("/tmp/vrai-sandbox/r/.git/index") == .index)
        #expect(watcher.classify("/tmp/vrai-sandbox/r/Sources/a.swift") == .worktree)
        #expect(watcher.classify("/tmp/vrai-sandbox/r/.git/rebase-merge/done") == .state)
        #expect(watcher.watchedPaths == ["/tmp/vrai-sandbox/r"])
    }
}

@MainActor
func waitUntil(timeout: Duration = .seconds(10), _ condition: () -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        if clock.now > deadline {
            Issue.record("timed out")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
