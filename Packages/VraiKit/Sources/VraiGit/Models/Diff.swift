import Foundation

public struct DiffLine: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case context
        case add
        case del
        case noNewline
    }

    public var kind: Kind
    public var text: String
    public var oldNumber: Int?
    public var newNumber: Int?
    public var wordRanges: [Range<Int>]
    public var staged: Bool?

    public init(kind: Kind, text: String, oldNumber: Int? = nil, newNumber: Int? = nil, wordRanges: [Range<Int>] = [], staged: Bool? = nil) {
        self.kind = kind
        self.text = text
        self.oldNumber = oldNumber
        self.newNumber = newNumber
        self.wordRanges = wordRanges
        self.staged = staged
    }
}

public struct Hunk: Sendable, Hashable {
    public var header: String
    public var oldStart: Int
    public var oldCount: Int
    public var newStart: Int
    public var newCount: Int
    public var title: String
    public var lines: [DiffLine]

    public init(header: String, oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, title: String, lines: [DiffLine]) {
        self.header = header
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.title = title
        self.lines = lines
    }

    public var additions: Int { lines.count { $0.kind == .add } }
    public var deletions: Int { lines.count { $0.kind == .del } }
}

public struct FileDiff: Sendable, Hashable, Identifiable {
    public var path: String
    public var oldPath: String?
    public var status: FileStatus
    public var oldMode: String?
    public var newMode: String?
    public var similarity: Int?
    public var isBinary: Bool
    public var isSubmodule: Bool
    public var hunks: [Hunk]

    public var id: String { path }

    public init(path: String, oldPath: String? = nil, status: FileStatus, oldMode: String? = nil, newMode: String? = nil, similarity: Int? = nil, isBinary: Bool = false, isSubmodule: Bool = false, hunks: [Hunk] = []) {
        self.path = path
        self.oldPath = oldPath
        self.status = status
        self.oldMode = oldMode
        self.newMode = newMode
        self.similarity = similarity
        self.isBinary = isBinary
        self.isSubmodule = isSubmodule
        self.hunks = hunks
    }

    public var additions: Int { hunks.reduce(0) { $0 + $1.additions } }
    public var deletions: Int { hunks.reduce(0) { $0 + $1.deletions } }
}

public struct ConflictFile: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case bothModified
        case bothAdded
        case bothDeleted
        case addedByUs
        case addedByThem
        case deletedByUs
        case deletedByThem

        public init?(xy: String) {
            switch xy {
            case "UU": self = .bothModified
            case "AA": self = .bothAdded
            case "DD": self = .bothDeleted
            case "AU": self = .addedByUs
            case "UA": self = .addedByThem
            case "DU": self = .deletedByUs
            case "UD": self = .deletedByThem
            default: return nil
            }
        }
    }

    public var path: String
    public var kind: Kind
    public var blocks: [ConflictBlock]

    public var id: String { path }

    public init(path: String, kind: Kind, blocks: [ConflictBlock] = []) {
        self.path = path
        self.kind = kind
        self.blocks = blocks
    }
}

public enum ConflictBlock: Sendable, Hashable {
    case context(lines: [String], range: Range<Int>)
    case conflict(Conflict)

    public struct Conflict: Sendable, Hashable {
        public var index: Int
        public var oursLabel: String
        public var ours: [String]
        public var baseLabel: String?
        public var base: [String]?
        public var theirsLabel: String
        public var theirs: [String]
        public var range: Range<Int>

        public init(index: Int, oursLabel: String, ours: [String], baseLabel: String? = nil, base: [String]? = nil, theirsLabel: String, theirs: [String], range: Range<Int>) {
            self.index = index
            self.oursLabel = oursLabel
            self.ours = ours
            self.baseLabel = baseLabel
            self.base = base
            self.theirsLabel = theirsLabel
            self.theirs = theirs
            self.range = range
        }
    }
}
