import Foundation
import Testing
@testable import VraiGit

struct RewriteCommandsTests {
    static let a = OID(String(repeating: "a", count: 40))!
    static let b = OID(String(repeating: "b", count: 40))!

    @Test func mergeCommandsMatchTheSheet() {
        #expect(RewriteCommands.merge(source: "origin/main", mode: .auto).display == "git merge origin/main")
        #expect(RewriteCommands.merge(source: "origin/main", mode: .fastForwardOnly, message: "ignored").display == "git merge --ff-only origin/main")
        #expect(RewriteCommands.merge(source: "fix/x", mode: .mergeCommit, message: "Merge fix/x").display == "git merge --no-ff -m \"Merge fix/x\" fix/x")
        #expect(RewriteCommands.merge(source: "fix/x", mode: .squash, message: "ignored").display == "git merge --squash fix/x")
        #expect(RewriteCommands.merge(source: "fix/x", mode: .auto, strategyOption: "theirs").display == "git merge -X theirs fix/x")
        #expect(RewriteCommands.merge(source: "fix/x", mode: .auto).risk == .safe)
        #expect(RewriteCommands.merge(source: "fix/x", mode: .auto).access == .write)
    }

    @Test func rebaseCommands() {
        let plain = RewriteCommands.rebase(onto: "origin/main", autostash: true, updateRefs: true, rebaseMerges: true)
        #expect(plain.display == "git rebase --autostash --update-refs --rebase-merges origin/main")
        #expect(plain.risk == .rewrites)
        let interactive = RewriteCommands.interactiveRebase(onto: "main", sequenceEditor: "'/x' --todo '/t'", editor: "'/x' --messages '/m'")
        #expect(interactive.display == "git rebase -i main")
        #expect(interactive.sequenceEditor == "'/x' --todo '/t'")
        #expect(interactive.editor == "'/x' --messages '/m'")
        #expect(RewriteCommands.replay(onto: "origin/main", branch: "feature/x", contained: true).display == "git replay --contained --ref-action=print --onto origin/main origin/main..feature/x")
        #expect(RewriteCommands.replay(onto: "main", branch: "x", printRefs: false).display == "git replay --onto main main..x")
        let update = RewriteCommands.updateRefs([RefUpdate(ref: "refs/heads/x", new: Self.b, old: Self.a)], reason: "rebase (replay): onto main")
        #expect(update.display == "git update-ref -m \"rebase (replay): onto main\" --stdin")
        #expect(update.stdin == Data("update refs/heads/x \(Self.b.rawValue) \(Self.a.rawValue)\n".utf8))
        #expect(RewriteCommands.moveWorktree(from: Self.a, to: Self.b).arguments == ["read-tree", "-m", "-u", Self.a.rawValue, Self.b.rawValue])
    }

