import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct PickResetStoreTests {
    static let branch = "refs/heads/feature/graph-renderer"
    static let lane = "Sources/VraiGit/Graph/LaneLayout.swift"
    static let cell = "Sources/VraiUI/History/GraphCell.swift"

    @Test func cherryPickRecordsTheOrigin() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        try await scratch.clean()
        let before = try await scratch.oid("HEAD")
        let docs = try await scratch.oid("origin/main")
        let store = try scratch.store()
        try await store.cherryPick(ids: [docs], recordOrigin: true)
        #expect(try await scratch.oid("HEAD~1") == before)
        #expect(try await scratch.git(["log", "-1", "--format=%B"]).hasSuffix("(cherry picked from commit \(docs.rawValue))"))
        #expect(scratch.log.commands.contains("git cherry-pick -x \(docs.rawValue)"))
        let entry = try #require(await store.recorded.first)
        #expect(entry.kind == .cherryPick)
        #expect(entry.head == Self.branch)
        #expect(entry.refsBefore == [Self.branch: before])
        #expect(entry.label == "Cherry-picked \(docs.short) onto feature/graph-renderer")
    }

    @Test func cherryPickWithoutCommittingStagesOnly() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        try await scratch.clean()
        let before = try await scratch.oid("HEAD")
        let store = try scratch.store()
        try await store.cherryPick(ids: [try await scratch.oid("origin/main")], noCommit: true)
        #expect(try await scratch.oid("HEAD") == before)
        #expect(!(try await scratch.git(["diff", "--cached", "--name-only"])).isEmpty)
        #expect(await store.recorded.isEmpty)
    }

    @Test func emptyCherryPickCanBeSkipped() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        try await scratch.clean()
        let before = try await scratch.oid("HEAD")
        let store = try scratch.store()
        let error = await #expect(throws: GitError.self) { try await store.cherryPick(ids: [before]) }
        #expect(error?.code == .emptyCommit)
        guard case .cherryPicking = store.snapshot?.state else {
            Issue.record("expected a cherry-pick in progress")
            return
        }
        try await store.skipStep()
        #expect(OperationInProgress.current(gitDir: try await scratch.gitDir()) == nil)
        #expect(try await scratch.oid("HEAD") == before)
        #expect(await store.recorded.isEmpty)
    }

    @Test func conflictedCherryPickResolvesAndContinues() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        try await scratch.clean()
        let before = try await scratch.oid("HEAD")
        let metal = try await scratch.oid("refs/remotes/mira/spike/metal-graph")
        let store = try scratch.store()
        let error = await #expect(throws: GitError.self) { try await store.cherryPick(ids: [metal]) }
        #expect(error?.code == .conflicts(paths: [Self.cell]))
        guard case .cherryPicking(let picking) = store.snapshot?.state else {
            Issue.record("expected a cherry-pick in progress")
            return
        }
        #expect(picking == metal)
        let early = await #expect(throws: GitError.self) { try await store.continueOperation() }
        #expect(early?.code == .unresolvedConflicts)
        try await store.resolve(path: Self.cell, block: nil, with: .theirs)
        try await store.markResolved(path: Self.cell)
        try await store.continueOperation()
        #expect(OperationInProgress.current(gitDir: try await scratch.gitDir()) == nil)
        #expect(try await scratch.oid("HEAD~1") == before)
        let picked = try await scratch.git(["show", "HEAD:" + Self.cell])
        let incoming = try await scratch.git(["show", "\(metal.rawValue):" + Self.cell])
        #expect(picked == incoming)
        #expect(try await scratch.git(["log", "-1", "--format=%s"]) == "Metal: draw lanes with instanced quads")
        let entry = try #require(await store.recorded.first)
        #expect(entry.kind == .cherryPick)
        #expect(entry.refsBefore == [Self.branch: before])
        #expect(entry.label == "Cherry-picked \(metal.short) onto feature/graph-renderer")
    }

    @Test func conflictedRevertResolvesAndContinues() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        try await scratch.clean()
        try Data("first\n".utf8).write(to: scratch.repository.appending(path: "README.md"))
        try await scratch.git(["commit", "-q", "-am", "Docs: first readme"])
        let first = try await scratch.oid("HEAD")
        try Data("second\n".utf8).write(to: scratch.repository.appending(path: "README.md"))
        try await scratch.git(["commit", "-q", "-am", "Docs: second readme"])
        let before = try await scratch.oid("HEAD")
        let store = try scratch.store()
        let error = await #expect(throws: GitError.self) { try await store.revert(id: first) }
        #expect(error?.code == .conflicts(paths: ["README.md"]))
        guard case .reverting(let reverting) = store.snapshot?.state else {
            Issue.record("expected a revert in progress")
            return
        }
        #expect(reverting == first)
        let original = try await scratch.git(["show", "\(first.rawValue)~1:README.md"])
        try await store.resolve(path: "README.md", block: 1, with: .theirs)
        #expect(try scratch.file("README.md").trimmingCharacters(in: .whitespacesAndNewlines) == original)
        try await store.markResolved(path: "README.md")
        try await store.continueOperation()
        #expect(OperationInProgress.current(gitDir: try await scratch.gitDir()) == nil)
        #expect(try await scratch.oid("HEAD~1") == before)
        #expect(try await scratch.git(["log", "-1", "--format=%s"]) == "Revert \"Docs: first readme\"")
        let entry = try #require(await store.recorded.first)
        #expect(entry.kind == .revert)
        #expect(entry.refsBefore == [Self.branch: before])
        #expect(entry.label == "Reverted \(first.short)")
    }

    @Test func abortedCherryPickLeavesNoTrace() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        try await scratch.clean()
        let before = try await scratch.oid("HEAD")
        let store = try scratch.store()
        _ = await #expect(throws: GitError.self) { try await store.cherryPick(ids: [try await scratch.oid("refs/remotes/mira/spike/metal-graph")]) }
        try await store.abort()
        #expect(scratch.log.commands.contains("git cherry-pick --abort"))
        #expect(try await scratch.oid("HEAD") == before)
        #expect(OperationInProgress.current(gitDir: try await scratch.gitDir()) == nil)
    }

    @Test func revertMakesTheUndoingCommit() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        try await scratch.clean()
        let before = try await scratch.oid("HEAD")
        let store = try scratch.store()
        try await store.revert(id: before)
        #expect(try await scratch.git(["log", "-1", "--format=%s"]) == "Revert \"Graph: draw merge curves with cubic béziers\"")
        #expect(try await scratch.oid("HEAD~1") == before)
        #expect(scratch.log.commands.contains("git revert --no-edit \(before.rawValue)"))
        let entry = try #require(await store.recorded.first)
        #expect(entry.kind == .revert)
        #expect(entry.refsBefore == [Self.branch: before])
        #expect(entry.label == "Reverted \(before.short)")
        #expect(entry.detail == "Revert \"Graph: draw merge curves with cubic béziers\"")

        try await scratch.git(["switch", "-q", "main"])
        let merge = try await scratch.oid("main")
        try await store.revert(id: merge, mainline: 1)
        #expect(try await scratch.oid("HEAD~1") == merge)
        #expect(await store.recorded.first?.refsBefore == ["refs/heads/main": merge])
    }

    @Test func revertOnADetachedHeadRecordsTheCommit() async throws {
        let scratch = try await Scratch.copy("detached")
        defer { scratch.remove() }
        let before = try await scratch.oid("HEAD")
        let store = try scratch.store()
        try await store.revert(id: before)
        #expect(try await scratch.oid("HEAD~1") == before)
        let entry = try #require(await store.recorded.first)
        #expect(entry.head == before.rawValue)
        #expect(entry.refsBefore == ["HEAD": before])
    }

    @Test func softMixedAndKeepResets() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        let store = try scratch.store()
        let dirty = try await scratch.oid("HEAD")
        let refused = await #expect(throws: GitError.self) { try await store.reset(to: "HEAD~1", mode: .keep) }
        guard case .localChangesWouldBeOverwritten(let paths) = refused?.code else {
            Issue.record("expected localChangesWouldBeOverwritten, got \(String(describing: refused))")
            return
        }
        #expect(!paths.isEmpty)
        #expect(try await scratch.oid("HEAD") == dirty)
        #expect(await store.recorded.isEmpty)

        try await scratch.clean()
        let before = try await scratch.oid("HEAD")
        try await store.reset(to: "HEAD~2", mode: .soft)
        #expect(try await scratch.oid("HEAD") == (try await scratch.oid("\(before.rawValue)~2")))
        #expect(!(try await scratch.git(["diff", "--cached", "--name-only"])).isEmpty)
        var entry = try #require(await store.recorded.first)
        #expect(entry.kind == .reset)
        #expect(entry.refsBefore == [Self.branch: before])
        #expect(entry.head == Self.branch)
        #expect(entry.detail == "ORIG_HEAD \(before.short)")

        let soft = try await scratch.oid("HEAD")
        try await store.reset(to: "HEAD~1", mode: .mixed)
        #expect(try await scratch.git(["diff", "--cached", "--name-only"]).isEmpty)
        #expect(!(try await scratch.git(["diff", "--name-only"])).isEmpty)
        entry = try #require(await store.recorded.first)
        #expect(entry.refsBefore == [Self.branch: soft])

        try await scratch.clean()
        let mixed = try await scratch.oid("HEAD")
        try await store.reset(to: before.rawValue, mode: .keep)
        #expect(try await scratch.oid("HEAD") == before)
        entry = try #require(await store.recorded.first)
        #expect(entry.kind == .reset)
        #expect(entry.refsBefore == [Self.branch: mixed])
        #expect(await store.recorded.count == 3)
    }

    @Test func hardResetKeepsACopyOfTheDirtyWorktree() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        let before = try await scratch.oid("HEAD")
        let store = try scratch.store()
        try await store.reset(to: "HEAD", mode: .hard)
        #expect(try await scratch.git(["status", "--porcelain", "--untracked-files=no", "--ignore-submodules"]).isEmpty)
        let entry = try #require(await store.recorded.first)
        #expect(entry.kind == .resetHard)
        #expect(entry.head == Self.branch)
        #expect(entry.refsBefore == [Self.branch: before])
        let stash = try #require(entry.stashCommit)
        #expect(try await scratch.oid("\(stash.rawValue)^1") == before)
        let saved = try await scratch.git(["diff", "--name-only", "\(stash.rawValue)^1", stash.rawValue])
        #expect(saved.contains(Self.lane))
        #expect(saved.contains(Self.cell))
        #expect(scratch.log.commands.contains("git stash create"))

        try await store.reset(to: "HEAD~1", mode: .hard)
        let clean = try #require(await store.recorded.first)
        #expect(clean.kind == .resetHard)
        #expect(clean.stashCommit == nil)
        #expect(clean.refsBefore == [Self.branch: before])
        #expect(try await scratch.oid("HEAD") == (try await scratch.oid("\(before.rawValue)~1")))
    }
}
