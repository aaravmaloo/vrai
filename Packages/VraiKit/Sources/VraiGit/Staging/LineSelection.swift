import Foundation

public struct LineID: Sendable, Hashable, Comparable, Codable {
    public var hunk: Int
    public var line: Int

    public init(hunk: Int, line: Int) {
        self.hunk = hunk
        self.line = line
    }

    public static func < (lhs: LineID, rhs: LineID) -> Bool {
        (lhs.hunk, lhs.line) < (rhs.hunk, rhs.line)
    }
}

public struct LineSelection: Sendable, Hashable {
    public enum Side: String, Sendable, Hashable, Codable {
        case unstaged
        case staged
    }

    public var file: FileDiff
    public var side: Side
    public private(set) var lines: Set<LineID>
    public private(set) var anchor: LineID?

    public init(file: FileDiff, side: Side, lines: some Sequence<LineID> = [LineID]()) {
        self.file = file
        self.side = side
        self.lines = []
        self.anchor = nil
        self.lines = Set(lines.filter { isSelectable($0) })
    }

    public static func hunk(_ index: Int, in file: FileDiff, side: Side) -> LineSelection {
        LineSelection(file: file, side: side, lines: changedLines(in: file, hunk: index))
    }

    public static func all(in file: FileDiff, side: Side) -> LineSelection {
        LineSelection(file: file, side: side, lines: file.hunks.indices.flatMap { changedLines(in: file, hunk: $0) })
    }

    static func changedLines(in file: FileDiff, hunk index: Int) -> [LineID] {
        guard file.hunks.indices.contains(index) else { return [] }
        return file.hunks[index].lines.indices.compactMap { line in
            let kind = file.hunks[index].lines[line].kind
            return kind == .add || kind == .del ? LineID(hunk: index, line: line) : nil
        }
    }

    public var path: String { file.path }
    public var isEmpty: Bool { lines.isEmpty }
    public var count: Int { lines.count }
    public var sorted: [LineID] { lines.sorted() }

    public var additions: Int { lines.count { kind(of: $0) == .add } }
    public var deletions: Int { lines.count { kind(of: $0) == .del } }

    public func kind(of id: LineID) -> DiffLine.Kind? {
        guard file.hunks.indices.contains(id.hunk), file.hunks[id.hunk].lines.indices.contains(id.line) else { return nil }
        return file.hunks[id.hunk].lines[id.line].kind
    }

    public func isSelectable(_ id: LineID) -> Bool {
        let kind = kind(of: id)
        return kind == .add || kind == .del
    }

    public func contains(_ id: LineID) -> Bool { lines.contains(id) }

    public func lines(inHunk hunk: Int) -> [Int] {
        lines.filter { $0.hunk == hunk }.map(\.line).sorted()
    }

    public func count(inHunk hunk: Int) -> Int {
        lines.count { $0.hunk == hunk }
    }

    public var hunks: [Int] { Set(lines.map(\.hunk)).sorted() }

    public func limited(toHunk hunk: Int) -> LineSelection {
        var copy = self
        copy.lines = lines.filter { $0.hunk == hunk }
        return copy
    }

    public mutating func click(_ id: LineID, extending: Bool = false, toggling: Bool = false) {
        guard isSelectable(id) else { return }
        var next: Set<LineID> = extending || toggling ? lines : []
        if extending, let anchor {
            next.formUnion(selectable(from: anchor, to: id))
        } else if lines.contains(id), lines.count == 1 {
            next.remove(id)
        } else if toggling, lines.contains(id) {
            next.remove(id)
        } else {
            next.insert(id)
        }
        anchor = id
        lines = next
    }

    public func selectable(from start: LineID, to end: LineID) -> [LineID] {
        let low = min(start, end)
        let high = max(start, end)
        guard !file.hunks.isEmpty, low.hunk < file.hunks.count else { return [] }
        var out: [LineID] = []
        for hunk in max(0, low.hunk)...min(high.hunk, file.hunks.count - 1) {
            for line in file.hunks[hunk].lines.indices {
                let id = LineID(hunk: hunk, line: line)
                if id >= low, id <= high, isSelectable(id) { out.append(id) }
            }
        }
        return out
    }

    public mutating func drag(from start: LineID, to end: LineID, keeping base: Set<LineID> = []) {
        anchor = start
        lines = base.filter(isSelectable).union(selectable(from: start, to: end))
    }

    public mutating func select(_ ids: some Sequence<LineID>) {
        for id in ids where isSelectable(id) { lines.insert(id) }
    }

    public mutating func deselect(_ ids: some Sequence<LineID>) {
        for id in ids { lines.remove(id) }
    }

    public mutating func clear() {
        lines = []
        anchor = nil
    }
}
