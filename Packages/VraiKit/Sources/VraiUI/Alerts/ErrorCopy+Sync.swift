import Foundation
import VraiCore
import VraiGit

extension ErrorCopy {
    static let syncSubcommands: Set<String> = ["fetch", "pull", "push", "switch", "checkout", "branch", "tag", "remote", "credential", "config"]

    static func sync(_ error: GitError) -> ErrorCopy? {
        if let sub = error.result?.command.subcommand, !syncSubcommands.contains(sub) {
            switch error.code {
            case .localChangesWouldBeOverwritten, .refExists, .refNotFound, .invalidRefName, .hookFailed: return nil
            default: break
            }
        }
        let host = error.host ?? String(localized: "The server", bundle: .module)
        switch error.code {
        case .authFailed:
            let repository = error.remoteURL.flatMap { RemoteURL($0)?.repositoryPath } ?? ""
            return ErrorCopy(
                title: SyncCopy.authTitle(host: host, repository: repository),
                message: String(localized: "Fetch, pull and push fail until you sign in again.", bundle: .module)
            )
        case .networkUnreachable:
            return ErrorCopy(
                title: String(localized: "Couldn't reach \(host)", bundle: .module),
                message: String(localized: "Check your connection, then try again. Everything that doesn't need the remote still works.", bundle: .module)
            )
        case .remoteNotFound:
            return ErrorCopy(
                title: String(localized: "This repository has no remotes", bundle: .module),
                message: String(localized: "git couldn't find the remote it needs. Add one to fetch, pull and push.", bundle: .module)
            )
        case .pushRejected(let behind):
            let copy = SyncCopy.rejected(remote: SyncCopy.remote(of: error) ?? String(localized: "The remote", bundle: .module), behind: behind)
            return ErrorCopy(title: copy.title, message: copy.message)
        case .protectedBranch:
            return ErrorCopy(
                title: String(localized: "The remote protects this branch", bundle: .module),
                message: String(localized: "It refused the push. Push to another branch and open a pull request, or ask for access.", bundle: .module)
            )
        case .noUpstream:
            return ErrorCopy(
                title: String(localized: "This branch has no upstream", bundle: .module),
                message: String(localized: "Push it first to set one, or choose a branch to pull from.", bundle: .module)
            )
        case .divergentBranches:
            return ErrorCopy(
                title: String(localized: "Can't fast-forward", bundle: .module),
                message: String(localized: "Your branch and its upstream both have commits the other lacks. Pull and merge, or pull and rebase your commits on top.", bundle: .module)
            )
        case .localChangesWouldBeOverwritten(let paths):
            return ErrorCopy(
                title: String(localized: "Your changes would be overwritten", bundle: .module),
                message: paths.isEmpty
                    ? String(localized: "git stopped so it doesn't overwrite files you changed. Commit or stash them, then try again.", bundle: .module)
                    : String(localized: "git stopped so it doesn't overwrite \(n(paths.count, "file")) you changed: \(paths.prefix(3).map { PathParts.split($0).name }.joined(separator: ", ")). Commit or stash them, then try again.", bundle: .module)
            )
        case .invalidRefName:
            return ErrorCopy(
                title: String(localized: "git won't accept that name", bundle: .module),
                message: String(localized: "Avoid spaces, .., ~ ^ : ? * [ \\ and a trailing slash. Try one like feature/graph-search.", bundle: .module)
            )
        case .refExists:
            return ErrorCopy(
                title: String(localized: "That name is taken", bundle: .module),
                message: String(localized: "A branch, tag or remote with that name already exists. Pick another name.", bundle: .module)
            )
        case .refNotFound:
            return ErrorCopy(
                title: String(localized: "git can't find that ref", bundle: .module),
                message: String(localized: "It may have been renamed or deleted outside Vrai. Pick another, then try again.", bundle: .module)
            )
        case .branchNotMerged(let count):
            return ErrorCopy(
                title: String(localized: "This branch isn't merged", bundle: .module),
                message: count.map { String(localized: "\(n($0, "commit")) on it aren't in HEAD. Delete it from the branch menu to confirm; Undo history keeps it for 14 days.", bundle: .module) }
                    ?? String(localized: "Some of its commits aren't in HEAD. Delete it from the branch menu to confirm; Undo history keeps it for 14 days.", bundle: .module)
            )
        case .isCurrentBranch:
            return ErrorCopy(
                title: String(localized: "You're on this branch", bundle: .module),
                message: String(localized: "Switch to another branch first, then delete it.", bundle: .module)
            )
        case .branchCheckedOutElsewhere(let path):
            return ErrorCopy(
                title: String(localized: "This branch is checked out in another worktree", bundle: .module),
                message: path.map { String(localized: "Switch \($0) to another branch first, then try again.", bundle: .module) } ?? String(localized: "Switch that worktree to another branch first, then try again.", bundle: .module)
            )
        case .invalidURL:
            return ErrorCopy(
                title: String(localized: "git can't use that URL", bundle: .module),
                message: String(localized: "Use an https or SSH address, like git@github.com:owner/repo.git.", bundle: .module)
            )
        case .hookFailed(let name, let output) where name == "pre-push":
            return ErrorCopy(
                title: String(localized: "The pre-push hook stopped the push", bundle: .module),
                message: SyncCopy.trimmed(output)
            )
        default:
            return nil
        }
    }
}
