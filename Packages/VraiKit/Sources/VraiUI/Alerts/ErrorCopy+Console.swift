import VraiGit

extension ErrorCopy {
    static func console(_ error: GitError) -> ErrorCopy? {
        guard let result = error.result else { return nil }
        let detail = result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        switch result.command.subcommand {
        case "notes":
            return ErrorCopy(
                title: String(localized: "Couldn't save the note", bundle: .module),
                message: detail.isEmpty ? String(localized: "git couldn't update refs/notes/commits. Try again, or run git notes in the console to see why.", bundle: .module) : detail
            )
        case "cat-file":
            return ErrorCopy(
                title: String(localized: "git couldn't show that object", bundle: .module),
                message: detail.isEmpty ? String(localized: "It may have been pruned. Check the reflog for where it went.", bundle: .module) : detail
            )
        case "grep", "ls-files":
            return ErrorCopy(
                title: String(localized: "Couldn't search this repository", bundle: .module),
                message: detail.isEmpty ? String(localized: "git stopped before it finished. Try a shorter search.", bundle: .module) : detail
            )
        default:
            return nil
        }
    }
}
