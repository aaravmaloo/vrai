import Foundation

extension ConfigEntry.Scope {
    public var flag: String? {
        switch self {
        case .system, .global, .local, .worktree: "--" + rawValue
        case .command, .unknown: nil
        }
    }

    public var isWritable: Bool {
        switch self {
        case .global, .local, .worktree: true
        case .system, .command, .unknown: false
        }
    }

    public var rank: Int {
        switch self {
        case .command: 0
        case .worktree: 1
        case .local: 2
        case .global: 3
        case .system: 4
        case .unknown: 5
        }
    }
}

public struct ConfigWrite: Sendable, Hashable {
    public var key: String
    public var value: String?

    public init(_ key: String, _ value: String?) {
        self.key = key
        self.value = value
    }
}

public enum ConfigCommands {
    public static let table = GitCommand.read(["config", "--list", "--show-scope", "--show-origin", "-z"])
    public static let version = GitCommand.read(["version"])

    public static func get(_ key: String, scope: ConfigEntry.Scope? = nil) -> GitCommand {
        .read(["config"] + flags(scope) + ["-z", "--get", key], acceptedExitCodes: [0, 1])
    }

    public static func getAll(_ key: String, scope: ConfigEntry.Scope? = nil) -> GitCommand {
        .read(["config"] + flags(scope) + ["-z", "--get-all", key], acceptedExitCodes: [0, 1])
    }

    public static func set(_ key: String, _ value: String, scope: ConfigEntry.Scope) -> GitCommand {
        GitCommand(["config"] + flags(scope) + [key, value], access: .write)
    }

    public static func add(_ key: String, _ value: String, scope: ConfigEntry.Scope) -> GitCommand {
        GitCommand(["config"] + flags(scope) + ["--add", key, value], access: .write)
    }

    public static func replace(_ key: String, old: String, new: String, scope: ConfigEntry.Scope) -> GitCommand {
        GitCommand(["config"] + flags(scope) + ["--replace-all", "--fixed-value", key, new, old], access: .write)
    }

    public static func unset(_ key: String, scope: ConfigEntry.Scope) -> GitCommand {
        GitCommand(["config"] + flags(scope) + ["--unset-all", key], access: .write, acceptedExitCodes: [0, 5])
    }

    public static func remove(_ key: String, value: String, scope: ConfigEntry.Scope) -> GitCommand {
        GitCommand(["config"] + flags(scope) + ["--unset-all", "--fixed-value", key, value], access: .write, acceptedExitCodes: [0, 5])
    }

    public static func write(_ change: ConfigWrite, scope: ConfigEntry.Scope) -> GitCommand {
        if let value = change.value { return set(change.key, value, scope: scope) }
        return unset(change.key, scope: scope)
    }

    public static func value(_ data: Data) -> String? {
        ParseSupport.nulFields(data).last
    }

    public static func values(_ data: Data) -> [String] {
        ParseSupport.nulFields(data)
    }

    static func flags(_ scope: ConfigEntry.Scope?) -> [String] {
        scope?.flag.map { [$0] } ?? []
    }

    public static func isValidKey(_ key: String) -> Bool {
        key.wholeMatch(of: /[A-Za-z][A-Za-z0-9-]*(\.[^\s=]+)?\.[A-Za-z][A-Za-z0-9-]*/) != nil
    }

    public static func canonical(_ key: String) -> String {
        guard let first = key.firstIndex(of: "."), let last = key.lastIndex(of: ".") else { return key.lowercased() }
        let section = key[..<first].lowercased()
        let name = key[key.index(after: last)...].lowercased()
        if first == last { return section + "." + name }
        return section + String(key[first..<last]) + "." + name
    }
}

public enum ConfigBool {
    public static func parse(_ raw: String) -> Bool? {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "true", "yes", "on", "1": true
        case "false", "no", "off", "0", "": false
        default: nil
        }
    }

    public static func string(_ value: Bool) -> String {
        value ? "true" : "false"
    }
}

public struct ConfigValues: Sendable, Hashable {
    public private(set) var entries: [ConfigEntry]

    public init(_ entries: [ConfigEntry] = []) {
        self.entries = entries
    }

    public init(table data: Data, scope: ConfigEntry.Scope? = nil) {
        let all = ConfigParser.table(data)
        entries = scope.map { wanted in all.filter { $0.scope == wanted } } ?? all
    }

    public func values(_ key: String) -> [String] {
        let wanted = ConfigCommands.canonical(key)
        return entries.filter { ConfigCommands.canonical($0.key) == wanted }.map(\.value)
    }

    public func value(_ key: String) -> String? {
        values(key).last
    }

    public func bool(_ key: String) -> Bool? {
        value(key).flatMap(ConfigBool.parse)
    }

    public func has(_ key: String) -> Bool {
        !values(key).isEmpty
    }
}
