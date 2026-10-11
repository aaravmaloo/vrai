import Foundation
import VraiGit

extension RepositoryStore {
    @discardableResult
    public func undoLast() async throws -> UndoEntry? {
        try await perform("undo") {
            try await undo.undoLast()
        }
    }

    public func restore(_ entry: UndoEntry) async throws {
        try await perform("undo") {
            try await undo.restore(entry)
        }
    }

    public func undoHistory(limit: Int = UndoStore.historyLimit) async throws -> [UndoEntry] {
        try await undo.recent(limit: limit)
    }
}
