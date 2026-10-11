import VraiCore
import VraiGit

extension ErrorCopy {
    static func places(_ error: GitError) -> ErrorCopy? {
        let arguments = error.result?.command.arguments ?? []
        let sub = error.result?.command.subcommand
        let detail = error.result?.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch error.code {
        case .pathExists:
            if sub == "submodule" {
                return ErrorCopy(
                    title: String(localized: "Something is already at that path", bundle: .module),
                    message: String(localized: "git won't put a submodule where a file or folder already exists. Choose an empty path, like Vendor/name.", bundle: .module)
                )
            }
            return ErrorCopy(
                title: String(localized: "That folder already exists", bundle: .module),
                message: String(localized: "git adds a worktree only in a new or empty folder. Choose another folder, then try again.", bundle: .module)
            )
        case .worktreeDirty:
            return ErrorCopy(
                title: String(localized: "This worktree has uncommitted changes", bundle: .module),
                message: String(localized: "git won't remove it while it has changes. Commit or stash them there, or remove it anyway and keep a copy in Undo history.", bundle: .module)
            )
        case .worktreeLocked:
            return ErrorCopy(
                title: String(localized: "This worktree is locked", bundle: .module),
                message: String(localized: "Unlock it first, then remove it. Someone locked it so git leaves it alone.", bundle: .module)
            )
        case .branchCheckedOutElsewhere(let path) where sub == "worktree":
            let place = path.map { PlacesCopy.name($0) } ?? String(localized: "another worktree", bundle: .module)
            return ErrorCopy(
                title: String(localized: "That branch is already checked out", bundle: .module),
                message: String(localized: "\(place) has it. A branch can be checked out in one worktree at a time, so pick another branch or create a new one.", bundle: .module)
            )
        case .remoteNotFound where sub == "submodule":
            return ErrorCopy(
                title: String(localized: "git can't find a repository at that URL", bundle: .module),
                message: String(localized: "Check the URL and that you can reach it, then try again.", bundle: .module)
            )
        case .unknown where sub == "submodule":
            if detail.contains("transport 'file' not allowed") {
                return ErrorCopy(
                    title: String(localized: "git blocks local submodule URLs", bundle: .module),
                    message: String(localized: "Your git config doesn't allow the file transport for submodules (protocol.file.allow). Use an https or SSH URL instead.", bundle: .module)
                )
            }
            return ErrorCopy(
                title: arguments.contains("deinit") ? String(localized: "The submodule wasn't deinitialized", bundle: .module) : String(localized: "The submodule didn't update", bundle: .module),
                message: detail.isEmpty ? String(localized: "Try again. If it keeps failing, run git submodule in Terminal to see why.", bundle: .module) : detail
            )
        case .unknown where sub == "blame" || sub == "log" && arguments.contains("--follow"):
            if detail.contains("no such path") || detail.contains("no such file") || detail.contains("does not exist") {
                return ErrorCopy(
                    title: String(localized: "git has no history for this file", bundle: .module),
                    message: String(localized: "It isn't in that commit. It may be new, renamed or deleted.", bundle: .module)
                )
            }
            return nil
        case .unknown where sub == "worktree":
            return ErrorCopy(
                title: String(localized: "git couldn't change the worktree", bundle: .module),
                message: detail.isEmpty ? String(localized: "Try again. If it keeps failing, run git worktree list in Terminal to see why.", bundle: .module) : detail
            )
        default:
            return nil
        }
    }
}
