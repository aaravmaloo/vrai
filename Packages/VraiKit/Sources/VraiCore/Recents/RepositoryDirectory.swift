import Foundation
import Synchronization
import VraiGit

public enum RepositoryOwner {
    static let known = Mutex<[String: String?]>([:])

    public static func parse(_ remote: String?) -> String? {
        guard let remote else { return nil }
        if let owner = known.withLock({ $0[remote] }) { return owner }
        let owner = read(remote)
        known.withLock { $0[remote] = owner }
        return owner
    }

    static func read(_ remote: String) -> String? {
        guard let url = RemoteURL(remote), url.kind == .network || url.kind == .scp else { return nil }
        let segments = url.repositoryPath.split(separator: "/", omittingEmptySubsequences: true)
        guard segments.count >= 2 else { return nil }
        var owner = String(segments[0])
        while owner.hasPrefix("~") { owner.removeFirst() }
        return owner.isEmpty ? nil : owner
    }
}

public struct DirectoryEntry: Sendable, Hashable, Identifiable {
    public var path: String
    public var name: String
    public var owner: String?
    public var lastOpened: Date

    public var id: String { path }

    public init(path: String, name: String, owner: String?, lastOpened: Date) {
        self.path = path
        self.name = name
        self.owner = owner
        self.lastOpened = lastOpened
    }

    public init(_ recent: RecentRepository) {
        self.init(path: recent.path, name: recent.name, owner: RepositoryOwner.parse(recent.remote), lastOpened: recent.lastOpened)
    }

    public var qualifiedName: String {
        owner.map { $0 + "/" + name } ?? name
    }
}

public struct DirectorySection: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case recent
        case owner(String)
        case other
    }

    public var kind: Kind
    public var entries: [DirectoryEntry]

    public init(kind: Kind, entries: [DirectoryEntry]) {
        self.kind = kind
        self.entries = entries
    }

    public var id: String {
        switch kind {
        case .recent: "recent"
        case .owner(let name): "owner:" + name.lowercased()
        case .other: "other"
        }
    }
}

public enum RepositoryDirectory {
    public static let recentLimit = 3

    public static func sections(_ recents: [RecentRepository], current: String?, query: String = "") -> [DirectorySection] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = recents.map(DirectoryEntry.init)
        var out: [DirectorySection] = []
        if needle.isEmpty {
            let recent = entries.enumerated()
                .filter { $0.element.path != current }
                .sorted { $0.element.lastOpened != $1.element.lastOpened ? $0.element.lastOpened > $1.element.lastOpened : $0.offset < $1.offset }
                .prefix(recentLimit)
                .map(\.element)
            if !recent.isEmpty { out.append(DirectorySection(kind: .recent, entries: recent)) }
        }
        var owners: [String: (name: String, entries: [DirectoryEntry])] = [:]
        var other: [DirectoryEntry] = []
        for entry in entries {
            if !needle.isEmpty, score(entry, needle) <= 0 { continue }
            guard let owner = entry.owner else {
                other.append(entry)
                continue
            }
            owners[owner.lowercased(), default: (owner, [])].entries.append(entry)
        }
        let keys = owners.keys.sorted { ordered(owners[$0]?.name ?? $0, owners[$1]?.name ?? $1) }
        for key in keys {
            guard let group = owners[key] else { continue }
            out.append(DirectorySection(kind: .owner(group.name), entries: arrange(group.entries, needle)))
        }
        if !other.isEmpty { out.append(DirectorySection(kind: .other, entries: arrange(other, needle))) }
        return out
    }

    public static func score(_ entry: DirectoryEntry, _ query: String) -> Double {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return 1 }
        let name = PaletteRanking.match(entry.name, needle)
        let qualified = entry.owner == nil ? 0 : PaletteRanking.match(entry.qualifiedName, needle) * 0.9
        return max(name, qualified)
    }

    public static func flatten(_ sections: [DirectorySection]) -> [DirectoryEntry] {
        sections.flatMap(\.entries)
    }

    public static func bestIndex(_ sections: [DirectorySection], query: String) -> Int? {
        var best: (index: Int, score: Double)?
        for (index, entry) in flatten(sections).enumerated() {
            let value = score(entry, query)
            if best.map({ value > $0.score }) ?? true { best = (index, value) }
        }
        return best?.index
    }

    public static func index(of path: String?, in sections: [DirectorySection]) -> Int? {
        guard let path else { return nil }
        var offset = 0
        for section in sections {
            if section.kind != .recent, let found = section.entries.firstIndex(where: { $0.path == path }) { return offset + found }
            offset += section.entries.count
        }
        return nil
    }

    static func arrange(_ entries: [DirectoryEntry], _ needle: String) -> [DirectoryEntry] {
        guard !needle.isEmpty else { return entries.sorted { ordered($0, $1) } }
        return entries
            .map { (entry: $0, score: score($0, needle)) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : ordered($0.entry, $1.entry) }
            .map(\.entry)
    }

    static func ordered(_ lhs: DirectoryEntry, _ rhs: DirectoryEntry) -> Bool {
        let result = lhs.name.localizedStandardCompare(rhs.name)
        return result == .orderedSame ? lhs.path < rhs.path : result == .orderedAscending
    }

    static func ordered(_ lhs: String, _ rhs: String) -> Bool {
        let result = lhs.localizedStandardCompare(rhs)
        return result == .orderedSame ? lhs < rhs : result == .orderedAscending
    }
}
