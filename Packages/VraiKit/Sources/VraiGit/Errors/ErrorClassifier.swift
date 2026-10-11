import Foundation

public enum ErrorClassifier {
    public static func classify(_ result: GitResult) -> GitError {
        GitError(code(for: result), result: result)
    }

    public static func code(for result: GitResult) -> GitErrorCode {
        let stderr = result.errorOutput
        let stdout = result.output
        let all = stderr + "\n" + stdout
        let subcommand = result.command.subcommand ?? ""

        if all.contains("not a git repository") { return .notARepository }
        if let path = firstMatch(all, /Unable to create '([^']+\.lock)': File exists/) { return .lockFileExists(path: path) }

        if all.contains("Authentication failed for") || all.contains("could not read Username") || all.contains("could not read Password")
            || all.contains("Permission denied (publickey") || all.contains("HTTP Basic: Access denied") || all.contains("The requested URL returned error: 401")
            || all.contains("The requested URL returned error: 403") || all.contains("Invalid username or password") {
            return .authFailed(host: host(in: all))
        }
        if all.contains("Could not resolve host") || all.contains("Failed to connect to") || all.contains("Couldn't connect to server")
            || all.contains("Connection refused") || all.contains("Network is unreachable") || all.contains("Operation timed out")
            || all.contains("Could not resolve hostname") || all.contains("Connection timed out") {
            return .networkUnreachable(host: host(in: all))
        }
        if all.contains("does not appear to be a git repository") || (all.contains("repository '") && all.contains("' not found")) {
            return .remoteNotFound
        }
        if all.contains("protected branch") || all.contains("GH006") || all.contains("pre-receive hook declined") { return .protectedBranch }
        if all.contains("[rejected]") || all.contains("Updates were rejected") || all.contains("failed to push some refs") && all.contains("non-fast-forward") {
            return .pushRejected(behind: nil)
        }
        if all.contains("has no upstream branch") || all.contains("There is no tracking information for the current branch") { return .noUpstream }
        if all.contains("Need to specify how to reconcile divergent branches") || all.contains("You have divergent branches") { return .divergentBranches }
        if all.contains("Not possible to fast-forward") || all.contains("Not a fast-forward") { return .notFastForward }

        if all.contains("would be overwritten by") {
            return .localChangesWouldBeOverwritten(paths: indentedPaths(after: "would be overwritten by", in: all))
        }
        if all.contains("you need to resolve your current index first") || all.contains("Committing is not possible because you have unmerged files")
            || all.contains("is not possible because you have unmerged files") || all.contains("You must edit all merge conflicts") {
            return .unresolvedConflicts
        }
        if all.contains("CONFLICT (") || all.contains("Automatic merge failed") || all.contains("could not apply") || all.contains("after resolving the conflicts") {
            return .conflicts(paths: conflictPaths(in: all))
        }
        if subcommand == "commit" || subcommand == "merge" || subcommand == "rebase" {
            if all.contains("nothing to commit") || all.contains("no changes added to commit") { return .nothingToCommit }
            if all.contains("Aborting commit due to empty commit message") { return .emptyMessage }
        }
        if all.contains("No local changes to save") { return .nothingToStash }
        if all.contains("The previous cherry-pick is now empty") || all.contains("nothing to commit") && subcommand == "cherry-pick" { return .emptyCommit }
        if let hook = firstMatch(all, /hint: The '[^']*hooks\/([a-z-]+)' hook/) ?? firstMatch(all, /([a-z-]+) hook (?:declined|failed)/) {
            return .hookFailed(name: hook, output: stderr)
        }
        if all.contains("gpg failed to sign") || all.contains("failed to write commit object") && all.contains("sign") || all.contains("ssh-keygen") && all.contains("sign") {
            return .signingFailed(detail: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if all.contains("is not a valid branch name") || all.contains("is not a valid tag name") || all.contains("is not a valid remote name") || all.contains("not a valid ref name") {
            return .invalidRefName
        }
        if all.contains("already exists") {
            if all.contains("' already exists") && (subcommand == "worktree" || subcommand == "clone") && !all.contains("branch named") { return .pathExists }
            return .refExists
        }
        if all.contains("is not fully merged") { return .branchNotMerged(count: nil) }
        if all.contains("Cannot delete branch") && all.contains("checked out at") || all.contains("cannot delete branch") && all.contains("used by worktree") {
            return .isCurrentBranch
        }
        if let path = firstMatch(all, /is already (?:checked out|used by worktree) at '([^']+)'/) { return .branchCheckedOutElsewhere(path: path) }
        if all.contains("patch does not apply") || all.contains("corrupt patch") || all.contains("patch failed") { return .patchDoesNotApply }
        if all.contains("contains modified or untracked files, use --force to delete it") { return .worktreeDirty }
        if all.contains("cannot remove a locked working tree") || all.contains("is locked") && subcommand == "worktree" { return .worktreeLocked }
        if all.contains("unknown revision") || all.contains("bad revision") || all.contains("Needed a single revision") || all.contains("not a valid object name")
            || all.contains("invalid reference") || all.contains("pathspec") && all.contains("did not match any") || all.contains("couldn't find remote ref")
            || all.contains("ambiguous argument") || all.contains("no such branch") || all.contains("not found") && subcommand == "branch" {
            return .refNotFound
        }
        if all.contains("is not a valid") && all.contains("URL") || all.contains("unable to find remote helper") || all.contains("Unsupported protocol") {
            return .invalidURL
        }
        return .unknown(exit: result.exitCode, stderr: stderr)
    }

    static func firstMatch(_ text: String, _ regex: Regex<(Substring, Substring)>) -> String? {
        text.firstMatch(of: regex).map { String($0.output.1) }
    }

    static func host(in text: String) -> String? {
        if let url = text.firstMatch(of: /(?:https?|ssh|git):\/\/(?:[^@\/\s']+@)?([^\/\s':]+)(?::\d+)?/) { return String(url.output.1) }
        if let scp = text.firstMatch(of: /[A-Za-z0-9._-]+@([A-Za-z0-9.-]+):/) { return String(scp.output.1) }
        if let resolve = text.firstMatch(of: /Could not resolve host(?:name)?:? ([A-Za-z0-9.-]+)/) { return String(resolve.output.1) }
        if let connect = text.firstMatch(of: /Failed to connect to ([A-Za-z0-9.-]+)/) { return String(connect.output.1) }
        return nil
    }

    static func indentedPaths(after marker: String, in text: String) -> [String] {
        var paths: [String] = []
        var collecting = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.contains(marker) {
                collecting = true
                continue
            }
            guard collecting else { continue }
            if line.hasPrefix("\t") {
                paths.append(String(line.dropFirst()))
            } else if !paths.isEmpty || !line.isEmpty {
                collecting = false
            }
        }
        return paths
    }

    static func conflictPaths(in text: String) -> [String] {
        var paths: [String] = []
        for match in text.matches(of: /CONFLICT \([^)]*\): (?:Merge conflict in |.*? deleted in .*? and modified in .*?\.  Version .*? of )?(.+)$/.anchorsMatchLineEndings()) {
            let path = String(match.output.1).trimmingCharacters(in: .whitespaces)
            if !paths.contains(path) { paths.append(path) }
        }
        return paths
    }
}
