import Foundation

public protocol PaletteRankable {
    var rankLabel: String { get }
    var rankKeywords: String? { get }
    var rankDetail: String? { get }
    var rankCurrent: Bool { get }
}

public enum PaletteGroupKind: String, Sendable, Hashable, CaseIterable {
    case run
    case topHit
    case suggestions
    case recentBranches
    case actions
    case branches
    case remoteBranches
    case newBranch
    case tags
    case commits
    case files
    case code

    public var weight: Double? {
        switch self {
        case .suggestions: 1.2
        case .actions: 1.1
        case .branches: 1.15
        case .remoteBranches: 0.95
        case .tags: 1
        case .commits: 0.75
        case .files: 0.85
        default: nil
        }
    }
}

public struct PaletteGroup<Item> {
    public var kind: PaletteGroupKind
    public var items: [Item]
    public var limit: Int?

    public init(_ kind: PaletteGroupKind, _ items: [Item], limit: Int? = nil) {
        self.kind = kind
        self.items = items
        self.limit = limit
    }
}

public enum PaletteRanking {
    public static func match(_ text: String, _ query: String) -> Double {
        let t = Array(text.lowercased())
        let s = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return 1 }
        let needle = Array(s)
        if t.starts(with: needle) { return 100 - Double(t.count) / 100 }
        if let index = firstIndex(of: needle, in: t) { return 60 - Double(index) / 10 }
        var from = 0
        var hits = 0
        var last = -2
        var run = 0
        for ch in needle {
            if ch == " " { continue }
            guard let j = t[min(from, t.count)...].firstIndex(of: ch) else { return 0 }
            hits += 1
            if j == last + 1 { run += 1 }
            last = j
            from = j + 1
        }
        return 10 + Double(run) * 2 + Double(hits) / 10
    }

    static func firstIndex(of needle: [Character], in haystack: [Character]) -> Int? {
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
        let first = needle[0]
        var index = 0
        while index + needle.count <= haystack.count {
            if haystack[index] == first, Array(haystack[index..<index + needle.count]) == needle { return index }
            index += 1
        }
        return nil
    }

    public static func score<Item: PaletteRankable>(_ item: Item, _ query: String) -> Double {
        max(
            match(item.rankLabel, query),
            item.rankKeywords.map { match($0, query) * 0.9 } ?? 0,
            item.rankDetail.map { match($0, query) * 0.6 } ?? 0
        )
    }

    public static func relevant<Item: PaletteRankable>(_ item: Item, _ query: String) -> Bool {
        if match(item.rankLabel, query) > 0 { return true }
        if let keywords = item.rankKeywords, match(keywords, query) > 0 { return true }
        if let detail = item.rankDetail, match(detail, query) >= 50 { return true }
        return false
    }

    public static func filterRelevant<Item: PaletteRankable>(_ groups: [PaletteGroup<Item>], _ query: String) -> [PaletteGroup<Item>] {
        groups.map { group in
            var copy = group
            copy.items = group.items.filter { relevant($0, query) }
            return copy
        }
    }

    public static func promoteTopHit<Item: PaletteRankable>(_ groups: [PaletteGroup<Item>], _ query: String, same: (Item, Item) -> Bool) -> [PaletteGroup<Item>] {
        var best: (group: Int, item: Item, score: Double)?
        for (index, group) in groups.enumerated() {
            guard let weight = group.kind.weight else { continue }
            for item in group.items {
                let raw = score(item, query)
                let weighted = raw * weight * (item.rankCurrent ? 0.8 : 1)
                if raw >= 50, best.map({ weighted > $0.score }) ?? true { best = (index, item, weighted) }
            }
        }
        guard let best else { return groups }
        var out = groups
        out[best.group].items.removeAll { same($0, best.item) }
        out.insert(PaletteGroup(.topHit, [best.item], limit: 1), at: 0)
        return out
    }

    public static func arrange<Item: PaletteRankable>(_ groups: [PaletteGroup<Item>], _ query: String) -> [PaletteGroup<Item>] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var out: [PaletteGroup<Item>] = []
        for group in groups {
            var items: [Item]
            if q.isEmpty {
                items = Array(group.items.prefix(group.limit ?? 8))
            } else {
                let scored = group.items.enumerated().map { (offset: $0.offset, item: $0.element, score: score($0.element, q)) }.filter { $0.score > 0 }
                let sorted = scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }
                items = Array(sorted.prefix(group.limit ?? 6).map(\.item))
            }
            guard !items.isEmpty else { continue }
            var copy = group
            copy.items = items
            out.append(copy)
        }
        return out
    }
}
