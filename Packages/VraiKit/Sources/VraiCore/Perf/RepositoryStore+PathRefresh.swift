import Foundation
import VraiGit

extension RepositoryStore {
    func refreshingPaths(_ paths: [String], _ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch {
            try? await refresh()
            throw error
        }
        try await refreshPaths(paths)
    }

    func refreshPaths(_ paths: [String]) async throws {
        guard let current = snapshot, let root = current.root, !current.isBare, current.headOID != nil, current.conflicts.isEmpty, !paths.isEmpty, !Self.mayPairRenames(current.working) else {
            try await refresh()
            return
        }
        let scope = Set(paths)
        guard !current.working.contains(where: { scope.contains($0.path) && $0.isSubmodule }) else {
            try await refresh()
            return
        }
        let pathspec = scope.sorted()
        let statusCommand = Self.limited(StatusParser.command(renameThreshold: renameThreshold), to: pathspec)
        let numstatCommand = Self.limited(SnapshotBuilder.numstatHead(renameThreshold: renameThreshold), to: pathspec)
        async let statusData = git.run(statusCommand, background: true).stdout
        async let numstatResult = git.runAllowingFailure(numstatCommand, background: true)
        let report = StatusParser.parse(try await statusData)
        let numstat = try await numstatResult
        guard numstat.succeeded, report.conflicts.isEmpty, report.head == current.head, report.oid == current.headOID,
              !report.files.contains(where: { $0.oldPath != nil || $0.isSubmodule || !scope.contains($0.path) }),
              let latest = snapshot, latest.working == current.working else {
            try await refresh()
            return
        }
        let counts = SnapshotBuilder.parseNumstat(numstat.stdout)
        var fresh: [String: WorkingFile] = [:]
        var order: [String] = []
        for var file in report.files {
            if let count = counts[file.path] {
                file.additions = count.additions
                file.deletions = count.deletions
                file.isBinary = count.binary
            } else if file.status == .untracked {
                let lines = SnapshotBuilder.lineCount(root.appending(path: file.path))
                file.additions = lines.count
                file.isBinary = lines.binary
            }
            fresh[file.path] = file
            order.append(file.path)
        }
        var working: [WorkingFile] = []
        for file in latest.working {
            guard scope.contains(file.path) else {
                working.append(file)
                continue
            }
            if let replacement = fresh.removeValue(forKey: file.path) { working.append(replacement) }
        }
        working += order.compactMap { fresh[$0] }
        working = working.filter { $0.status != .untracked }.sorted(by: Self.gitOrder) + working.filter { $0.status == .untracked }.sorted(by: Self.gitOrder)
        guard working.isEmpty == latest.working.isEmpty else {
            try await refresh()
            return
        }
        var next = latest
        next.working = working
        next.worktrees = latest.worktrees.map { worktree in
            var worktree = worktree
            if worktree.isMain { worktree.changes = working.count }
            return worktree
        }
        snapshot = next
        refreshWipSelection()
    }

    static func limited(_ command: GitCommand, to paths: [String]) -> GitCommand {
        var limited = GitCommand.read(command.arguments + ["--"] + paths, acceptedExitCodes: command.acceptedExitCodes)
        limited.environment = command.environment.merging(["GIT_LITERAL_PATHSPECS": "1"]) { _, literal in literal }
        return limited
    }

    static func gitOrder(_ a: WorkingFile, _ b: WorkingFile) -> Bool {
        a.path.utf8.lexicographicallyPrecedes(b.path.utf8)
    }

    static func mayPairRenames(_ working: [WorkingFile]) -> Bool {
        working.contains { $0.oldPath != nil || $0.status == .deleted || $0.indexStatus == .deleted || $0.worktreeStatus == .deleted }
    }
}
