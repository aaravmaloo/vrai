import Foundation
import Observation
import VraiGit

@MainActor
@Observable
public final class RepositoryStore {
    public let git: GitProcess
    public let undo: UndoStore
    public internal(set) var snapshot: RepositorySnapshot?
    public private(set) var busy: Set<String> = []
    public var branchColors: BranchColors

    public init(git: GitProcess, colors: BranchColors = BranchColors()) {
        self.git = git
        self.undo = UndoStore(git: git)
        self.branchColors = colors
    }

    public func refresh() async throws {
        let built = try await SnapshotBuilder(git: git).build(colors: branchColors, network: snapshot?.network ?? .unknown)
        snapshot = built
        branchColors = built.branchColors
    }

    public func perform<T: Sendable>(_ action: String, refresh shouldRefresh: Bool = true, _ body: () async throws -> T) async throws -> T {
        busy.insert(action)
        defer { busy.remove(action) }
        do {
            let value = try await body()
            if shouldRefresh { try await refresh() }
            return value
        } catch {
            if shouldRefresh { try? await refresh() }
            throw error
        }
    }
}
