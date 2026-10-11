import VraiGit

extension ErrorCopy {
    static let hookOutputLines = 12

    static func changes(_ error: GitError) -> ErrorCopy? {
        switch error.code {
        case .nothingToCommit:
            return ErrorCopy(
                title: String(localized: "Nothing to commit", bundle: .module),
                message: String(localized: "No changes are staged. Check a file or press Space to stage it, then commit.", bundle: .module)
            )
        case .emptyMessage:
            return ErrorCopy(
                title: String(localized: "Write a summary to commit", bundle: .module),
                message: String(localized: "git needs a summary line for every commit. Type one above the description, then commit.", bundle: .module)
            )
        case .hookFailed(let name, let output):
            let tail = hookTail(output)
            let advice = String(localized: "Fix what the hook reports, then try again.", bundle: .module)
            return ErrorCopy(
                title: String(localized: "The \(name) hook stopped this", bundle: .module),
                message: tail.isEmpty ? advice : tail + "\n\n" + advice
            )
        case .signingFailed(let detail):
            let reason = detail.split(separator: "\n").first.map(String.init) ?? ""
            let advice = String(localized: "Check the signing key in Settings, Accounts, or turn off signing for this repository. Your message is kept.", bundle: .module)
            return ErrorCopy(
                title: String(localized: "git couldn't sign the commit", bundle: .module),
                message: reason.isEmpty ? advice : reason + "\n\n" + advice
            )
        case .patchDoesNotApply:
            return ErrorCopy(
                title: String(localized: "Those lines changed on disk", bundle: .module),
                message: String(localized: "The file changed after Vrai showed it, so git couldn't apply the lines you picked. The diff is up to date now; pick the lines again.", bundle: .module)
            )
        case .lockFileExists(let path):
            return ErrorCopy(
                title: String(localized: "Another git process is running", bundle: .module),
                message: String(localized: "git left a lock file at \(path ?? ".git/index.lock"). Wait for the other process to finish, then try again. If nothing else is running, delete the lock file.", bundle: .module)
            )
        case .undoNoLongerApplies:
            return ErrorCopy(
                title: String(localized: "This can't be undone anymore", bundle: .module),
                message: String(localized: "The branch or files changed after it, so putting it back now would lose newer work. Earlier states stay in Reflog, part of Expert mode.", bundle: .module)
            )
        default:
            return nil
        }
    }

    static func hookTail(_ output: String) -> String {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let trimmed = lines.drop { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        return trimmed.suffix(hookOutputLines).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
