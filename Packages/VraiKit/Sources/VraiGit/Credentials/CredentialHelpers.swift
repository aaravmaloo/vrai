import Foundation

public struct CredentialHelper: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case keychain
        case cache
        case store
        case other

        public var configValue: String? {
            switch self {
            case .keychain: "osxkeychain"
            case .cache: "cache"
            case .store: "store"
            case .other: nil
            }
        }
    }

    public var value: String
    public var name: String
    public var kind: Kind
    public var options: [String]

    public var id: String { value }

    public init(_ value: String) {
        let words = CommandParser.words(value).map(CommandParser.unquote)
        self.value = value
        name = words.first ?? value
        options = Array(words.dropFirst())
        kind = Self.kind(of: name)
    }

    static func kind(of name: String) -> Kind {
        guard !name.hasPrefix("!") else { return .other }
        var short = URL(filePath: name).lastPathComponent
        if short.hasPrefix("git-credential-") { short.removeFirst("git-credential-".count) }
        switch short {
        case "osxkeychain": return .keychain
        case "cache": return .cache
        case "store": return .store
        default: return .other
        }
    }

    public func option(_ name: String) -> String? {
        for (index, word) in options.enumerated() {
            if word.hasPrefix(name + "=") { return String(word.dropFirst(name.count + 1)) }
            if word == name, index + 1 < options.count { return options[index + 1] }
        }
        return nil
    }

    public var socket: String? { kind == .cache ? option("--socket") : nil }
    public var file: String? { kind == .store ? option("--file") : nil }

    public static func effective(_ values: [String]) -> [CredentialHelper] {
        let start = values.lastIndex { $0.trimmingCharacters(in: .whitespaces).isEmpty }.map { $0 + 1 } ?? 0
        return values[start...].map { CredentialHelper($0.trimmingCharacters(in: .whitespaces)) }
    }
}

public enum CredentialHelperCommands {
    public static let key = "credential.helper"
    public static let schemes = ["https", "http"]

    public static let configured = ConfigCommands.getAll(key)

    public static func choose(_ kind: CredentialHelper.Kind) -> [GitCommand] {
        guard let value = kind.configValue else { return [] }
        return [
            ConfigCommands.unset(key, scope: .global),
            ConfigCommands.add(key, "", scope: .global),
            ConfigCommands.add(key, value, scope: .global)
        ]
    }

    public static func forgetCached(socket: String? = nil) -> GitCommand {
        var arguments = ["credential-cache"]
        if let socket { arguments += ["--socket", socket] }
        arguments.append("exit")
        return GitCommand(arguments, access: .write)
    }

    public static func eraseStored(file: String? = nil, scheme: String) -> GitCommand {
        var arguments = ["credential-store"]
        if let file { arguments.append("--file=" + file) }
        arguments.append("erase")
        return GitCommand(arguments, stdin: Data(("protocol=" + scheme + "\n\n").utf8), risk: .destructive, access: .write)
    }

    public static func expandHome(_ path: String, home: String?) -> String {
        guard let home, !home.isEmpty else { return path }
        if path == "~" { return home }
        guard path.hasPrefix("~/") else { return path }
        return home.trimmingSuffix("/") + "/" + path.dropFirst(2)
    }
}
