import Foundation
import VraiGit

extension ErrorCopy {
    static let longTailSubcommands: Set<String> = [
        "am", "archive", "bundle", "sparse-checkout", "clean", "history", "format-patch", "gc", "fsck", "prune", "repack",
        "commit-graph", "backfill", "pack-refs", "mv", "rm", "update-index", "bugreport", "diagnose", "request-pull", "clone", "init", "index-pack"
    ]

    static func longTail(_ error: GitError) -> ErrorCopy? {
        switch error.code {
        case .pathExists:
            return ErrorCopy(
                title: String(localized: "That folder already exists", bundle: .module),
                message: String(localized: "It isn't empty, so git won't use it. Pick another folder or name.", bundle: .module)
            )
        case .cancelled:
            return ErrorCopy(
                title: String(localized: "Stopped", bundle: .module),
                message: String(localized: "git stopped before it finished. Nothing else changed.", bundle: .module)
            )
        case .invalidURL:
            return ErrorCopy(
                title: String(localized: "git doesn't understand that address", bundle: .module),
                message: String(localized: "Use git@host:owner/repo.git or https://host/owner/repo.git.", bundle: .module)
            )
        default:
            break
        }
        guard case .unknown = error.code, let sub = error.result?.command.subcommand, longTailSubcommands.contains(sub) else { return nil }
        let said = (error.result?.errorOutput ?? "").split(separator: "\n").prefix(6).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return ErrorCopy(
            title: longTailTitle(sub),
            message: said.isEmpty ? String(localized: "Try again. The console shows everything git said.", bundle: .module) : said
        )
    }

    static func longTailTitle(_ sub: String) -> String {
        switch sub {
        case "am": String(localized: "The patches didn't apply", bundle: .module)
        case "archive": String(localized: "The archive wasn't written", bundle: .module)
        case "bundle": String(localized: "The bundle wasn't written", bundle: .module)
        case "sparse-checkout": String(localized: "Sparse checkout didn't change", bundle: .module)
        case "clean": String(localized: "The files weren't removed", bundle: .module)
        case "history": String(localized: "git history stopped", bundle: .module)
        case "format-patch": String(localized: "The patch wasn't saved", bundle: .module)
        case "clone": String(localized: "The clone didn't finish", bundle: .module)
        case "init": String(localized: "git couldn't create the repository", bundle: .module)
        case "mv": String(localized: "git couldn't rename the file", bundle: .module)
        case "rm": String(localized: "git couldn't remove the file", bundle: .module)
        case "bugreport", "diagnose": String(localized: "git couldn't write the report", bundle: .module)
        default: String(localized: "Maintenance didn't finish", bundle: .module)
        }
    }
}
