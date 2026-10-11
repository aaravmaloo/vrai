import Foundation

public struct GitVersion: Sendable, Hashable, Comparable, CustomStringConvertible, Codable {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(parsing output: String) {
        guard let match = output.firstMatch(of: /(\d+)\.(\d+)(?:\.(\d+))?/) else { return nil }
        guard let major = Int(match.output.1), let minor = Int(match.output.2) else { return nil }
        self.init(major, minor, match.output.3.flatMap { Int($0) } ?? 0)
    }

    public static let minimum = GitVersion(2, 45, 0)

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: GitVersion, rhs: GitVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
