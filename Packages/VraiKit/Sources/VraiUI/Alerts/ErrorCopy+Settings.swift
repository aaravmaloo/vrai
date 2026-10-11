import VraiGit

extension ErrorCopy {
    static func settings(_ error: GitError) -> ErrorCopy? {
        guard let command = error.result?.command, case .unknown = error.code else { return nil }
        let detail = error.result?.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch command.subcommand {
        case "config":
            return ErrorCopy(
                title: String(localized: "git didn't change that setting", bundle: .module),
                message: detail.isEmpty ? String(localized: "git config stopped without saying why. Check the file in Terminal with git config --list --show-origin.", bundle: .module) : detail
            )
        case "maintenance":
            return ErrorCopy(
                title: String(localized: "Maintenance didn't finish", bundle: .module),
                message: detail.isEmpty ? String(localized: "git maintenance stopped without saying why. The console shows what ran.", bundle: .module) : detail
            )
        case "hook":
            return ErrorCopy(
                title: String(localized: "The hook didn't run", bundle: .module),
                message: detail.isEmpty ? String(localized: "git hook run stopped without saying why. Check that the script is executable.", bundle: .module) : detail
            )
        case "credential":
            return ErrorCopy(
                title: String(localized: "git couldn't update your saved credentials", bundle: .module),
                message: detail.isEmpty ? String(localized: "The credential helper stopped without saying why.", bundle: .module) : detail
            )
        default:
            return nil
        }
    }
}
