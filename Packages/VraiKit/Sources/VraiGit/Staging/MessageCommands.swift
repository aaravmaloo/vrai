import Foundation

public struct MergeHead: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case branch
        case remoteBranch
        case tag
        case commit
    }

    public var oid: OID
    public var name: String
    public var kind: Kind

    public init(oid: OID, name: String, kind: Kind) {
        self.oid = oid
        self.name = name
        self.kind = kind
    }

    public var line: String {
        let quoted = "'" + name + "'"
        switch kind {
        case .branch: return oid.rawValue + "\t\tbranch " + quoted + " of .\n"
        case .remoteBranch: return oid.rawValue + "\t\tremote-tracking branch " + quoted + " of .\n"
        case .tag: return oid.rawValue + "\t\ttag " + quoted + " of .\n"
        case .commit: return oid.rawValue + "\t\tcommit " + quoted + "\n"
        }
    }
}

public struct Trailer: Sendable, Hashable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }

    public static func coAuthor(name: String, email: String) -> Trailer {
        Trailer(key: "Co-authored-by", value: email.isEmpty ? name : name + " <" + email + ">")
    }

    public var text: String { key + ": " + value }
}

public enum MessageCommands {
    public static func mergeMessage(_ heads: [MergeHead]) -> GitCommand {
        GitCommand(["fmt-merge-msg"], stdin: Data(heads.map(\.line).joined().utf8))
    }

    public static func cleanup(_ text: String, stripComments: Bool = true) -> GitCommand {
        GitCommand(["stripspace"] + (stripComments ? ["--strip-comments"] : []), stdin: Data(text.utf8))
    }

    public static func addTrailers(_ trailers: [Trailer], to text: String) -> GitCommand {
        var arguments = ["interpret-trailers", "--if-exists", "addIfDifferent"]
        for trailer in trailers { arguments += ["--trailer", trailer.text] }
        return GitCommand(arguments, stdin: Data(text.utf8))
    }
}
