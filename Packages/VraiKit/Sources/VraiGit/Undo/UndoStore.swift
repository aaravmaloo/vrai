import Foundation

public actor UndoStore {
    public let git: GitProcess
    public private(set) var entries: [UndoEntry] = []

    public init(git: GitProcess) {
        self.git = git
    }

    public func record(_ entry: UndoEntry) async throws {
        entries.insert(entry, at: 0)
    }
}
