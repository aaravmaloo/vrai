import SwiftUI
import VraiCore
import VraiGit

@MainActor
enum BisectMarks {
    static func skipped(_ store: RepositoryStore) async -> [OID] {
        guard case .bisecting? = store.snapshot?.state else { return [] }
        return await store.bisectSkipped()
    }
}
