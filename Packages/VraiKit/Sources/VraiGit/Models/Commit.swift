import Foundation

public struct Commit: Sendable, Hashable, Identifiable {
    public var id: OID
    public var parents: [OID]
    public var authorName: String
    public var authorEmail: String
    public var authorDate: Date
    public var committerName: String
    public var committerEmail: String
    public var committerDate: Date
    public var subject: String
    public var body: String?
    public var signature: SignatureState
    public var refs: [RefLabel]

    public init(id: OID, parents: [OID], authorName: String, authorEmail: String, authorDate: Date, committerName: String, committerEmail: String, committerDate: Date, subject: String, body: String? = nil, signature: SignatureState = .unchecked, refs: [RefLabel] = []) {
        self.id = id
        self.parents = parents
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.authorDate = authorDate
        self.committerName = committerName
        self.committerEmail = committerEmail
        self.committerDate = committerDate
        self.subject = subject
        self.body = body
        self.signature = signature
        self.refs = refs
    }

    public var isMerge: Bool { parents.count > 1 }
}

public struct CommitDetail: Sendable, Hashable {
    public var commit: Commit
    public var signer: String?
    public var signingKey: String?
    public var files: [ChangedFile]

    public init(commit: Commit, signer: String? = nil, signingKey: String? = nil, files: [ChangedFile] = []) {
        self.commit = commit
        self.signer = signer
        self.signingKey = signingKey
        self.files = files
    }
}

public struct ChangedFile: Sendable, Hashable, Identifiable {
    public var path: String
    public var oldPath: String?
    public var status: FileStatus
    public var additions: Int
    public var deletions: Int
    public var isBinary: Bool

    public var id: String { path }

    public init(path: String, oldPath: String? = nil, status: FileStatus, additions: Int = 0, deletions: Int = 0, isBinary: Bool = false) {
        self.path = path
        self.oldPath = oldPath
        self.status = status
        self.additions = additions
        self.deletions = deletions
        self.isBinary = isBinary
    }
}

public struct ReflogEntry: Sendable, Hashable, Identifiable {
    public var id: OID
    public var selector: String
    public var message: String
    public var date: Date

    public init(id: OID, selector: String, message: String, date: Date) {
        self.id = id
        self.selector = selector
        self.message = message
        self.date = date
    }
}

public struct BlameLine: Sendable, Hashable, Identifiable {
    public var number: Int
    public var text: String
    public var commit: OID
    public var originalNumber: Int
    public var path: String
    public var authorName: String
    public var authorEmail: String
    public var authorDate: Date
    public var summary: String
    public var previous: OID?
    public var previousPath: String?
    public var isBoundary: Bool

    public var id: Int { number }

    public init(number: Int, text: String, commit: OID, originalNumber: Int, path: String, authorName: String, authorEmail: String, authorDate: Date, summary: String, previous: OID? = nil, previousPath: String? = nil, isBoundary: Bool = false) {
        self.number = number
        self.text = text
        self.commit = commit
        self.originalNumber = originalNumber
        self.path = path
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.authorDate = authorDate
        self.summary = summary
        self.previous = previous
        self.previousPath = previousPath
        self.isBoundary = isBoundary
    }
}
