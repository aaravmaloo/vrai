import Foundation

public struct BranchColors: Sendable, Hashable, Codable {
    public static let mainLines: Set<String> = ["main", "master", "trunk"]
    public static let laneCount = 8

    public private(set) var assignments: [String: Int]
    public private(set) var next: Int

    public init(assignments: [String: Int] = [:], next: Int = 1) {
        self.assignments = assignments
        self.next = next
    }

    public func color(for branch: String) -> Int? {
        assignments[branch]
    }

    @discardableResult
    public mutating func assign(_ branch: String) -> Int {
        if let existing = assignments[branch] { return existing }
        let color: Int
        if Self.mainLines.contains(branch) {
            color = 0
        } else {
            color = 1 + ((next - 1) % (Self.laneCount - 1))
            next += 1
        }
        assignments[branch] = color
        return color
    }

    public static func branchName(forRemote remoteBranch: RemoteBranch) -> String { remoteBranch.name }

    public mutating func assign(branches: [Branch], remoteBranches: [RemoteBranch], current: String?) {
        for name in branches.map(\.name) where Self.mainLines.contains(name) { assign(name) }
        if let current { assign(current) }
        for name in branches.map(\.name).sorted() { assign(name) }
        for remote in remoteBranches.sorted(by: { $0.fullName < $1.fullName }) { assign(Self.branchName(forRemote: remote)) }
    }

    public func tipColors(branches: [Branch], remoteBranches: [RemoteBranch], current: String?) -> [OID: Int] {
        var colors: [OID: Int] = [:]
        for remote in remoteBranches {
            if let color = assignments[remote.name] { colors[remote.tip] = color }
        }
        for branch in branches {
            if let color = assignments[branch.name] { colors[branch.tip] = color }
        }
        if let current, let branch = branches.first(where: { $0.name == current }), let color = assignments[current] {
            colors[branch.tip] = color
        }
        return colors
    }
}
