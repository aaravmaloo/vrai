import Observation
import SwiftUI
import VraiCore
import VraiGit

@MainActor
@Observable
final class PaletteSearch {
    var recent: [String] = []
    var files: [String] = []
    var commits: [Commit] = []
    var commitQuery = ""
    var code: [GrepMatch] = []
    var codeQuery = ""
    var searching = false
    @ObservationIgnored private var task: Task<Void, Never>?

    static let debounce: Duration = .milliseconds(180)
    static let codeMinimum = 3

    func start(window: WindowModel) async {
        let store = window.store
        recent = await store.recentBranches()
        let key = Self.fileKey(store.snapshot)
        if let cached = window.palette.cachedFiles, window.palette.cachedFilesKey == key {
            files = cached
            return
        }
        guard let loaded = try? await store.trackedFiles() else { return }
        files = loaded
        window.palette.cachedFiles = loaded
        window.palette.cachedFilesKey = key
    }

    static func fileKey(_ snapshot: RepositorySnapshot?) -> String {
        guard let snapshot else { return "" }
        return (snapshot.headOID?.rawValue ?? "unborn") + ":" + String(snapshot.working.count)
    }

    func update(_ query: String, store: RepositoryStore) {
        task?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, !q.hasPrefix("git"), store.snapshot != nil else {
            commits = []
            commitQuery = ""
            code = []
            codeQuery = ""
            searching = false
            return
        }
        searching = true
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            async let foundCommits = try? store.searchCommits(q, limit: 20)
            async let foundCode = q.count >= Self.codeMinimum ? ((try? await store.grep(text: q, limit: 40)) ?? []) : []
            let commits = await foundCommits ?? []
            let code = await foundCode
            guard !Task.isCancelled, let self else { return }
            self.commits = commits
            self.commitQuery = q
            self.code = code
            self.codeQuery = q
            self.searching = false
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
