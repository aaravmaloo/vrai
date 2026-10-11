import Foundation

public struct LayoutCommit: Sendable, Hashable {
    public var id: OID
    public var parents: [OID]
    public var color: Int?

    public init(id: OID, parents: [OID], color: Int? = nil) {
        self.id = id
        self.parents = parents
        self.color = color
    }
}

public struct GraphRow: Sendable, Hashable {
    public struct Segment: Sendable, Hashable, Codable {
        public enum Kind: String, Sendable, Hashable, Codable {
            case incoming = "in"
            case pass
            case outgoing = "out"
        }

        public var from: Int
        public var to: Int
        public var color: Int
        public var kind: Kind

        public init(from: Int, to: Int, color: Int, kind: Kind) {
            self.from = from
            self.to = to
            self.color = color
            self.kind = kind
        }
    }

    public var id: OID
    public var lane: Int
    public var color: Int
    public var top: [Segment]
    public var bottom: [Segment]
    public var width: Int
    public var isMerge: Bool
    public var isHead: Bool
}

public struct LaneLayout: Sendable {
    public var colorCount: Int
    public var keepMissing: Bool
    public private(set) var maxWidth = 1
    private var lanes: [OID?] = []
    private var laneColor: [Int] = []
    private var nextColor: Int

    public init(colorCount: Int = 8, firstColor: Int = 0, keepMissing: Bool = true) {
        self.colorCount = colorCount
        self.nextColor = firstColor
        self.keepMissing = keepMissing
    }

    public static func layout(_ commits: [LayoutCommit], head: OID? = nil, keepMissing: Bool = false, colorCount: Int = 8, firstColor: Int = 0) -> (rows: [GraphRow], lanes: Int) {
        var layout = LaneLayout(colorCount: colorCount, firstColor: firstColor, keepMissing: keepMissing)
        let known = Set(commits.map(\.id))
        var colors: [OID: Int] = [:]
        for commit in commits { if let color = commit.color { colors[commit.id] = color } }
        let rows = layout.append(commits, head: head, isKnown: { known.contains($0) }, colorOf: { colors[$0] })
        return (rows, layout.maxWidth)
    }

    private mutating func take() -> Int {
        let color = ((nextColor % colorCount) + colorCount) % colorCount
        nextColor += 1
        return color
    }

    private mutating func freeLane() -> Int {
        if let index = lanes.firstIndex(where: { $0 == nil }) { return index }
        lanes.append(nil)
        laneColor.append(0)
        return lanes.count - 1
    }

    public mutating func append(_ commits: [LayoutCommit], head: OID? = nil, isKnown: (OID) -> Bool = { _ in true }, colorOf: (OID) -> Int? = { _ in nil }) -> [GraphRow] {
        var rows: [GraphRow] = []
        rows.reserveCapacity(commits.count)
        for c in commits {
            var lane = lanes.firstIndex(of: c.id) ?? -1
            if lane < 0 {
                lane = freeLane()
                laneColor[lane] = c.color ?? take()
            }
            var top: [GraphRow.Segment] = []
            var incoming: [Int] = []
            for j in lanes.indices {
                guard let occupant = lanes[j] else { continue }
                if occupant == c.id {
                    top.append(.init(from: j, to: lane, color: laneColor[j], kind: .incoming))
                    if j != lane { incoming.append(j) }
                } else {
                    top.append(.init(from: j, to: j, color: laneColor[j], kind: .pass))
                }
            }
            for j in incoming { lanes[j] = nil }
            if let color = c.color { laneColor[lane] = color }
            let color = laneColor[lane]
            let parents = c.parents.filter { keepMissing || isKnown($0) }
            var bottom: [GraphRow.Segment] = []
            lanes[lane] = parents.first
            if !parents.isEmpty { bottom.append(.init(from: lane, to: lane, color: color, kind: .outgoing)) }
            for p in parents.dropFirst() {
                var m = lanes.firstIndex(of: p) ?? -1
                if m < 0 {
                    m = freeLane()
                    lanes[m] = p
                    laneColor[m] = colorOf(p) ?? take()
                }
                bottom.append(.init(from: lane, to: m, color: laneColor[m], kind: .outgoing))
            }
            for j in lanes.indices where lanes[j] != nil && j != lane && !bottom.contains(where: { $0.to == j }) {
                bottom.append(.init(from: j, to: j, color: laneColor[j], kind: .pass))
            }
            while let last = lanes.last, last == nil {
                lanes.removeLast()
                laneColor.removeLast()
            }
            var width = lane + 1
            for s in top { width = max(width, max(s.from, s.to) + 1) }
            for s in bottom { width = max(width, max(s.from, s.to) + 1) }
            maxWidth = max(maxWidth, width)
            rows.append(GraphRow(id: c.id, lane: lane, color: color, top: top, bottom: bottom, width: width, isMerge: c.parents.count > 1, isHead: c.id == head))
        }
        return rows
    }
}
