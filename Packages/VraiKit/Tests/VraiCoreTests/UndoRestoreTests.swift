import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct UndoRestoreTests {
    static let branch = "refs/heads/feature/graph-renderer"

    func clean(_ scenario: String = "everyday") async throws -> PrivateFixture {
        let fixture = try await PrivateFixture.copy(scenario, "vrai")
        try await fixture.run(["reset", "--hard", "-q"])
        try await fixture.run(["clean", "-fdq"])
        try await fixture.store.refresh()
        return fixture
    }

    func commitFile(_ fixture: PrivateFixture, _ path: String, _ text: String, _ message: String) async throws {
        try fixture.write(path, text)
        try await fixture.run(["add", "--", path])
        try await fixture.run(["commit", "-q", "-m", message])
    }

    func sideBranch(_ fixture: PrivateFixture, commits: Int) async throws -> [String] {
        try await fixture.run(["switch", "-q", "-c", "side", "HEAD~1"])
        var ids: [String] = []
        for index in 1...commits {
            try await commitFile(fixture, "Side/file\(index).txt", "side \(index)\n", "Side \(index)")
            ids.append(try await fixture.head())
        }
        try await fixture.run(["switch", "-q", "feature/graph-renderer"])
        return ids
    }

    func refEntry(_ kind: UndoEntry.Kind, _ fixture: PrivateFixture, ref: String = branch, label: String = "test") async throws -> UndoEntry {
        let tip = try #require(OID(try await fixture.output(["rev-parse", ref])))
        return UndoEntry(kind: kind, label: label, head: ref, refsBefore: [ref: tip])
    }

    @Test func journalLivesInTheCommonGitDirAndEveryObjectIsProtected() async throws {
        let fixture = try await PrivateFixture.everyday()
        let undo = fixture.store.undo
        let files = try await undo.snapshotFiles(["Sources/VraiGit/Graph/LaneLayout.swift", "Notes/graph-perf.md", "Resources/Graph.xcassets/Contents.json"])
        #expect(files["Resources/Graph.xcassets/Contents.json"]?.isZero == true)
        let patch = try await undo.storeBlob(Data("diff --git a/x b/x\n".utf8))
        let stash = try #require(OID(try await fixture.output(["rev-parse", "stash@{0}"])))
        let tip = try #require(OID(try await fixture.head()))
        let entry = UndoEntry(kind: .discardFile, label: "Discarded changes to 3 files", head: Self.branch, refsBefore: [Self.branch: tip], files: files, stashCommit: stash, patch: patch)
        try await undo.record(entry)

        let common = try await fixture.output(["rev-parse", "--path-format=absolute", "--git-common-dir"])
        let journal = URL(filePath: common).appending(path: "vrai/undo.json")
        #expect(try await undo.journalURL().standardizedFileURL == journal.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: journal.path(percentEncoded: false)))

        let refs = try await undo.refNames(of: entry.id)
        #expect(refs.count == 5)
        var protected: Set<String> = []
        for ref in refs {
            #expect(ref.hasPrefix("refs/vrai/undo/" + entry.id.uuidString + "/"))
            #expect(try await fixture.output(["cat-file", "-t", ref]) == "commit")
            protected.insert(try await fixture.output(["rev-parse", ref]))
            for row in try await fixture.output(["ls-tree", ref]).split(separator: "\n") {
                protected.insert(String(row.split(separator: "\t")[0].split(separator: " ")[2]))
            }
        }
        for oid in [tip, stash, patch] + files.values.filter({ !$0.isZero }) {
            #expect(protected.contains(oid.rawValue), "\(oid) is not protected")
        }

        try await fixture.run(["worktree", "add", "-q", "-b", "undo-worktree", fixture.repo.deletingLastPathComponent().appending(path: "undo-worktree").path(percentEncoded: false)])
        let linked = UndoStore(git: try Sandbox.git(at: fixture.repo.deletingLastPathComponent().appending(path: "undo-worktree")))
        #expect(try await linked.journalURL().standardizedFileURL == journal.standardizedFileURL)
        #expect(try await linked.recent().map(\.id) == [entry.id])

        try await undo.forget(entry.id)
        #expect(try await undo.refNames(of: entry.id).isEmpty)
        #expect(try await undo.recent().isEmpty)
    }

    @Test func entriesExpireAfterFourteenDaysWithTheirRefs() async throws {
        let fixture = try await PrivateFixture.everyday()
        let tip = try #require(OID(try await fixture.head()))
        let old = UndoEntry(kind: .branchDelete, label: "old", date: Date().addingTimeInterval(-15 * 24 * 3600), refsBefore: ["refs/heads/gone": tip])
        let recent = UndoEntry(kind: .branchDelete, label: "recent", date: Date().addingTimeInterval(-13 * 24 * 3600), refsBefore: ["refs/heads/kept": tip])
        try await fixture.store.undo.record(recent)
        try await fixture.store.undo.record(old)
        #expect(try await fixture.store.undo.refNames(of: old.id).count == 1)
        let history = try await fixture.store.undoHistory()
        #expect(history.map(\.label) == ["recent"])
        #expect(try await fixture.store.undo.refNames(of: old.id).isEmpty)
        #expect(try await fixture.store.undo.refNames(of: recent.id).count == 1)

        let later = UndoStore(git: fixture.git, now: { Date().addingTimeInterval(15 * 24 * 3600) })
        #expect(try await later.recent().isEmpty)
        #expect(try await later.refNames(of: recent.id).isEmpty)
        #expect(try await later.undoLast() == nil)
    }

    @Test func historyListsTheLatestFiftyNewestFirst() async throws {
        let fixture = try await PrivateFixture.everyday()
        for index in 0..<55 {
            try await fixture.store.undo.record(UndoEntry(kind: .discardLines, label: "entry \(index)", date: Date().addingTimeInterval(Double(index))))
        }
        let history = try await fixture.store.undoHistory()
        #expect(history.count == 50)
        #expect(history.first?.label == "entry 54")
        #expect(try await UndoStore(git: fixture.git).recent(limit: 100).count == 55)
    }

    @Test func deletedBranchesComeBack() async throws {
        let fixture = try await PrivateFixture.everyday()
        let entry = try await refEntry(.branchDelete, fixture, ref: "refs/heads/fix/rebase-banner", label: "Deleted branch fix/rebase-banner")
        try await fixture.store.undo.record(entry)
        try await fixture.run(["branch", "-D", "-q", "fix/rebase-banner"])
        try await fixture.store.refresh()
        #expect(fixture.store.snapshot?.branches.contains { $0.name == "fix/rebase-banner" } == false)

        let undone = try await fixture.store.undoLast()
        #expect(undone?.id == entry.id)
        #expect(try await fixture.output(["rev-parse", "refs/heads/fix/rebase-banner"]) == entry.refsBefore.values.first?.rawValue)
        #expect(fixture.store.snapshot?.branches.contains { $0.name == "fix/rebase-banner" } == true)
        await expectGitError("undoNoLongerApplies") {
            try await fixture.store.restore(entry)
        }
    }

    @Test func droppedStashesComeBackWithTheirMessage() async throws {
        let fixture = try await PrivateFixture.everyday()
        let oid = try #require(OID(try await fixture.output(["rev-parse", "stash@{0}"])))
        let message = try await fixture.output(["log", "-g", "-1", "--format=%gs", "refs/stash"])
        try await fixture.store.undo.record(UndoEntry(kind: .stashDrop, label: "Dropped stash@{0}", stashCommit: oid, message: message))
        try await fixture.run(["stash", "drop", "-q", "stash@{0}"])
        #expect(!(try await fixture.output(["stash", "list", "--format=%H"])).contains(oid.rawValue))
        try await fixture.store.undoLast()
        let listed = try await fixture.output(["stash", "list", "--format=%H %gs"])
        #expect(listed.split(separator: "\n").first == Substring(oid.rawValue + " " + message))
        #expect(fixture.store.snapshot?.stashes.count == 3)
    }

    @Test func mergesAreUndoneAndRefusedOnceTheBranchMovedOn() async throws {
        let fixture = try await clean()
        _ = try await sideBranch(fixture, commits: 1)
        let entry = try await refEntry(.merge, fixture, label: "Merged side into feature/graph-renderer")
        try await fixture.store.undo.record(entry)
        try await fixture.run(["merge", "-q", "--no-ff", "-m", "Merge side", "side"])
        #expect(fixture.exists("Side/file1.txt"))
        try await fixture.store.undoLast()
        #expect(try await fixture.head() == entry.refsBefore[Self.branch]?.rawValue)
        #expect(!fixture.exists("Side/file1.txt"))

        let again = try await refEntry(.merge, fixture)
        try await fixture.store.undo.record(again)
        try await fixture.run(["merge", "-q", "--no-ff", "-m", "Merge side", "side"])
        try await commitFile(fixture, "Notes/after.md", "after\n", "After the merge")
        let moved = try await fixture.head()
        await expectGitError("undoNoLongerApplies") {
            try await fixture.store.undoLast()
        }
        #expect(try await fixture.head() == moved)
    }

    @Test func softMixedAndKeepResetsAreUndone() async throws {
        let fixture = try await clean()
        let tip = try await fixture.head()
        for mode in ["--soft", "--mixed", "--keep"] {
            try await fixture.store.undo.record(try await refEntry(.reset, fixture, label: "Reset " + mode))
            try await fixture.run(["reset", "-q", mode, "HEAD~2"])
            #expect(try await fixture.head() != tip)
            try await fixture.store.undoLast()
            #expect(try await fixture.head() == tip, "\(mode)")
            #expect(try await fixture.output(["diff", "--cached", "--name-only"]).isEmpty, "\(mode)")
            #expect(try await fixture.output(["diff", "--name-only", "--ignore-submodules"]).isEmpty, "\(mode)")
        }
    }

    @Test func hardResetsComeBackWithTheDirtyWorktree() async throws {
        let fixture = try await clean()
        let path = "Sources/VraiGit/Graph/LaneLayout.swift"
        let dirty = Data("dirty before the hard reset\n".utf8)
        try fixture.write(path, dirty)
        let stash = try #require(OID(try await fixture.output(["stash", "create"])))
        var entry = try await refEntry(.resetHard, fixture, label: "Reset feature/graph-renderer (hard)")
        entry.stashCommit = stash
        try await fixture.store.undo.record(entry)
        try await fixture.run(["reset", "-q", "--hard", "HEAD~1"])
        #expect(fixture.read(path) != dirty)
        try await fixture.store.undoLast()
        #expect(try await fixture.head() == entry.refsBefore[Self.branch]?.rawValue)
        #expect(fixture.read(path) == dirty)
    }

    @Test func cherryPicksAndRevertsAreUndone() async throws {
        let fixture = try await clean()
        let ids = try await sideBranch(fixture, commits: 2)
        let pick = try await refEntry(.cherryPick, fixture, label: "Cherry-picked 2 commits")
        try await fixture.store.undo.record(pick)
        try await fixture.run(["cherry-pick", ids[0], ids[1]])
        #expect(fixture.exists("Side/file2.txt"))
        try await fixture.store.undoLast()
        #expect(try await fixture.head() == pick.refsBefore[Self.branch]?.rawValue)
        #expect(!fixture.exists("Side/file2.txt"))

        let revert = try await refEntry(.revert, fixture, label: "Reverted HEAD")
        try await fixture.store.undo.record(revert)
        try await fixture.run(["revert", "--no-edit", "HEAD"])
        try await fixture.store.undoLast()
        #expect(try await fixture.head() == revert.refsBefore[Self.branch]?.rawValue)
        #expect(try await fixture.output(["status", "--porcelain", "--ignore-submodules"]).isEmpty)
    }

    @Test func rebasesAreUndone() async throws {
        let fixture = try await clean()
        _ = try await sideBranch(fixture, commits: 2)
        try await fixture.run(["switch", "-q", "side"])
        let entry = try await refEntry(.rebase, fixture, ref: "refs/heads/side", label: "Rebased side onto feature/graph-renderer")
        try await fixture.store.undo.record(entry)
        try await fixture.run(["rebase", "-q", "feature/graph-renderer"])
        #expect(try await fixture.head() != entry.refsBefore["refs/heads/side"]?.rawValue)
        try await fixture.store.undoLast()
        #expect(try await fixture.head() == entry.refsBefore["refs/heads/side"]?.rawValue)
        #expect(try await fixture.output(["symbolic-ref", "HEAD"]) == "refs/heads/side")
    }

    @Test func rewritesOfABranchThatIsNotCheckedOutMoveOnlyTheRef() async throws {
        let fixture = try await clean()
        let ids = try await sideBranch(fixture, commits: 1)
        let entry = try await refEntry(.rebase, fixture, ref: "refs/heads/side", label: "Rebased side in the background")
        try await fixture.store.undo.record(entry)
        try await fixture.run(["update-ref", "refs/heads/side", "HEAD"])
        let head = try await fixture.head()
        try await fixture.store.undoLast()
        #expect(try await fixture.output(["rev-parse", "refs/heads/side"]) == ids[0])
        #expect(try await fixture.head() == head)
    }

    @Test func pullsAreUndone() async throws {
        let fixture = try await clean("push-rejected")
        let entry = try await refEntry(.pull, fixture, label: "Pulled 1 commit from origin/feature/graph-renderer")
        try await fixture.store.undo.record(entry)
        try await fixture.run(["pull", "-q", "--no-rebase", "--no-edit", "--no-verify", "origin", "feature/graph-renderer"])
        #expect(try await fixture.head() != entry.refsBefore[Self.branch]?.rawValue)
        try await fixture.store.undoLast()
        #expect(try await fixture.head() == entry.refsBefore[Self.branch]?.rawValue)
        #expect(try await fixture.output(["status", "--porcelain", "--ignore-submodules"]).isEmpty)
    }

    @Test func commitsOnADetachedHeadAreUndone() async throws {
        let fixture = try await clean()
        try await fixture.run(["switch", "-q", "--detach", "HEAD"])
        let before = try await fixture.head()
        try fixture.write("Notes/detached.md", "detached\n")
        try await fixture.store.stage(paths: ["Notes/detached.md"])
        try await fixture.store.commit(subject: "Commit while detached")
        let entry = try #require(try await fixture.store.undoHistory().first)
        #expect(entry.head == before)
        #expect(entry.refsBefore["HEAD"]?.rawValue == before)
        try await fixture.store.undoLast()
        #expect(try await fixture.head() == before)
        #expect(try await fixture.git.runAllowingFailure(.read(["symbolic-ref", "-q", "HEAD"])).exitCode == 1)
        #expect(try await fixture.output(["diff", "--cached", "--name-only"]) == "Notes/detached.md")
    }

    @Test func entriesOfFailedActionsDoNotApply() async throws {
        let fixture = try await clean()
        let entry = try await refEntry(.merge, fixture)
        try await fixture.store.undo.record(entry)
        let failed = try await fixture.git.runAllowingFailure(.write(["merge", "no-such-branch"]))
        #expect(!failed.succeeded)
        try await commitFile(fixture, "Notes/unrelated.md", "unrelated\n", "Unrelated commit")
        let head = try await fixture.head()
        await expectGitError("undoNoLongerApplies") {
            try await fixture.store.restore(entry)
        }
        #expect(try await fixture.head() == head)
    }

    @Test func undoLastSkipsEntriesWhoseActionChangedNothing() async throws {
        let fixture = try await clean()
        try fixture.write("Notes/halo.md", "halo\n")
        try await fixture.store.stage(paths: ["Notes/halo.md"])
        try await fixture.store.commit(subject: "Write halo notes")
        let committed = try #require(try await fixture.store.undoHistory().first)
        let failedMerge = try await refEntry(.merge, fixture)
        try await fixture.store.undo.record(failedMerge)
        #expect(try await !fixture.git.runAllowingFailure(.write(["merge", "no-such-branch"])).succeeded)
        let undone = try await fixture.store.undoLast()
        #expect(undone?.id == committed.id)
        #expect(try await fixture.store.undoHistory().contains { $0.id == failedMerge.id } == false)
        #expect(try await fixture.output(["diff", "--cached", "--name-only"]) == "Notes/halo.md")
    }

    @Test func refsAreLeftAloneWhileAMergeIsInProgress() async throws {
        let fixture = try await PrivateFixture.copy("conflict", "vrai")
        let head = try await fixture.head()
        try await fixture.store.undo.record(try await refEntry(.reset, fixture, label: "Reset"))
        await expectGitError("undoNoLongerApplies") {
            try await fixture.store.undoLast()
        }
        #expect(try await fixture.head() == head)
        #expect(fixture.store.snapshot?.state.isOperationInProgress == true)
    }

    @Test func deletedTagsComeBackAsTheSameTagObject() async throws {
        let fixture = try await PrivateFixture.everyday()
        let ref = "refs/tags/v0.9.1"
        let tag = try #require(OID(try await fixture.output(["rev-parse", ref])))
        #expect(try await fixture.output(["cat-file", "-t", tag.rawValue]) == "tag")
        let entry = UndoEntry(kind: .tagDelete, label: "Deleted tag v0.9.1", refsBefore: [ref: tag])
        try await fixture.store.undo.record(entry)
        let protected = try await fixture.store.undo.refNames(of: entry.id)
        #expect(protected.count == 1)
        #expect(try await fixture.output(["rev-parse", protected[0]]) == tag.rawValue)
        try await fixture.run(["tag", "-d", "v0.9.1"])
        try await fixture.run(["reflog", "expire", "--expire=now", "--all"])
        try await fixture.run(["gc", "-q", "--prune=now"])

        let undone = try await fixture.store.undoLast()
        #expect(undone?.kind == .tagDelete)
        #expect(try await fixture.output(["rev-parse", ref]) == tag.rawValue)
        #expect(try await fixture.output(["cat-file", "-t", ref]) == "tag")
        #expect(fixture.store.snapshot?.tags.first { $0.name == "v0.9.1" }?.annotated == true)
        #expect(try await fixture.store.undo.refNames(of: entry.id).isEmpty)

        let again = UndoEntry(kind: .tagDelete, label: "Deleted tag v0.9.1", refsBefore: [ref: tag])
        try await fixture.store.undo.record(again)
        try await fixture.run(["tag", "-d", "v0.9.1"])
        try await fixture.run(["tag", "v0.9.1", "HEAD"])
        let replaced = try await fixture.output(["rev-parse", ref])
        await expectGitError("undoNoLongerApplies") {
            try await fixture.store.restore(again)
        }
        #expect(try await fixture.output(["rev-parse", ref]) == replaced)
    }
}
