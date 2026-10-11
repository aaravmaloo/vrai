import Foundation

public enum Head: Sendable, Hashable {
    case branch(String)
    case detached(OID)
    case unborn(String)

    public var branchName: String? {
        switch self {
        case .branch(let name), .unborn(let name): name
        case .detached: nil
        }
    }
}

public enum SignatureState: String, Sendable, Hashable, Codable {
    case verified
    case unknownKey
    case bad
    case unsigned
    case unchecked

    public init(gitCode: String) {
        switch gitCode {
        case "G": self = .verified
        case "U", "X", "Y", "E": self = .unknownKey
        case "B", "R": self = .bad
        default: self = .unsigned
        }
    }
}

public struct Branch: Sendable, Hashable, Identifiable {
    public var name: String
    public var tip: OID
    public var upstream: String?
    public var ahead: Int
    public var behind: Int
    public var upstreamGone: Bool
    public var colorIndex: Int
    public var isCurrent: Bool
    public var worktreePath: String?

    public var id: String { name }

    public init(name: String, tip: OID, upstream: String? = nil, ahead: Int = 0, behind: Int = 0, upstreamGone: Bool = false, colorIndex: Int = 0, isCurrent: Bool = false, worktreePath: String? = nil) {
        self.name = name
        self.tip = tip
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.upstreamGone = upstreamGone
        self.colorIndex = colorIndex
        self.isCurrent = isCurrent
        self.worktreePath = worktreePath
    }
}

public struct RemoteBranch: Sendable, Hashable, Identifiable {
    public var remote: String
    public var name: String
    public var tip: OID
    public var colorIndex: Int

    public var id: String { remote + "/" + name }
    public var fullName: String { remote + "/" + name }

    public init(remote: String, name: String, tip: OID, colorIndex: Int = 0) {
        self.remote = remote
        self.name = name
        self.tip = tip
        self.colorIndex = colorIndex
    }
}

public struct Remote: Sendable, Hashable, Identifiable {
    public var name: String
    public var fetchURL: String
    public var pushURL: String?
    public var headBranch: String?
    public var prune: Bool

    public var id: String { name }

    public init(name: String, fetchURL: String, pushURL: String? = nil, headBranch: String? = nil, prune: Bool = false) {
        self.name = name
        self.fetchURL = fetchURL
        self.pushURL = pushURL
        self.headBranch = headBranch
        self.prune = prune
    }
}

public struct Tag: Sendable, Hashable, Identifiable {
    public var name: String
    public var target: OID
    public var annotated: Bool
    public var tagger: String?
    public var date: Date?
    public var message: String?
    public var signature: SignatureState

    public var id: String { name }

    public init(name: String, target: OID, annotated: Bool, tagger: String? = nil, date: Date? = nil, message: String? = nil, signature: SignatureState = .unsigned) {
        self.name = name
        self.target = target
        self.annotated = annotated
        self.tagger = tagger
        self.date = date
        self.message = message
        self.signature = signature
    }
}

public struct RefLabel: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case head
        case branch
        case remoteBranch
        case tag
        case other
    }

    public var kind: Kind
    public var name: String
    public var fullName: String
    public var isHead: Bool

    public init(kind: Kind, name: String, fullName: String, isHead: Bool = false) {
        self.kind = kind
        self.name = name
        self.fullName = fullName
        self.isHead = isHead
    }

    public init(fullName: String, isHead: Bool = false) {
        self.fullName = fullName
        self.isHead = isHead
        if fullName == "HEAD" {
            kind = .head
            name = "HEAD"
        } else if fullName.hasPrefix("refs/heads/") {
            kind = .branch
            name = String(fullName.dropFirst("refs/heads/".count))
        } else if fullName.hasPrefix("refs/remotes/") {
            kind = .remoteBranch
            name = String(fullName.dropFirst("refs/remotes/".count))
        } else if fullName.hasPrefix("refs/tags/") {
            kind = .tag
            name = String(fullName.dropFirst("refs/tags/".count))
        } else {
            kind = .other
            name = fullName
        }
    }
}
