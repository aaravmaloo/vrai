import Foundation

public enum ConfigParser {
    public static let remotesCommand = GitCommand.read(["config", "-z", "--get-regexp", "^remote\\."], acceptedExitCodes: [0, 1])
    public static let tableCommand = GitCommand.read(["config", "--list", "--show-scope", "--show-origin", "-z"])

    public static func keyValues(_ data: Data) -> [(key: String, value: String)] {
        ParseSupport.nulFields(data).compactMap { field in
            guard !field.isEmpty else { return nil }
            guard let newline = field.firstIndex(of: "\n") else { return (key: field, value: "") }
            return (key: String(field[..<newline]), value: String(field[field.index(after: newline)...]))
        }
    }

    public static func remotes(_ data: Data, heads: [String: String] = [:]) -> [Remote] {
        var order: [String] = []
        var values: [String: [String: [String]]] = [:]
        for (key, value) in keyValues(data) {
            guard key.hasPrefix("remote.") else { continue }
            let rest = key.dropFirst("remote.".count)
            guard let dot = rest.lastIndex(of: ".") else { continue }
            let name = String(rest[..<dot])
            let field = String(rest[rest.index(after: dot)...]).lowercased()
            if values[name] == nil {
                order.append(name)
                values[name] = [:]
            }
            values[name]?[field, default: []].append(value)
        }
        return order.compactMap { name in
            guard let fields = values[name], let url = fields["url"]?.first else { return nil }
            return Remote(
                name: name,
                fetchURL: url,
                pushURL: fields["pushurl"]?.first,
                headBranch: heads[name],
                prune: fields["prune"]?.last.map { ["true", "yes", "on", "1"].contains($0.lowercased()) } ?? false
            )
        }
    }

    public static func table(_ data: Data) -> [ConfigEntry] {
        let fields = ParseSupport.nulFields(data)
        var entries: [ConfigEntry] = []
        var index = 0
        while index + 2 < fields.count {
            let scope = ConfigEntry.Scope(rawValue: fields[index]) ?? .unknown
            let origin = fields[index + 1]
            let pair = fields[index + 2]
            index += 3
            let key: String
            let value: String
            if let newline = pair.firstIndex(of: "\n") {
                key = String(pair[..<newline])
                value = String(pair[pair.index(after: newline)...])
            } else {
                key = pair
                value = ""
            }
            entries.append(ConfigEntry(scope: scope, origin: origin.isEmpty ? nil : origin, key: key, value: value))
        }
        return entries
    }

    public static func gitmodules(_ data: Data) -> [(name: String, path: String, url: String?, branch: String?)] {
        var order: [String] = []
        var values: [String: [String: String]] = [:]
        for (key, value) in keyValues(data) {
            guard key.hasPrefix("submodule.") else { continue }
            let rest = key.dropFirst("submodule.".count)
            guard let dot = rest.lastIndex(of: ".") else { continue }
            let name = String(rest[..<dot])
            if values[name] == nil {
                order.append(name)
                values[name] = [:]
            }
            values[name]?[String(rest[rest.index(after: dot)...]).lowercased()] = value
        }
        return order.compactMap { name in
            guard let fields = values[name], let path = fields["path"] else { return nil }
            return (name: name, path: path, url: fields["url"], branch: fields["branch"])
        }
    }
}