    @Test func operationControlCommands() {
        #expect(OperationInProgress.allCases.map { RewriteCommands.abort($0).display } == [
            "git merge --abort", "git rebase --abort", "git am --abort", "git cherry-pick --abort", "git revert --abort", "git bisect reset"
        ])
        #expect(OperationInProgress.allCases.map { RewriteCommands.continueOperation($0)?.display } == [
            "git merge --continue", "git rebase --continue", "git am --continue", "git cherry-pick --continue", "git revert --continue", nil
        ])
        #expect(OperationInProgress.allCases.map { RewriteCommands.skip($0)?.display } == [
            nil, "git rebase --skip", "git am --skip", "git cherry-pick --skip", "git revert --skip", nil
        ])
        #expect(RewriteCommands.continueOperation(.rebase, editor: "'/x' --messages '/m'")?.editor == "'/x' --messages '/m'")
        #expect(RewriteCommands.abort(.merge).risk == .safe)
    }

    @Test func pickRevertAndReset() {
        #expect(RewriteCommands.cherryPick(ids: [Self.a, Self.b], recordOrigin: true, noCommit: true, mainline: 1).display == "git cherry-pick -x --no-commit -m 1 \(Self.a.rawValue) \(Self.b.rawValue)")
        #expect(RewriteCommands.cherryPick(ids: [Self.a]).display == "git cherry-pick \(Self.a.rawValue)")
        #expect(RewriteCommands.revert(id: Self.a, noCommit: true, mainline: 2).display == "git revert --no-edit --no-commit -m 2 \(Self.a.rawValue)")
        #expect(ResetMode.allCases.map { RewriteCommands.reset(to: "HEAD~1", mode: $0).display } == ["git reset --soft HEAD~1", "git reset --mixed HEAD~1", "git reset --hard HEAD~1", "git reset --keep HEAD~1"])
        #expect(ResetMode.allCases.map { RewriteCommands.reset(to: "HEAD~1", mode: $0).risk } == [.rewrites, .rewrites, .destructive, .rewrites])
    }

    @Test func stashCommands() {
        #expect(RewriteCommands.stash().display == "git stash push")
        #expect(RewriteCommands.stash(message: "halo experiments", includeUntracked: true, keepIndex: true, onlyStaged: true, paths: ["a b.txt", "c"]).display
            == "git stash push --include-untracked --keep-index --staged -m \"halo experiments\" -- \"a b.txt\" c")
        #expect(RewriteCommands.applyStash(index: 2, pop: true, restoreIndex: true).display == "git stash pop --index stash@{2}")
        #expect(RewriteCommands.applyStash(index: 0).display == "git stash apply stash@{0}")
        #expect(RewriteCommands.dropStash(index: 1).display == "git stash drop stash@{1}")
        #expect(RewriteCommands.dropStash(index: 1).risk == .destructive)
        #expect(RewriteCommands.branchFromStash(index: 1, name: "notes").display == "git stash branch notes stash@{1}")
        #expect(RewriteCommands.stashCreate.display == "git stash create")
    }

    @Test func bisectCommandsAndOutput() {
        #expect(RewriteCommands.startBisect(bad: "feature/graph-renderer", good: "v0.9.0").display == "git bisect start feature/graph-renderer v0.9.0")
        #expect(BisectVerdict.allCases.map { RewriteCommands.markBisect($0).display } == ["git bisect good", "git bisect bad", "git bisect skip"])
        #expect(RewriteCommands.markBisect(.skip).acceptedExitCodes == [0, 2])
        #expect(RewriteCommands.endBisect.display == "git bisect reset")

        let testing = "Bisecting: 3 revisions left to test after this (roughly 2 steps)\n[6fb0127667c5d753c9fba2022ff9b94935c99129] D one\n"
        #expect(BisectOutcome.parse(testing) == .testing(current: OID("6fb0127667c5d753c9fba2022ff9b94935c99129"), remaining: 3))
        let found = "be68bbffd7262d18cfaf2741ff7fe77591273dbf is the first bad commit\ncommit be68bbffd7262d18cfaf2741ff7fe77591273dbf\nAuthor: Avery Chen <avery@vrai.app>\n\n    E one\n"
        #expect(BisectOutcome.parse(found) == .found(OID("be68bbffd7262d18cfaf2741ff7fe77591273dbf")!))
        let quoted = "be68bbffd7262d18cfaf2741ff7fe77591273dbf is the first 'bad' commit\ncommit be68bbffd7262d18cfaf2741ff7fe77591273dbf\n"
        #expect(BisectOutcome.parse(quoted) == .found(OID("be68bbffd7262d18cfaf2741ff7fe77591273dbf")!))
        let skipped = "There are only 'skip'ped commits left to test.\nThe first bad commit could be any of:\n02d1595e9bb01f41141768dea84f8be13ac618be\n1af25b5a0f25f24ecf40b9501dfca046ffb0c852\nWe cannot bisect more!\n"
        #expect(BisectOutcome.parse(skipped) == .inconclusive(candidates: [OID("02d1595e9bb01f41141768dea84f8be13ac618be")!, OID("1af25b5a0f25f24ecf40b9501dfca046ffb0c852")!]))
    }

    @Test func replayOutputParses() {
        let output = "update refs/heads/side-mid b8ba6a521a117bdcd7369fb43e0037138b48df4f 267d69b131e5c825e556ef3af15cdb9fbd6a8710\nupdate refs/heads/side 22cffda59900f7f5eeea94d3822b4649b3c06eca b801de25fe21137f8afc37fa8983b78835447506\n"
        let updates = RefUpdate.parse(output)
        #expect(updates.map(\.ref) == ["refs/heads/side-mid", "refs/heads/side"])
        #expect(updates[1].new == OID("22cffda59900f7f5eeea94d3822b4649b3c06eca"))
        #expect(updates[1].old == OID("b801de25fe21137f8afc37fa8983b78835447506"))
    }

    @Test func conflictResolutionCommands() {
        #expect(RewriteCommands.checkout(.ours, path: "a b.txt").display == "git checkout --ours -- \"a b.txt\"")
        #expect(RewriteCommands.checkout(.theirs, path: "x").display == "git checkout --theirs -- x")
        #expect(RewriteCommands.add(path: "x").display == "git add -- x")
        #expect(RewriteCommands.remove(path: "x").display == "git rm --quiet -- x")
        #expect(RewriteCommands.mergeFile(ours: Self.a, base: Self.b, theirs: Self.a).acceptedExitCodes.contains(1))
    }
}
