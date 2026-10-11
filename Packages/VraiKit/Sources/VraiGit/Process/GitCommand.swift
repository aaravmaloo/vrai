import Foundation

public struct GitCommand: Sendable, Hashable {
    public enum Risk: String, Sendable, Hashable, Codable {
        case safe
        case rewrites
        case destructive
    }

    public enum Access: Sendable, Hashable {
        case read
        case write
    }

    public var arguments: [String]
    public var stdin: Data?
    public var risk: Risk
    public var display: String
    public var access: Access
    public var acceptedExitCodes: Set<Int32>
    public var environment: [String: String]
    public var editor: String?
    public var sequenceEditor: String?

    public init(
        _ arguments: [String],
        stdin: Data? = nil,
        risk: Risk = .safe,
        access: Access = .read,
        acceptedExitCodes: Set<Int32> = [0],
        environment: [String: String] = [:],
        editor: String? = nil,
        sequenceEditor: String? = nil
    ) {
        self.arguments = arguments
        self.stdin = stdin
        self.risk = risk
        self.access = access
        self.acceptedExitCodes = acceptedExitCodes
        self.environment = environment
        self.editor = editor
        self.sequenceEditor = sequenceEditor
        self.display = CommandDisplay.render(["git"] + arguments)
    }

    public static func read(_ arguments: [String], acceptedExitCodes: Set<Int32> = [0]) -> GitCommand {
        GitCommand(arguments, access: .read, acceptedExitCodes: acceptedExitCodes)
    }

    public static func write(_ arguments: [String], stdin: Data? = nil, risk: Risk = .safe) -> GitCommand {
        GitCommand(arguments, stdin: stdin, risk: risk, access: .write)
    }

    public var subcommand: String? { arguments.first { !$0.hasPrefix("-") } }
}

public enum CommandDisplay {
    public static func render(_ words: [String]) -> String {
        words.map(quote).joined(separator: " ")
    }

    public static func quote(_ word: String) -> String {
        if word.isEmpty { return "\"\"" }
        let needsQuotes = word.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) || $0 == "\"" || $0 == "'" }
        guard needsQuotes else { return word }
        if !word.contains("\"") { return "\"" + word + "\"" }
        if !word.contains("'") { return "'" + word + "'" }
        return "\"" + word.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
