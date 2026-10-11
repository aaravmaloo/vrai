import Foundation

public struct UndoEntry: Sendable, Hashable, Codable, Identifiable {
    public struct Kind: RawRepresentable, Sendable, Hashable, Codable {
        public var rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static let commit = Kind(rawValue: "commit")
        public static let amend = Kind(rawValue: "amend")
        public static let merge = Kind(rawValue: "merge")
        public static let pull = Kind(rawValue: "pull")
        public static let rebase = Kind(rawValue: "rebase")
        public static let reset = Kind(rawValue: "reset")
        public static let resetHard = Kind(rawValue: "resetHard")
        public static let cherryPick = Kind(rawValue: "cherryPick")
        public static let revert = Kind(rawValue: "revert")
        public static let discardFile = Kind(rawValue: "discardFile")
        public static let discardLines = Kind(rawValue: "discardLines")
        public static let restoreFile = Kind(rawValue: "restoreFile")
        public static let branchDelete = Kind(rawValue: "branchDelete")
        public static let tagDelete = Kind(rawValue: "tagDelete")
        public static let stashDrop = Kind(rawValue: "stashDrop")
    }

    public var id: UUID
    public var kind: Kind
    public var label: String
    public var detail: String?
    public var date: Date
    public var head: String?
    public var refsBefore: [String: OID]
    public var objects: [OID]
    public var files: [String: OID]
    public var stashCommit: OID?
    public var patch: OID?
    public var message: String?
    public var refsAfter: [String: OID]?
    public var filesAfter: [String: OID]?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        label: String,
        detail: String? = nil,
        date: Date = Date(),
        head: String? = nil,
        refsBefore: [String: OID] = [:],
        objects: [OID] = [],
        files: [String: OID] = [:],
        stashCommit: OID? = nil,
        patch: OID? = nil,
        message: String? = nil,
        refsAfter: [String: OID]? = nil,
        filesAfter: [String: OID]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.detail = detail
        self.date = date
        self.head = head
        self.refsBefore = refsBefore
        self.objects = objects
        self.files = files
        self.stashCommit = stashCommit
        self.patch = patch
        self.message = message
        self.refsAfter = refsAfter
        self.filesAfter = filesAfter
    }
}
