import Foundation

public struct Stash: Sendable, Hashable, Identifiable {
    public var index: Int
    public var oid: OID
    public var message: String
    public var branch: String?
    public var base: OID?
    public var date: Date
    public var files: [WorkingFile]?

    public var id: OID { oid }
    public var selector: String { "stash@{\(index)}" }

    public init(index: Int, oid: OID, message: String, branch: String?, base: OID?, date: Date, files: [WorkingFile]? = nil) {
        self.index = index
        self.oid = oid
        self.message = message
        self.branch = branch
        self.base = base
        self.date = date
        self.files = files
    }
}

public struct Worktree: Sendable, Hashable, Identifiable {
    public var path: String
    public var head: OID?
    public var branch: String?
    public var detachedAt: OID?
    public var isMain: Bool
    public var isBare: Bool
    public var locked: Bool
    public var lockReason: String?
    public var prunable: String?
    public var changes: Int?

    public var id: String { path }

    public init(path: String, head: OID? = nil, branch: String? = nil, detachedAt: OID? = nil, isMain: Bool = false, isBare: Bool = false, locked: Bool = false, lockReason: String? = nil, prunable: String? = nil, changes: Int? = nil) {
        self.path = path
        self.head = head
        self.branch = branch
        self.detachedAt = detachedAt
        self.isMain = isMain
        self.isBare = isBare
        self.locked = locked
        self.lockReason = lockReason
        self.prunable = prunable
        self.changes = changes
    }
}

public struct Submodule: Sendable, Hashable, Identifiable {
    public enum State: String, Sendable, Hashable {
        case clean
        case ahead
        case behind
        case modified
        case uninitialized
        case conflicted
    }

    public var path: String
    public var name: String
    public var url: String?
    public var branch: String?
    public var recorded: OID?
    public var checkedOut: OID?
    public var state: State
    public var ahead: Int
    public var describe: String?

    public var id: String { path }

    public init(path: String, name: String? = nil, url: String? = nil, branch: String? = nil, recorded: OID? = nil, checkedOut: OID? = nil, state: State, ahead: Int = 0, describe: String? = nil) {
        self.path = path
        self.name = name ?? path
        self.url = url
        self.branch = branch
        self.recorded = recorded
        self.checkedOut = checkedOut
        self.state = state
        self.ahead = ahead
        self.describe = describe
    }
}

public struct ConfigEntry: Sendable, Hashable, Identifiable {
    public enum Scope: String, Sendable, Hashable, CaseIterable {
        case system
        case global
        case local
        case worktree
        case command
        case unknown
    }

    public var scope: Scope
    public var origin: String?
    public var key: String
    public var value: String

    public var id: String { scope.rawValue + "\u{0}" + (origin ?? "") + "\u{0}" + key + "\u{0}" + value }

    public init(scope: Scope, origin: String? = nil, key: String, value: String) {
        self.scope = scope
        self.origin = origin
        self.key = key
        self.value = value
    }
}

public struct Hook: Sendable, Hashable, Identifiable {
    public var name: String
    public var path: String
    public var enabled: Bool

    public var id: String { name }

    public init(name: String, path: String, enabled: Bool) {
        self.name = name
        self.path = path
        self.enabled = enabled
    }
}
