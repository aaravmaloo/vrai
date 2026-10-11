import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct BranchStoreTests {
    @Test func createBranchAndSwitchToIt() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let store = try await copy.store()
        let head = try #require(try await copy.tip("HEAD"))
        let summary = try await store.createBranch(name: "feature/halo", switchTo: true)
        #expect(try await copy.tip("refs/heads/feature/halo") == head)
        #expect(try await copy.git(["symbolic-ref", "--short", "HEAD"]) == "feature/halo")
        #expect(summary.message == "Created and switched to feature/halo")
        #expect(summary.detail == "From \(head.prefix(7)).")
        #expect(store.snapshot?.head == .branch("feature/halo"))
        #expect(store.createBranchCommand(name: "x", from: "main", switchTo: true).display == "git switch -c x main")
    }

    @Test func createBranchWithoutSwitching() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let store = try await copy.store()
        let summary = try await store.createBranch(name: "from-main", from: "main", switchTo: false)
        #expect(try await copy.tip("refs/heads/from-main") == copy.tip("refs/heads/main"))
        #expect(try await copy.git(["symbolic-ref", "--short", "HEAD"]) == "feature/graph-renderer")
        #expect(summary.message == "Created branch from-main")
        #expect(summary.detail == "From main.")
    }

    @Test func createBranchAndPublish() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let store = try await copy.store()
        try await store.createBranch(name: "published", switchTo: false, publish: true)
        #expect(try await copy.remoteTip("origin", "refs/heads/published") == copy.tip("refs/heads/published"))
        #expect(try await copy.config("branch.published.remote") == "origin")
        #expect(try await copy.config("branch.published.merge") == "refs/heads/published")
        #expect(store.snapshot?.branches.first { $0.name == "published" }?.upstream == "origin/published")
    }

    @Test func createBranchErrors() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let store = try await copy.store()
        await expectCode("invalidRefName") { try await store.createBranch(name: "bad..name") }
        await expectCode("refExists") { try await store.createBranch(name: "main") }
        await expectCode("refExists") { try await store.createBranch(name: "main", switchTo: false) }
        #expect(store.busy.isEmpty)
    }

    @Test func switchRefusesToOverwriteChangesThenStashes() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let store = try await copy.store()
        let error = await expectCode("localChangesWouldBeOverwritten") { try await store.switchTo(branch: "main") }
        if case .localChangesWouldBeOverwritten(let paths)? = error?.code {
            #expect(paths.contains("Sources/VraiGit/Graph/LaneLayout.swift"))
        }
        let bring = await expectCode("localChangesWouldBeOverwritten") { try await store.switchTo(branch: "main", carry: .bring) }
        if case .localChangesWouldBeOverwritten(let paths)? = bring?.code {
            #expect(paths.contains("Sources/VraiUI/History/GraphCell.swift"))
        }
        let stashesBefore = try await copy.git(["stash", "list"]).split(separator: "\n").count
        let summary = try await store.switchTo(branch: "main", carry: .stash)
        #expect(try await copy.git(["symbolic-ref", "--short", "HEAD"]) == "main")
        #expect(try await copy.git(["stash", "list"]).split(separator: "\n").count == stashesBefore + 1)
        #expect(summary.detail == "Your changes are in stash@{0}.")
        #expect(store.snapshot?.head == .branch("main"))
    }

    @Test func bringAlongMergesChangesIntoTheOtherBranch() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        try await copy.clean()
        let lines = (1...12).map { "line \($0)" }
        _ = try await copy.commit(in: copy.repository, file: "bring.txt", contents: lines.joined(separator: "\n") + "\n", message: "Add bring")
        _ = try await copy.git(["switch", "-q", "-c", "left"])
        var left = lines
        left[0] = "line 1 on left"
        _ = try await copy.commit(in: copy.repository, file: "bring.txt", contents: left.joined(separator: "\n") + "\n", message: "Change left")
        _ = try await copy.git(["switch", "-q", "-"])
        var dirty = lines
        dirty[11] = "line 12 edited"
        try Data((dirty.joined(separator: "\n") + "\n").utf8).write(to: copy.repository.appending(path: "bring.txt"))
        let store = try await copy.store()
        let summary = try await store.switchTo(branch: "left", carry: .bring)
        #expect(try await copy.git(["symbolic-ref", "--short", "HEAD"]) == "left")
        let merged = try String(contentsOf: copy.repository.appending(path: "bring.txt"), encoding: .utf8)
        #expect(merged.hasPrefix("line 1 on left\n"))
        #expect(merged.hasSuffix("line 12 edited\n"))
        #expect(summary.detail == "Your changes came along.")
    }

    @Test func switchToARemoteBranch() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        try await copy.clean()
        let other = try await copy.clone("origin", branch: "main")
        _ = try await copy.git(["switch", "-q", "-c", "remote-only"], in: other)
        let pushed = try await copy.commit(in: other, file: "remote.txt", contents: "remote\n", message: "Remote only")
        _ = try await copy.git(["push", "-q", "origin", "remote-only"], in: other)
        _ = try await copy.git(["fetch", "-q", "origin"])
        let store = try await copy.store()
        let summary = try await store.switchTo(branch: "origin/remote-only")
        #expect(try await copy.git(["symbolic-ref", "--short", "HEAD"]) == "remote-only")
        #expect(try await copy.tip("HEAD") == pushed)
        #expect(try await copy.config("branch.remote-only.merge") == "refs/heads/remote-only")
        #expect(summary.message == "Switched to remote-only")
        #expect(summary.detail == "Tracking origin/remote-only.")

        try await store.switchTo(branch: "origin/feature/line-staging")
        #expect(try await copy.git(["symbolic-ref", "--short", "HEAD"]) == "feature/line-staging")
        await expectCode("refNotFound") { try await store.switchTo(branch: "no-such-branch") }
    }

    @Test func detachAtACommit() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        try await copy.clean()
        let store = try await copy.store()
        let target = try #require(try await copy.tip("v0.9.1"))
        let summary = try await store.detach(at: "v0.9.1")
        #expect(try await copy.gitAllowingFailure(["symbolic-ref", "-q", "HEAD"]).exitCode == 1)
        #expect(try await copy.tip("HEAD") == target)
        #expect(summary.message == "You're looking at \(target.prefix(7))")
        if case .detached(let id)? = store.snapshot?.head { #expect(id.rawValue == target) } else { Issue.record("expected a detached HEAD") }
        await expectCode("refNotFound") { try await store.detach(at: "nope") }
    }

    func sideBranch(_ copy: ScenarioCopy, _ name: String, commits: Int) async throws -> String {
        var parent = try await copy.git(["rev-parse", "HEAD"])
        for index in 0..<commits {
            parent = try await copy.git(["commit-tree", "--no-gpg-sign", "HEAD^{tree}", "-p", parent, "-m", "Side \(index)"])
        }
        _ = try await copy.git(["update-ref", "refs/heads/" + name, parent])
        return parent
    }

    @Test func deleteBranchRecordsUndoAndReportsUnmergedCommits() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let tip = try await sideBranch(copy, "side", commits: 2)
        let store = try await copy.store()
        #expect(try await store.unmergedCount(branch: "side") == 2)
        let error = await expectCode("branchNotMerged") { try await store.deleteBranch(name: "side") }
        #expect(error?.code == .branchNotMerged(count: 2))
        #expect(try await copy.tip("refs/heads/side") == tip)
        #expect(await store.undo.entries.isEmpty)

        let summary = try await store.deleteBranch(name: "side", force: true)
        #expect(try await copy.tip("refs/heads/side") == nil)
        let entry = try #require(await store.undo.entries.first)
        #expect(entry.kind == .branchDelete)
        #expect(entry.refsBefore == ["refs/heads/side": OID(tip)!])
        #expect(entry.label == "Deleted branch side")
        #expect(entry.detail == "Was at \(tip.prefix(7))")
        #expect(summary.message == "Deleted branch side")
        #expect(summary.detail == "Was at \(tip.prefix(7)).")
        #expect(store.snapshot?.branches.contains { $0.name == "side" } == false)

        let merged = try #require(try await copy.tip("refs/heads/mira/spike/metal-graph"))
        try await store.deleteBranch(name: "mira/spike/metal-graph")
        #expect(await store.undo.entries.first?.refsBefore == ["refs/heads/mira/spike/metal-graph": OID(merged)!])
        #expect(await store.undo.entries.count == 2)
    }

    @Test func deleteBranchRefusesCurrentAndOtherWorktrees() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let store = try await copy.store()
        await expectCode("isCurrentBranch") { try await store.deleteBranch(name: "feature/graph-renderer", force: true) }
        let elsewhere = await expectCode("branchCheckedOutElsewhere") { try await store.deleteBranch(name: "release/0.9", force: true) }
        if case .branchCheckedOutElsewhere(let path)? = elsewhere?.code {
            #expect(path?.hasSuffix("/everyday/vrai-release") == true)
        }
        await expectCode("refNotFound") { try await store.deleteBranch(name: "no-such-branch") }
        #expect(await store.undo.entries.isEmpty)
    }

    @Test func deleteBranchAlsoOnTheRemote() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let store = try await copy.store()
        #expect(try await copy.remoteTip("origin", "refs/heads/feature/line-staging") != nil)
        let summary = try await store.deleteBranch(name: "feature/line-staging", force: true, alsoOnRemote: true)
        #expect(try await copy.tip("refs/heads/feature/line-staging") == nil)
        #expect(try await copy.remoteTip("origin", "refs/heads/feature/line-staging") == nil)
        #expect(try await copy.tip("refs/remotes/origin/feature/line-staging") == nil)
        #expect(summary.detail?.hasSuffix(", also deleted on origin.") == true)
    }

    @Test func renameBranch() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let store = try await copy.store()
        let tip = try await copy.tip("refs/heads/fix/rebase-banner")
        let summary = try await store.renameBranch(from: "fix/rebase-banner", to: "fix/banner")
        #expect(try await copy.tip("refs/heads/fix/banner") == tip)
        #expect(try await copy.tip("refs/heads/fix/rebase-banner") == nil)
        #expect(summary.message == "Renamed fix/rebase-banner to fix/banner")
        await expectCode("refExists") { try await store.renameBranch(from: "fix/banner", to: "main") }
        await expectCode("invalidRefName") { try await store.renameBranch(from: "fix/banner", to: "bad..name") }
        await expectCode("refNotFound") { try await store.renameBranch(from: "nope", to: "other") }
    }

    @Test func setAndUnsetUpstream() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let store = try await copy.store()
        let set = try await store.setUpstream(branch: "fix/rebase-banner", upstream: "origin/main")
        #expect(try await copy.config("branch.fix/rebase-banner.remote") == "origin")
        #expect(try await copy.config("branch.fix/rebase-banner.merge") == "refs/heads/main")
        #expect(set.message == "fix/rebase-banner now tracks origin/main")
        #expect(store.snapshot?.branches.first { $0.name == "fix/rebase-banner" }?.upstream == "origin/main")
        let unset = try await store.setUpstream(branch: "fix/rebase-banner", upstream: nil)
        #expect(try await copy.config("branch.fix/rebase-banner.merge") == nil)
        #expect(unset.message == "fix/rebase-banner no longer tracks a remote branch")
        try await store.setUpstream(branch: "fix/rebase-banner", upstream: nil)
        await expectCode("refNotFound") { try await store.setUpstream(branch: "main", upstream: "origin/nope") }
        await expectCode("refNotFound") { try await store.setUpstream(branch: "nope", upstream: "origin/main") }
        await expectCode("refNotFound") { try await store.setUpstream(branch: "nope", upstream: nil) }
    }

    @Test func createLightweightAnnotatedAndSignedTags() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let store = try await copy.store()
        let head = try #require(try await copy.tip("HEAD"))
        let light = try await store.createTag(name: "light")
        #expect(try await copy.git(["cat-file", "-t", "refs/tags/light"]) == "commit")
        #expect(light.message == "Tagged \(head.prefix(7)) as light")

        try await store.createTag(name: "notes", target: "main", message: "Release notes")
        #expect(try await copy.git(["cat-file", "-t", "refs/tags/notes"]) == "tag")
        #expect(try await copy.tip("refs/tags/notes") == copy.tip("refs/heads/main"))
        #expect(try await copy.git(["for-each-ref", "--format=%(contents:subject)", "refs/tags/notes"]) == "Release notes")

        try await store.createTag(name: "v1.0.0", message: "Vrai 1.0", sign: true)
        let verify = try await copy.gitAllowingFailure(["tag", "-v", "v1.0.0"])
        #expect(verify.exitCode == 0)
        #expect(verify.errorOutput.contains("Good \"git\" signature for avery@vrai.app"))
        #expect(store.createTagCommand(name: "v1.0.0", message: "Vrai 1.0", sign: true).display == "git tag -s -m \"Vrai 1.0\" v1.0.0")

        await expectCode("refExists") { try await store.createTag(name: "v0.9.1") }
        await expectCode("invalidRefName") { try await store.createTag(name: "bad..tag") }
    }

    @Test func pushAndDeleteTags() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let store = try await copy.store()
        try await store.createTag(name: "v2.0.0", message: "Two")
        let pushed = try await store.pushTag(name: "v2.0.0")
        #expect(pushed.message == "Pushed tag v2.0.0 to origin")
        #expect(try await copy.git(["rev-parse", "refs/tags/v2.0.0"], in: copy.remote("origin")) == copy.git(["rev-parse", "refs/tags/v2.0.0"]))
        try await store.pushTag(name: "v2.0.0", remote: "mira")
        #expect(try await copy.remoteTip("mira", "refs/tags/v2.0.0") != nil)

        let deleted = try await store.deleteTag(name: "v2.0.0", alsoOnRemote: true)
        #expect(deleted.message == "Deleted tag v2.0.0")
        #expect(try await copy.tip("refs/tags/v2.0.0") == nil)
        #expect(try await copy.remoteTip("origin", "refs/tags/v2.0.0") == nil)
        #expect(try await copy.remoteTip("mira", "refs/tags/v2.0.0") != nil)
        try await store.deleteTag(name: "v0.8.0")
        #expect(try await copy.tip("refs/tags/v0.8.0") == nil)
        #expect(try await copy.remoteTip("origin", "refs/tags/v0.8.0") != nil)
        await expectCode("refNotFound") { try await store.deleteTag(name: "nope") }
    }
}
