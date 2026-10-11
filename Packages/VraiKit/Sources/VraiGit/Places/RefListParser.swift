import Foundation

public struct RefEntry: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case symbolic
        case pseudo
        case branch
        case remote
        case tag
        case annotatedTag
        case stash
        case notes
        case replace
        case undo
        case bisect
        case other
    }

    public var name: String
    public var target: OID?
    public var symbolicTarget: String?
    public var objectType: String?
    public var peeled: OID?
    public var kind: Kind

    public var id: String { name }

    public init(name: String, target: OID?, symbolicTarget: String? = nil, objectType: String? = nil, peeled: OID? = nil, kind: Kind) {
        self.name = name
        self.target = target
        self.symbolicTarget = symbolicTarget
        self.objectType = objectType
        self.peeled = peeled
        self.kind = kind
    }

    public var commit: OID? {
        if let peeled { return peeled }
        return objectType == nil || objectType == "commit" ? target : nil
    }

    public var namespace: String {
        guard name.hasPrefix("refs/") else { return "" }
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count <= 2 { return name }
        return parts.prefix(2).joined(separator: "/")
    }

    public var replacedObject: String? {
        guard kind == .replace else { return nil }
        return String(name.dropFirst("refs/replace/".count))
    }
}

public enum RefListParser {
    static let fields = ["%(refname)", "%(objectname)", "%(objecttype)", "%(symref)", "%(*objectname)"]
    public static let format = fields.map { $0 + "%00" }.joined()
    public static let command = GitCommand.read(["for-each-ref", "--format=" + format])

    public static func parse(_ data: Data) -> [RefEntry] {
        var entries: [RefEntry] = []
        for record in data.split(separator: 0x0A) {
            var parts = record.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
            if parts.last == "" { parts.removeLast() }
            guard parts.count >= fields.count, !parts[0].isEmpty else { continue }
            let name = parts[0]
            let symbolic = parts[3].isEmpty ? nil : parts[3]
            entries.append(RefEntry(name: name, target: OID(parts[1]), symbolicTarget: symbolic, objectType: parts[2].isEmpty ? nil : parts[2], peeled: OID(parts[4]), kind: kind(of: name, type: parts[2], symbolic: symbolic != nil)))
        }
        return entries
    }

    public static func kind(of name: String, type: String, symbolic: Bool) -> RefEntry.Kind {
        if symbolic { return .symbolic }
        if name.hasPrefix("refs/heads/") { return .branch }
        if name.hasPrefix("refs/remotes/") { return .remote }
        if name.hasPrefix("refs/tags/") { return type == "tag" ? .annotatedTag : .tag }
        if name == "refs/stash" { return .stash }
        if name.hasPrefix("refs/notes/") { return .notes }
        if name.hasPrefix("refs/replace/") { return .replace }
        if name.hasPrefix(UndoStore.refNamespace) { return .undo }
        if name.hasPrefix("refs/bisect/") { return .bisect }
        return .other
    }
}
