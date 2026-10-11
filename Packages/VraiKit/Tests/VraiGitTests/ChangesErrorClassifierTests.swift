import Foundation
import Testing
@testable import VraiGit

struct ChangesErrorClassifierTests {
    static func result(_ arguments: [String], exit: Int32, stdout: String = "", stderr: String = "") -> GitResult {
        GitResult(command: GitCommand(arguments), exitCode: exit, stdout: Data(stdout.utf8), stderr: Data(stderr.utf8), startedAt: Date(), duration: .zero)
    }

    @Test func nothingToCommit() {
        let clean = Self.result(["commit", "-F", "-"], exit: 1, stdout: "On branch main\nnothing to commit, working tree clean\n")
        #expect(ErrorClassifier.code(for: clean) == .nothingToCommit)
        let untracked = Self.result(["commit", "-F", "-"], exit: 1, stdout: "On branch main\nUntracked files:\n  (use \"git add <file>...\" to include in what will be committed)\n\ttrace.json\n\nnothing added to commit but untracked files present (use \"git add\" to track)\n")
        #expect(ErrorClassifier.code(for: untracked) == .nothingToCommit)
        let unstaged = Self.result(["commit", "-F", "-"], exit: 1, stdout: "On branch main\nChanges not staged for commit:\n\tmodified:   a.txt\n\nno changes added to commit (use \"git add\" and/or \"git commit -a\")\n")
        #expect(ErrorClassifier.code(for: unstaged) == .nothingToCommit)
    }

    @Test func emptyMessage() {
        let result = Self.result(["commit", "-F", "-"], exit: 1, stderr: "Aborting commit due to empty commit message.\n")
        #expect(ErrorClassifier.code(for: result) == .emptyMessage)
    }

    @Test func hookFailedKeepsTheHookOutput() {
        let output = "swift-format lint --strict: 2 problems\nSources/VraiUI/History/GraphCell.swift:31:1: Line is too long\n"
        let result = Self.result(["commit", "-F", "-"], exit: 1, stderr: output)
        #expect(ErrorClassifier.code(for: result) == .hookFailed(name: "pre-commit", output: output))
        let skipped = Self.result(["commit", "-F", "-", "--no-verify"], exit: 1, stderr: "prepare says no\n")
        #expect(ErrorClassifier.code(for: skipped) == .hookFailed(name: "prepare-commit-msg", output: "prepare says no\n"))
        let push = Self.result(["push", "origin", "main"], exit: 1, stderr: "error: failed to push some refs to 'origin'\nhint: pre-push hook failed\n")
        if case .hookFailed(let name, _) = ErrorClassifier.code(for: push) {
            #expect(name == "pre-push")
        } else {
            Issue.record("expected hookFailed for a pre-push failure")
        }
    }

    @Test func signingFailed() {
        let ssh = Self.result(["commit", "-F", "-"], exit: 128, stderr: "error: Couldn't load public key /nonexistent/key: No such file or directory?\n\nfatal: failed to write commit object\n")
        #expect(ErrorClassifier.code(for: ssh) == .signingFailed(detail: "error: Couldn't load public key /nonexistent/key: No such file or directory?\n\nfatal: failed to write commit object"))
        let gpg = Self.result(["commit", "-F", "-"], exit: 128, stderr: "error: cannot run gpg: No such file or directory\nerror: gpg failed to sign the data\nfatal: failed to write commit object\n")
        #expect(ErrorClassifier.code(for: gpg).name == "signingFailed")
    }

    @Test func patchDoesNotApply() {
        let failed = Self.result(["apply", "--cached", "--recount", "--unidiff-zero", "-"], exit: 1, stderr: "error: patch failed: f.txt:1\nerror: f.txt: patch does not apply\n")
        #expect(ErrorClassifier.code(for: failed) == .patchDoesNotApply)
        let missing = Self.result(["apply", "--cached", "--recount", "--unidiff-zero", "-"], exit: 1, stderr: "error: gone.txt: does not exist in index\n")
        #expect(ErrorClassifier.code(for: missing) == .patchDoesNotApply)
        let exists = Self.result(["apply", "--cached", "--recount", "--unidiff-zero", "-"], exit: 1, stderr: "error: fresh.txt: already exists in index\n")
        #expect(ErrorClassifier.code(for: exists) == .patchDoesNotApply)
    }

    @Test func lockFileExists() {
        let stderr = "fatal: Unable to create '/repo/.git/index.lock': File exists.\n\nAnother git process seems to be running in this repository, e.g.\nan editor opened by 'git commit'. Please make sure all processes\nare terminated then try again.\n"
        for arguments in [["add", "--", "a.txt"], ["restore", "--staged", "--", "a.txt"], ["apply", "--cached", "-"], ["commit", "-F", "-"]] {
            #expect(ErrorClassifier.code(for: Self.result(arguments, exit: 128, stderr: stderr)) == .lockFileExists(path: "/repo/.git/index.lock"))
        }
    }
}
