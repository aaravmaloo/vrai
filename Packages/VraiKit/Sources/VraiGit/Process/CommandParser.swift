import Foundation

public struct ParsedCommand: Sendable, Hashable {
    public var subcommand: String
    public var rawArguments: [String]
    public var arguments: [String]
    public var risk: GitCommand.Risk
    public var text: String

    public var command: GitCommand {
        var command = GitCommand(arguments, risk: risk, access: .write)
        command.display = text
        return command
    }
}

public enum CommandParser {
    static func words(_ text: String) -> [String] {
        text.matches(of: #/"[^"]*"|'[^']*'|\S+/#).map { String($0.output) }
    }

    static func unquote(_ word: String) -> String {
        if word.count >= 2, (word.hasPrefix("\"") && word.hasSuffix("\"")) || (word.hasPrefix("'") && word.hasSuffix("'")) {
            return String(word.dropFirst().dropLast())
        }
        return word
    }

    public static func parse(_ input: String) -> ParsedCommand? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let prompt = s.firstMatch(of: #/^\$\s*/#) { s.removeSubrange(prompt.range) }
        let parts = words(s)
        guard parts.first == "git" else { return nil }
        let sub = parts.count > 1 ? parts[1] : ""
        let rest = Array(parts.dropFirst(2))
        return ParsedCommand(subcommand: sub, rawArguments: rest, arguments: parts.dropFirst().map(unquote), risk: risk(sub: sub, rest: rest), text: s)
    }

    public static func parseImplied(_ input: String) -> ParsedCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("git ") || trimmed == "git" { return parse(trimmed) }
        return parse("git " + trimmed)
    }

    static func risk(sub: String, rest: [String]) -> GitCommand.Risk {
        func has(_ regex: Regex<Substring>) -> Bool { rest.contains { $0.wholeMatch(of: regex) != nil } }
        func hasPrefix(_ regex: Regex<Substring>) -> Bool { rest.contains { $0.prefixMatch(of: regex) != nil } }
        let force = #/-f|--force/#
        let control = has(#/--(?:abort|continue|quit|show-current-patch)/#)
        let risky = (sub == "push" && has(force))
            || (sub == "reset" && rest.contains("--hard"))
            || (sub == "clean" && hasPrefix(#/-\w*f/#))
            || (sub == "branch" && (rest.contains("-D") || (rest.contains("-d") && rest.contains("--force"))))
            || sub == "filter-branch"
            || (sub == "checkout" && (rest.contains("--") || has(force)))
            || (sub == "restore" && !rest.contains("--staged") && !rest.contains("-S"))
            || (sub == "stash" && (rest.first == "drop" || rest.first == "clear"))
            || (sub == "worktree" && rest.first == "remove" && has(force))
            || (sub == "push" && rest.contains("--delete"))
            || (sub == "tag" && rest.contains("-d"))
        let resetRewrites = sub == "reset" && !rest.contains("--hard") && !rest.isEmpty && !rest.allSatisfy { r in
            r == "--" || (r.contains("/") && r.prefixMatch(of: #/HEAD|[0-9a-f]{7,}/#) == nil)
        }
        let rewrites = !control && (
            sub == "rebase" || sub == "history" || sub == "replay"
            || (sub == "commit" && rest.contains("--amend"))
            || resetRewrites
            || (sub == "push" && hasPrefix(#/--force-with-lease/#))
            || (sub == "commit" && hasPrefix(#/--fixup=(?:amend|reword):/#))
        )
        return risky ? .destructive : (rewrites ? .rewrites : .safe)
    }
}

public enum CommandTokenizer {
    public enum Kind: String, Sendable, Hashable {
        case git
        case sub
        case str
        case flag
        case arg
    }

    public struct Token: Sendable, Hashable {
        public var text: String
        public var kind: Kind?
    }

    public static func tokenize(_ command: String) -> [Token] {
        var seenGit = false
        var seenSub = false
        return command.matches(of: #/"[^"]*"|'[^']*'|\S+|\s+/#).map { match in
            let t = String(match.output)
            if t.allSatisfy(\.isWhitespace) { return Token(text: t, kind: nil) }
            if !seenGit, t == "git" {
                seenGit = true
                return Token(text: t, kind: .git)
            }
            if seenGit, !seenSub, !t.hasPrefix("-") {
                seenSub = true
                return Token(text: t, kind: .sub)
            }
            if t.hasPrefix("\"") || t.hasPrefix("'") { return Token(text: t, kind: .str) }
            if t.hasPrefix("-") { return Token(text: t, kind: .flag) }
            return Token(text: t, kind: .arg)
        }
    }
}
