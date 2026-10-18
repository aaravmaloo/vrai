import Foundation

public struct VraiNotification: Sendable, Hashable {
    public enum Category: String, Sendable, CaseIterable {
        case sync
        case needsYou
        case history
        case fetch
        case checks
        case maintenance
    }

    public enum Level: String, Sendable {
        case quiet
        case alert
    }

    public struct Button: Sendable, Hashable {
        public var id: String
        public var title: String
        public var opensApp: Bool
        public var destructive: Bool

        public init(id: String, title: String, opensApp: Bool = true, destructive: Bool = false) {
            self.id = id
            self.title = title
            self.opensApp = opensApp
            self.destructive = destructive
        }
    }

    public enum Target: Sendable, Hashable {
        case history
        case changes
        case conflicts
        case console
        case ref(String)
        case commit(String)

        public var link: String {
            switch self {
            case .history: "history"
            case .changes: "changes"
            case .conflicts: "conflicts"
            case .console: "console"
            case .ref(let name): "ref:" + name
            case .commit(let sha): "commit:" + sha
            }
        }

        public init?(link: String) {
            switch link {
            case "history": self = .history
            case "changes": self = .changes
            case "conflicts": self = .conflicts
            case "console": self = .console
            default:
                if link.hasPrefix("ref:") {
                    self = .ref(String(link.dropFirst(4)))
                } else if link.hasPrefix("commit:") {
                    self = .commit(String(link.dropFirst(7)))
                } else {
                    return nil
                }
            }
        }
    }

    public var id: String
    public var category: Category
    public var repository: String
    public var title: String
    public var body: String
    public var level: Level
    public var sound = false
    public var target: Target?
    public var buttons: [Button]
    public var newCommits: [String: Int]

    public init(id: String? = nil, category: Category, repository: String, title: String, body: String, level: Level = .quiet, target: Target? = nil, buttons: [Button] = [], newCommits: [String: Int] = [:]) {
        self.id = id ?? category.rawValue + ":" + repository + ":" + UUID().uuidString
        self.category = category
        self.repository = repository
        self.title = title
        self.body = body
        self.level = level
        self.target = target
        self.buttons = buttons
        self.newCommits = newCommits
    }

    public static func lines(for newCommits: [String: Int]) -> [String] {
        newCommits.filter { $0.value > 0 }.sorted { $0.key < $1.key }.map { ref, count in
            String(localized: "\(n(count, "new commit")) on \(ref)", bundle: .module)
        }
    }

    public static func fetched(repository: String, name: String, newCommits: [String: Int]) -> VraiNotification {
        let first = newCommits.filter { $0.value > 0 }.keys.sorted().first
        return VraiNotification(
            id: "fetch:" + repository,
            category: .fetch,
            repository: repository,
            title: name,
            body: lines(for: newCommits).joined(separator: "\n"),
            target: first.map(Target.ref) ?? .history,
            newCommits: newCommits
        )
    }
}

extension VraiNotification {
    public static func upstreamChanged(repository: String, name: String, rewritten: [String], gone: [String]) -> VraiNotification {
        let lines = rewritten.sorted().map { String(localized: "\($0) was force-pushed", bundle: .module) }
            + gone.sorted().map { String(localized: "\($0) was deleted on the remote", bundle: .module) }
        return VraiNotification(
            id: "upstream:" + repository,
            category: .fetch,
            repository: repository,
            title: name,
            body: lines.joined(separator: "\n"),
            level: .alert,
            target: rewritten.sorted().first.map(Target.ref) ?? .history
        )
    }

    public var isUpstreamChange: Bool { id.hasPrefix("upstream:") }
}

public protocol Notifier: Sendable {
    func post(_ notification: VraiNotification) async
    func remove(_ ids: [String]) async
}

extension Notifier {
    public func remove(_ ids: [String]) async {}
}

public struct ClosureNotifier: Notifier {
    let handler: @Sendable (VraiNotification) async -> Void
    let removal: @Sendable ([String]) async -> Void

    public init(_ handler: @escaping @Sendable (VraiNotification) async -> Void, removal: @escaping @Sendable ([String]) async -> Void = { _ in }) {
        self.handler = handler
        self.removal = removal
    }

    public func post(_ notification: VraiNotification) async {
        await handler(notification)
    }

    public func remove(_ ids: [String]) async {
        await removal(ids)
    }
}
