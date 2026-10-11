import Foundation
import Testing
@testable import VraiGit

struct SyncErrorClassifierTests {
    @Test(arguments: [
        ("sync-auth-fetch", "authFailed"),
        ("sync-auth-no-credentials", "authFailed"),
        ("sync-offline-push", "networkUnreachable"),
        ("sync-offline-pull", "networkUnreachable"),
        ("sync-remote-not-found", "remoteNotFound"),
        ("sync-no-such-remote", "remoteNotFound"),
        ("sync-push-non-fast-forward", "pushRejected"),
        ("sync-push-stale-lease", "pushRejected"),
        ("sync-protected-branch", "protectedBranch"),
        ("sync-push-no-upstream", "noUpstream"),
        ("sync-pull-no-upstream", "noUpstream"),
        ("sync-pull-detached", "noUpstream"),
        ("sync-pull-diverged", "divergentBranches"),
        ("sync-pull-rebase-dirty", "localChangesWouldBeOverwritten"),
        ("sync-switch-merge-staged", "localChangesWouldBeOverwritten"),
        ("sync-tag-invalid", "invalidRefName"),
        ("sync-tag-exists", "refExists"),
        ("sync-tag-not-found", "refNotFound"),
        ("sync-delete-current", "isCurrentBranch"),
        ("sync-delete-elsewhere", "isCurrentBranch"),
        ("sync-rename-missing", "refNotFound"),
        ("sync-upstream-missing", "refNotFound"),
        ("sync-branch-missing", "refNotFound"),
        ("sync-remote-exists", "refExists"),
        ("sync-remote-invalid-name", "invalidRefName"),
        ("sync-unknown-scheme", "invalidURL"),
        ("sync-src-refspec", "refNotFound"),
        ("sync-delete-missing-remote-ref", "refNotFound"),
        ("sync-switch-invalid", "refNotFound")
    ])
    func recordedSyncFailuresMapToCodes(name: String, expected: String) throws {
        let result = try ErrorClassifierTests.result(name)
        #expect(ErrorClassifier.code(for: result).name == expected)
    }

    @Test func networkDetailsNameTheHost() throws {
        #expect(ErrorClassifier.code(for: try ErrorClassifierTests.result("sync-auth-fetch")) == .authFailed(host: "127.0.0.1"))
        #expect(ErrorClassifier.code(for: try ErrorClassifierTests.result("sync-auth-no-credentials")) == .authFailed(host: "127.0.0.1"))
        #expect(ErrorClassifier.code(for: try ErrorClassifierTests.result("sync-offline-push")) == .networkUnreachable(host: "127.0.0.1"))
        let auth = ErrorClassifier.classify(try ErrorClassifierTests.result("sync-auth-fetch"))
        #expect(auth.remoteURL == "http://127.0.0.1:47813/vrai.git")
        #expect(auth.host == "127.0.0.1")
        let rejected = ErrorClassifier.classify(try ErrorClassifierTests.result("sync-push-non-fast-forward"))
        #expect(rejected.remoteURL == "file:///SANDBOX/fixtures/everyday/remotes/origin.git")
        #expect(RemoteURL(rejected.remoteURL ?? "")?.repositoryPath == "SANDBOX/fixtures/everyday/remotes/origin")
    }

    @Test func pathsAreParsed() throws {
        let staged = ErrorClassifier.code(for: try ErrorClassifierTests.result("sync-switch-merge-staged"))
        #expect(staged == .localChangesWouldBeOverwritten(paths: [
            "Sources/VraiGit/Graph/LaneLayout.swift",
            "Sources/VraiUI/History/GraphCell.swift",
            "Sources/VraiUI/History/LaneColors.swift",
            "Sources/VraiUI/History/Palette.swift"
        ]))
        #expect(ErrorClassifier.code(for: try ErrorClassifierTests.result("sync-pull-rebase-dirty")) == .localChangesWouldBeOverwritten(paths: []))
    }

    @Test func mergeFastForwardFailuresStayNotFastForward() {
        let stderr = "hint: Diverging branches can't be fast-forwarded, you need to either:\nfatal: Not possible to fast-forward, aborting.\n"
        let merge = GitResult(command: GitCommand(["merge", "--ff-only", "main"]), exitCode: 128, stdout: Data(), stderr: Data(stderr.utf8), startedAt: Date(), duration: .zero)
        #expect(ErrorClassifier.code(for: merge) == .notFastForward)
        let pull = GitResult(command: GitCommand(["pull", "--ff-only"]), exitCode: 128, stdout: Data(), stderr: Data(stderr.utf8), startedAt: Date(), duration: .zero)
        #expect(ErrorClassifier.code(for: pull) == .divergentBranches)
    }

    @Test func commandsCarryTheRightRisk() {
        #expect(SyncCommands.push(remote: "origin", refspec: "main").risk == .safe)
        #expect(SyncCommands.push(remote: "origin", refspec: "main", force: .withLease).risk == .rewrites)
        #expect(SyncCommands.push(remote: "origin", refspec: "main", force: .force).risk == .destructive)
        #expect(SyncCommands.deleteRemoteBranch(remote: "origin", name: "x").risk == .destructive)
        #expect(BranchCommands.delete(name: "x", force: true).risk == .destructive)
        #expect(BranchCommands.delete(name: "x", force: false).risk == .safe)
        #expect(BranchCommands.deleteTag(name: "v1").risk == .destructive)
        #expect(SyncCommands.push(remote: "origin", refspec: "main", force: .withLease, setUpstream: true, tags: true, noVerify: true, pushOptions: ["ci.skip"]).display
            == "git push --force-with-lease -u --follow-tags --no-verify -o ci.skip --progress origin main")
        #expect(SyncCommands.fetch(remote: "origin", prune: false, depth: 3).display == "git fetch --no-prune --depth 3 --progress origin")
        #expect(SyncCommands.fetch(remote: "origin", prune: nil, unshallow: true, progress: false).display == "git fetch --unshallow origin")
        #expect(SyncCommands.pull(mode: .rebase, autostash: true).display == "git pull --rebase --autostash --progress")
        #expect(SyncCommands.pull(mode: .fastForwardOnly, progress: false).display == "git pull --ff-only")
        #expect(SyncCommands.pushTag(name: "v1", remote: "origin").display == "git push origin refs/tags/v1")
        #expect(SyncCommands.deleteRemoteTag(name: "v1", remote: "origin").display == "git push origin --delete refs/tags/v1")
        #expect(BranchCommands.switchTo("main", merge: true).display == "git switch --merge main")
        #expect(BranchCommands.track("origin/x").display == "git switch --track origin/x")
        #expect(BranchCommands.setUpstream(branch: "x", upstream: "origin/x").display == "git branch --set-upstream-to=origin/x x")
        #expect(BranchCommands.setUpstream(branch: "x", upstream: nil).display == "git branch --unset-upstream x")
        #expect(BranchCommands.createTag(name: "v1", target: "abc1234", message: "One").display == "git tag -a -m One v1 abc1234")
        #expect(BranchCommands.createTag(name: "v1").display == "git tag v1")
        #expect(SyncCommands.backgroundFetch().display == "git fetch --all")
    }
}
