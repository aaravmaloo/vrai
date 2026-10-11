import Foundation
import VraiGit

public struct TypedCommand: Sendable, Hashable {
    public var command: GitCommand
    public var changesRepository: Bool
    public var subcommand: String

    public var risk: GitCommand.Risk { command.risk }
    public var display: String { command.display }
    var rest: [String] { Array(command.arguments.dropFirst()) }

    public enum Problem: Sendable, Hashable {
        case empty
        case notGit
        case globalOptions
    }

    public static let allowedLeadingOptions: Set<String> = ["--version", "--help", "-v", "-h"]

    public static func problem(_ text: String, impliedGit: Bool = true) -> Problem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard let parsed = impliedGit ? CommandParser.parseImplied(trimmed) : CommandParser.parse(trimmed) else { return .notGit }
        if parsed.subcommand.isEmpty { return .empty }
        if parsed.subcommand.hasPrefix("-"), !allowedLeadingOptions.contains(parsed.subcommand) { return .globalOptions }
        return nil
    }

    public init?(_ text: String, impliedGit: Bool = true) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.problem(trimmed, impliedGit: impliedGit) == nil else { return nil }
        guard let parsed = impliedGit ? CommandParser.parseImplied(trimmed) : CommandParser.parse(trimmed) else { return nil }
        let reads = Self.readsOnly(sub: parsed.subcommand, rest: Array(parsed.arguments.dropFirst()))
        var command = GitCommand(parsed.arguments, risk: parsed.risk, access: reads ? .read : .write)
        command.display = parsed.text
        self.command = command
        subcommand = parsed.subcommand
        changesRepository = !reads
    }

    public init(command built: GitCommand) {
        var command = built
        let parsed = CommandParser.parse(built.display)
        if let risk = parsed?.risk, Self.rank(risk) > Self.rank(built.risk) { command.risk = risk }
        self.command = command
        subcommand = built.subcommand ?? ""
        changesRepository = built.access == .write
    }

    public static func rank(_ risk: GitCommand.Risk) -> Int {
        switch risk {
        case .safe: 0
        case .rewrites: 1
        case .destructive: 2
        }
    }

    public static func risk(of command: GitCommand) -> GitCommand.Risk {
        guard let parsed = CommandParser.parse(command.display) else { return command.risk }
        return rank(parsed.risk) > rank(command.risk) ? parsed.risk : command.risk
    }

    public var opensEditor: Bool {
        switch subcommand {
        case "commit":
            if rest.contains(where: { $0 == "--help" || $0 == "-h" }) { return false }
            let supplies = rest.contains { flag in
                ["-m", "-F", "-C", "--no-edit", "--file", "--message", "--reuse-message"].contains(flag)
                    || flag.hasPrefix("--message=") || flag.hasPrefix("--file=") || flag.hasPrefix("--reuse-message=") || flag.hasPrefix("--fixup")
                    || flag.hasPrefix("-m") || flag.hasPrefix("-F") || flag.hasPrefix("-C")
            }
            return !supplies
        case "rebase":
            return rest.contains("-i") || rest.contains("--interactive")
        default:
            return false
        }
    }

    public var interactiveRebaseTarget: String? {
        guard subcommand == "rebase" else { return nil }
        guard rest.contains("-i") || rest.contains("--interactive") else { return nil }
        return rest.last { !$0.hasPrefix("-") }
    }

    static let readOnlySubcommands: Set<String> = [
        "log", "show", "status", "diff", "blame", "annotate", "cat-file", "rev-parse", "ls-files", "ls-tree", "ls-remote",
        "grep", "describe", "shortlog", "whatchanged", "for-each-ref", "show-ref", "show-branch", "rev-list", "merge-base",
        "name-rev", "count-objects", "verify-commit", "verify-tag", "verify-pack", "version", "help", "check-ignore", "check-attr",
        "check-mailmap", "check-ref-format", "cherry", "diff-tree", "diff-index", "diff-files", "range-diff", "var", "fsck",
        "get-tar-commit-id", "show-index", "patch-id", "interpret-trailers", "stripspace", "last-modified"
    ]

    static func readsOnly(sub: String, rest: [String]) -> Bool {
        if readOnlySubcommands.contains(sub) || allowedLeadingOptions.contains(sub) { return true }
        let positional = rest.filter { !$0.hasPrefix("-") }
        switch sub {
        case "branch":
            let listing: Set<String> = ["-a", "--all", "-r", "--remotes", "-v", "-vv", "--verbose", "-l", "--list", "--show-current", "--no-color", "--color", "--column", "--no-column"]
            let filters = ["--contains", "--no-contains", "--merged", "--no-merged", "--points-at", "--sort", "--format", "--abbrev", "--color=", "--column="]
            let flagsOnly = rest.allSatisfy { arg in listing.contains(arg) || filters.contains { arg.hasPrefix($0) } }
            if flagsOnly, positional.isEmpty { return true }
            return rest.contains("--list") || rest.contains("-l") || rest.contains("--show-current")
        case "tag":
            if rest.isEmpty { return true }
            return rest.contains("-l") || rest.contains("--list") || rest.contains("-v") || rest.contains("--verify") || rest.contains { $0.hasPrefix("--contains") || $0.hasPrefix("--points-at") || $0.hasPrefix("-n") }
        case "stash":
            return ["list", "show"].contains(rest.first ?? "")
        case "remote":
            if positional.isEmpty { return true }
            return ["show", "get-url"].contains(positional.first ?? "")
        case "config":
            return rest.contains { ["--get", "--get-all", "--get-regexp", "--list", "-l", "--get-urlmatch", "--show-origin", "--show-scope", "get", "list"].contains($0) }
                && !rest.contains { ["--unset", "--unset-all", "--add", "--replace-all", "--rename-section", "--remove-section", "set", "unset", "--edit", "-e"].contains($0) }
        case "reflog":
            return positional.isEmpty || ["show", "exists"].contains(positional.first ?? "")
        case "worktree":
            return positional.first == "list"
        case "submodule":
            return ["status", "summary"].contains(positional.first ?? "")
        case "notes":
            return positional.isEmpty || ["list", "show"].contains(positional.first ?? "")
        case "bisect":
            return ["log", "visualize", "view", "terms"].contains(positional.first ?? "")
        case "sparse-checkout":
            return positional.first == "list"
        case "lfs":
            return ["env", "ls-files", "status", "version", "track"].contains(positional.first ?? "") && !(positional.first == "track" && positional.count > 1)
        case "maintenance":
            return false
        default:
            return false
        }
    }
}

public struct TypedRun: Sendable {
    public var typed: TypedCommand
    public var result: GitResult
    public var entryID: UUID?
    public var fullOutput: URL?

    public var succeeded: Bool { result.succeeded }
}

public struct GrepMatch: Sendable, Hashable, Identifiable {
    public var path: String
    public var line: Int
    public var text: String

    public var id: String { path + ":" + String(line) }

    public init(path: String, line: Int, text: String) {
        self.path = path
        self.line = line
        self.text = text
    }

    public static func parse(_ data: Data, revision: String? = nil, limit: Int = .max) -> [GrepMatch] {
        var out: [GrepMatch] = []
        for rawLine in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if out.count >= limit { break }
            let fields = rawLine.split(separator: 0, maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3 else { continue }
            var path = String(decoding: fields[0], as: UTF8.self)
            if let revision, path.hasPrefix(revision + ":") { path.removeFirst(revision.count + 1) }
            guard let number = Int(String(decoding: fields[1], as: UTF8.self)) else { continue }
            out.append(GrepMatch(path: path, line: number, text: String(decoding: fields[2], as: UTF8.self)))
        }
        return out
    }
}
