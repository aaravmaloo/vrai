import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct CrossMilestoneTests {
    enum Rewrite: String, CaseIterable, Sendable {
        case merge, rebase, resetMixed, resetHard, cherryPick, revert, stashDrop
    }

    static func cleanCopy() async throws -> ScenarioCopy {
        let copy = try ScenarioCopy.make("everyday")
        _ = try await copy.git(["reset", "-q", "--hard"])
        _ = try await copy.git(["clean", "-qfd"])
        return copy
    }

    static func refs(_ copy: ScenarioCopy) async throws -> String {
        let refs = try await copy.git(["for-each-ref", "--format=%(refname) %(objectname)", "refs/heads", "refs/tags", "refs/stash"])
        let head = try await copy.git(["rev-parse", "HEAD"])
        let symbolic = try await copy.gitAllowingFailure(["symbolic-ref", "-q", "HEAD"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        return refs + "\nHEAD " + head + " " + symbolic
    }

    static func hookFailure(_ error: any Error, named hook: String) -> Bool {
        guard case .hookFailed(let name, let output) = (error as? GitError)?.code else { return false }
        return name == hook && output.contains("Keep it to 72 or fewer") && !output.contains("Not committing merge") && !output.contains("From file:")
    }

    @Test func pullStoppedByTheCommitMessageHookSaysWhichHook() async throws {
        let copy = try await Self.cleanCopy()
        defer { copy.remove() }
        let store = try await copy.store()
        await #expect { try await store.pull(mode: .merge) } throws: { Self.hookFailure($0, named: "commit-msg") }
        guard case .merging = store.snapshot?.state else {
            Issue.record("expected the merge to stay in progress, got \(String(describing: store.snapshot?.state))")
            return
        }
    }

    @Test func mergeStoppedByTheCommitMessageHookSaysWhichHook() async throws {
        let copy = try await Self.cleanCopy()
        defer { copy.remove() }
        let store = try await copy.store()
        let message = "Merge feature/line-staging so the graph and line staging can be reviewed together in one place"
        await #expect { try await store.merge(source: "feature/line-staging", mode: .mergeCommit, message: message) } throws: { Self.hookFailure($0, named: "commit-msg") }
    }

    @Test func deletedTagsComeBackFromUndo() async throws {
        let copy = try await Self.cleanCopy()
        defer { copy.remove() }
        let store = try await copy.store()
        let before = try await copy.git(["rev-parse", "refs/tags/v0.9.1"])
        _ = try await store.deleteTag(name: "v0.9.1")
        #expect(try await copy.gitAllowingFailure(["rev-parse", "--verify", "--quiet", "refs/tags/v0.9.1"]).exitCode != 0)
        let entry = try #require(try await store.undoHistory().first)
        #expect(entry.kind == .tagDelete)
        #expect(entry.label == "Deleted tag v0.9.1")
        try await store.undoLast()
        #expect(try await copy.git(["rev-parse", "refs/tags/v0.9.1"]) == before)
        #expect(try await copy.git(["cat-file", "-t", "refs/tags/v0.9.1"]) == "tag")
    }

    @Test func commitAndPushLandsOnTheRemote() async throws {
        let copy = try await Self.cleanCopy()
        defer { copy.remove() }
        _ = try await copy.git(["reset", "-q", "--hard", "origin/feature/graph-renderer"])
        try Data("probe\n".utf8).write(to: copy.repository.appending(path: "Probe.md"))
        let store = try await copy.store()
        try await store.stage(paths: ["Probe.md"])
        let tip = try await store.commit(subject: "Add a probe note", andPush: true)
        #expect(try await copy.remoteTip("origin", "refs/heads/feature/graph-renderer") == tip.rawValue)
        #expect(store.snapshot?.ahead == 0)
    }

    @Test(arguments: Rewrite.allCases)
    func everyRewriteComesBackFromUndoHistory(_ rewrite: Rewrite) async throws {
        let copy = try await Self.cleanCopy()
        defer { copy.remove() }
        let store = try await copy.store()
        let probe = copy.repository.appending(path: "Sources/VraiUI/History/GraphCell.swift")
        if rewrite == .resetHard { try Data("dirty\n".utf8).write(to: probe) }
        let dirty = try Data(contentsOf: probe)
        let before = try await Self.refs(copy)
        switch rewrite {
        case .merge:
            _ = try await store.merge(source: "feature/line-staging", mode: .mergeCommit, message: "Merge line staging")
        case .rebase:
            _ = try await store.rebase(onto: "origin/feature/graph-renderer")
        case .resetMixed:
            try await store.reset(to: "HEAD~2", mode: .mixed)
        case .resetHard:
            try await store.reset(to: "HEAD~1", mode: .hard)
        case .cherryPick:
            let first = try #require(OID(try await copy.git(["rev-parse", "feature/line-staging~1"])))
            let second = try #require(OID(try await copy.git(["rev-parse", "feature/line-staging"])))
            _ = try await store.cherryPick(ids: [first, second])
        case .revert:
            let head = try #require(OID(try await copy.git(["rev-parse", "HEAD"])))
            _ = try await store.revert(id: head)
        case .stashDrop:
            try await store.dropStash(index: 0)
        }
        #expect(try await Self.refs(copy) != before, "\(rewrite) changed nothing")
        let entry = try #require(try await store.undoHistory().first)
        let undone = try await store.undoLast()
        #expect(undone?.id == entry.id)
        #expect(try await Self.refs(copy) == before, "\(rewrite) did not come back")
        #expect(try Data(contentsOf: probe) == dirty, "\(rewrite) lost the worktree")
    }
}
