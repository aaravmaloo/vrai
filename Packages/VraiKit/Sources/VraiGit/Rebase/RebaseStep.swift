import Foundation

public struct RebaseStep: Sendable, Hashable, Codable, Identifiable {
    public enum Action: String, Sendable, Hashable, Codable, CaseIterable {
        case pick
        case reword
        case edit
        case squash
        case fixup
        case drop

        public var key: Character {
            switch self {
            case .pick: "p"
            case .reword: "r"
            case .edit: "e"
            case .squash: "s"
            case .fixup: "f"
            case .drop: "d"
            }
        }

        public init?(key: Character) {
            guard let action = Action.allCases.first(where: { $0.key == Character(key.lowercased()) }) else { return nil }
            self = action
        }

        public var foldsIntoPrevious: Bool { self == .squash || self == .fixup }
    }

    public var commit: OID
    public var action: Action
    public var subject: String
    public var author: String?
    public var message: String?

    public var id: OID { commit }

    public init(commit: OID, action: Action = .pick, subject: String, author: String? = nil, message: String? = nil) {
        self.commit = commit
        self.action = action
        self.subject = subject
        self.author = author
        self.message = message
    }
}
