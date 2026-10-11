import Foundation

public enum FileStatus: String, Sendable, Hashable, Codable {
    case added
    case modified
    case deleted
    case renamed
    case copied
    case untracked
    case conflicted
    case typeChanged

    public init?(letter: Character) {
        switch letter {
        case "A": self = .added
        case "M": self = .modified
        case "D": self = .deleted
        case "R": self = .renamed
        case "C": self = .copied
        case "T": self = .typeChanged
        case "U": self = .conflicted
        case "?": self = .untracked
        default: return nil
        }
    }

    public var letter: String {
        switch self {
        case .added: "A"
        case .modified: "M"
        case .deleted: "D"
        case .renamed: "R"
        case .copied: "C"
        case .untracked: "?"
        case .conflicted: "U"
        case .typeChanged: "T"
        }
    }
}

public enum StageState: String, Sendable, Hashable, Codable {
    case none
    case partial
    case full
}

public struct WorkingFile: Sendable, Hashable, Identifiable {
    public var path: String
    public var oldPath: String?
    public var status: FileStatus
    public var staged: StageState
    public var indexStatus: FileStatus?
    public var worktreeStatus: FileStatus?
    public var additions: Int
    public var deletions: Int
    public var isBinary: Bool
    public var isLFS: Bool
    public var isSubmodule: Bool

    public var id: String { path }

    public init(path: String, oldPath: String? = nil, status: FileStatus, staged: StageState, indexStatus: FileStatus? = nil, worktreeStatus: FileStatus? = nil, additions: Int = 0, deletions: Int = 0, isBinary: Bool = false, isLFS: Bool = false, isSubmodule: Bool = false) {
        self.path = path
        self.oldPath = oldPath
        self.status = status
        self.staged = staged
        self.indexStatus = indexStatus
        self.worktreeStatus = worktreeStatus
        self.additions = additions
        self.deletions = deletions
        self.isBinary = isBinary
        self.isLFS = isLFS
        self.isSubmodule = isSubmodule
    }
}
