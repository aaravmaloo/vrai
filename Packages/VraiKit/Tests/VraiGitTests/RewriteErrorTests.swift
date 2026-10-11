import Foundation
import Testing
@testable import VraiGit

struct RewriteErrorTests {
    static func result(_ arguments: [String], exit: Int32, stdout: String = "", stderr: String = "") -> GitResult {
        GitResult(command: GitCommand(arguments), exitCode: exit, stdout: Data(stdout.utf8), stderr: Data(stderr.utf8), startedAt: Date(), duration: .zero)
    }

    @Test func conflictsCarryTheirPaths() {
        let rebase = Self.result(["rebase", "x"], exit: 1, stdout: "Rebasing (1/3)Auto-merging a.txt\nCONFLICT (content): Merge conflict in a.txt\nCould not apply b8c151e... # A on main\n", stderr: "error: could not apply b8c151e... A on main\nhint: Resolve all conflicts manually, mark them as resolved with\n")
        #expect(ErrorClassifier.code(for: rebase) == .conflicts(paths: ["a.txt"]))
        let pick = Self.result(["cherry-pick", "5b33efb"], exit: 1, stdout: "Auto-merging a.txt\nCONFLICT (content): Merge conflict in a.txt\n", stderr: "error: could not apply 5b33efb... A topic\nhint: After resolving the conflicts, mark them with\nhint: \"git add/rm <pathspec>\", then run\n")
        #expect(ErrorClassifier.code(for: pick) == .conflicts(paths: ["a.txt"]))
        let modifyDelete = Self.result(["merge", "del"], exit: 1, stdout: "CONFLICT (modify/delete): a.txt deleted in del and modified in HEAD.  Version HEAD of a.txt left in tree.\nAutomatic merge failed; fix conflicts and then commit the result.\n")
        #expect(ErrorClassifier.code(for: modifyDelete) == .conflicts(paths: ["a.txt"]))
        let replay = Self.result(["replay", "--ref-action=print", "--onto", "main", "main..topic"], exit: 1)
        #expect(ErrorClassifier.code(for: replay) == .conflicts(paths: []))
    }

    @Test func unresolvedConflictsWhenContinuingTooEarly() {
        let merge = Self.result(["merge", "--continue"], exit: 128, stdout: "U\ta.txt\n", stderr: "error: Committing is not possible because you have unmerged files.\nhint: Fix them up in the work tree, and then use 'git add/rm <file>'\nfatal: Exiting because of an unresolved conflict.\n")
        #expect(ErrorClassifier.code(for: merge) == .unresolvedConflicts)
        let rebase = Self.result(["rebase", "--continue"], exit: 1, stderr: "a.txt: needs merge\nYou must edit all merge conflicts and then\nmark them as resolved using git add\n")
        #expect(ErrorClassifier.code(for: rebase) == .unresolvedConflicts)
        let revert = Self.result(["revert", "--no-edit", "HEAD"], exit: 128, stderr: "error: Reverting is not possible because you have unmerged files.\nfatal: revert failed\n")
        #expect(ErrorClassifier.code(for: revert) == .unresolvedConflicts)
    }

    @Test func markersLeftInAFile() {
        let check = Self.result(["diff", "--check"], exit: 2, stdout: "a.txt:2: leftover conflict marker\na.txt:4: leftover conflict marker\n")
        #expect(ErrorClassifier.code(for: check) == .conflictMarkersRemain)
    }

    @Test func fastForwardOnlyOnDivergedBranches() {
        let stderr = "hint: Diverging branches can't be fast-forwarded, you need to either:\nhint:\nhint: \tgit merge --no-ff\nhint:\nhint: or:\nhint:\nhint: \tgit rebase\nhint:\nhint: Disable this message with \"git config set advice.diverging false\"\nfatal: Not possible to fast-forward, aborting.\n"
        #expect(ErrorClassifier.code(for: Self.result(["merge", "--ff-only", "main"], exit: 128, stderr: stderr)) == .notFastForward)
    }

    @Test func rebaseStoppedForEdit() {
        let stdout = "Rebasing (1/2)Stopped at cb8049d...  \nYou can amend the commit now, with\n\n  git commit --amend \n\nOnce you are satisfied with your changes, run\n\n  git rebase --continue\n"
        #expect(ErrorClassifier.code(for: Self.result(["rebase", "-i", "main"], exit: 0, stderr: stdout)) == .stoppedForEdit)
    }

    @Test func emptyCherryPick() {
        let stdout = "On branch t2\nYou are currently cherry-picking commit 78e4ec5.\n  (all conflicts fixed: run \"git cherry-pick --continue\")\n\nnothing to commit, working tree clean\n"
        let stderr = "The previous cherry-pick is now empty, possibly due to conflict resolution.\nIf you wish to commit it anyway, use:\n\n    git commit --allow-empty\n\nOtherwise, please use 'git cherry-pick --skip'\n"
        #expect(ErrorClassifier.code(for: Self.result(["cherry-pick", "78e4ec5"], exit: 1, stdout: stdout, stderr: stderr)) == .emptyCommit)
    }

    @Test func localChangesInTheWay() {
        let stash = Self.result(["stash", "apply", "--index", "stash@{0}"], exit: 1, stderr: "error: Your local changes to the following files would be overwritten by merge:\n\ta.txt\nPlease commit your changes or stash them before you merge.\nAborting\n")
        #expect(ErrorClassifier.code(for: stash) == .localChangesWouldBeOverwritten(paths: ["a.txt"]))
        let keep = Self.result(["reset", "--keep", "x"], exit: 128, stderr: "error: Entry 'a.txt' not uptodate. Cannot merge.\nfatal: Could not reset index file to revision 'x'.\n")
        #expect(ErrorClassifier.code(for: keep) == .localChangesWouldBeOverwritten(paths: ["a.txt"]))
        let readTree = Self.result(["read-tree", "-m", "-u", "a", "b"], exit: 128, stderr: "error: Entry 'dir/b c.txt' would be overwritten by merge. Cannot merge.\n")
        #expect(ErrorClassifier.code(for: readTree) == .localChangesWouldBeOverwritten(paths: ["dir/b c.txt"]))
        let unstaged = Self.result(["rebase", "main"], exit: 1, stderr: "error: cannot rebase: You have unstaged changes.\nerror: Please commit or stash them.\n")
        #expect(ErrorClassifier.code(for: unstaged) == .localChangesWouldBeOverwritten(paths: []))
        let index = Self.result(["rebase", "main"], exit: 1, stderr: "error: cannot rebase: Your index contains uncommitted changes.\nerror: Please commit or stash them.\n")
        #expect(ErrorClassifier.code(for: index) == .localChangesWouldBeOverwritten(paths: []))
        let pick = Self.result(["cherry-pick", "a"], exit: 128, stderr: "error: your local changes would be overwritten by cherry-pick.\nhint: commit your changes or stash them to proceed.\nfatal: cherry-pick failed\n")
        #expect(ErrorClassifier.code(for: pick) == .localChangesWouldBeOverwritten(paths: []))
    }

    @Test func nothingToStashExitsZero() {
        let result = Self.result(["stash", "push"], exit: 0, stdout: "No local changes to save\n")
        #expect(result.succeeded)
        #expect(ErrorClassifier.code(for: result) == .nothingToStash)
    }

    @Test func stashBranchThatExists() {
        let result = Self.result(["stash", "branch", "topic", "stash@{0}"], exit: 1, stderr: "fatal: a branch named 'topic' already exists\n")
        #expect(ErrorClassifier.code(for: result) == .refExists)
    }
}
