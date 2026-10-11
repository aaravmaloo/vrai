import Foundation

public struct PathParts: Sendable, Hashable {
    public var directory: String
    public var name: String

    public init(directory: String, name: String) {
        self.directory = directory
        self.name = name
    }

    public static func split(_ path: String) -> PathParts {
        guard let slash = path.lastIndex(of: "/") else { return PathParts(directory: "", name: path) }
        return PathParts(directory: String(path[...slash]), name: String(path[path.index(after: slash)...]))
    }
}
