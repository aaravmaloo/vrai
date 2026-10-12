import Foundation

public struct RepositoryLayout: Codable, Equatable, Sendable {
    public var sections: [String: Bool]
    public var folders: [String: Bool]
    public var view: RepositoryView?

    public init(sections: [String: Bool] = [:], folders: [String: Bool] = [:], view: RepositoryView? = nil) {
        self.sections = sections
        self.folders = folders
        self.view = view
    }

    public static let restorable: Set<RepositoryView> = [.history, .changes, .stashes]
}

extension RepositoryView: Codable {}
