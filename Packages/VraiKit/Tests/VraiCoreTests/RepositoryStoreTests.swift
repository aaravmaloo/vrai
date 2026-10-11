import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct RepositoryStoreTests {
    @Test func refreshLoadsTheSnapshot() async throws {
        let store = RepositoryStore(git: try Sandbox.git("everyday/vrai"))
        try await store.refresh()
        #expect(store.snapshot?.head == .branch("feature/graph-renderer"))
        #expect(store.branchColors.color(for: "main") == 0)
    }

    @Test func performRefreshesAfterFailureAndClearsBusy() async throws {
        let store = RepositoryStore(git: try Sandbox.git("everyday/vrai"))
        await #expect(throws: GitError.self) {
            try await store.perform("probe") {
                try await store.git.run(.read(["rev-parse", "--verify", "no-such-ref"]))
            }
        }
        #expect(store.snapshot != nil)
        #expect(store.busy.isEmpty)
    }

    @Test func undoEntriesRoundTripThroughJSON() throws {
        let entry = UndoEntry(kind: .branchDelete, label: "Delete branch fix/rebase-banner", refsBefore: ["refs/heads/fix/rebase-banner": OID(String(repeating: "a", count: 40))!])
        let decoded = try JSONDecoder().decode(UndoEntry.self, from: JSONEncoder().encode(entry))
        #expect(decoded == entry)
        #expect(decoded.kind == .branchDelete)
    }
}
