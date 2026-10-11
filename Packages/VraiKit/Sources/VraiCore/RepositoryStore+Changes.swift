import Foundation
import VraiGit

extension RepositoryStore {
    private var staging: StagingService { StagingService(git: git) }

    public func stage(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await perform("stage") {
            _ = try await git.run(StagingService.stageCommand(paths: paths))
        }
    }

    public func unstage(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        var expanded = paths
        for path in paths {
            if let old = snapshot?.working.first(where: { $0.path == path })?.oldPath, !expanded.contains(old) { expanded.append(old) }
        }
        try await perform("unstage") {
            let unborn = try await staging.isUnborn()
            _ = try await git.run(StagingService.unstageCommand(paths: expanded, unborn: unborn))
        }
    }

    public func stageAll(includeUntracked: Bool) async throws {
        try await perform("stage") {
            _ = try await git.run(StagingService.stageAllCommand(includeUntracked: includeUntracked))
        }
    }

    public func unstageAll() async throws {
        try await perform("unstage") {
            let unborn = try await staging.isUnborn()
            _ = try await git.run(StagingService.unstageAllCommand(unborn: unborn))
        }
    }

    public func stage(lines selection: LineSelection) async throws {
        guard let command = try StagingService.lineCommand(selection, action: .stage) else { return }
        try await perform("stage") {
            _ = try await git.run(command)
        }
    }

    public func unstage(lines selection: LineSelection) async throws {
        guard let command = try StagingService.lineCommand(selection, action: .unstage) else { return }
        try await perform("unstage") {
            _ = try await git.run(command)
        }
    }

    public func discard(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        let label = paths.count == 1
            ? String(localized: "Discarded changes to \(PathParts.split(paths[0]).name)", bundle: .module)
            : String(localized: "Discarded changes to \(n(paths.count, "file"))", bundle: .module)
        let detail = String(localized: "A copy stays in Undo history for 14 days", bundle: .module)
        try await perform("discard") {
            let tracked = try await staging.trackedPaths(paths)
            let kept = paths.filter { tracked.contains($0) }
            let untracked = paths.filter { !tracked.contains($0) }
            let files = try await undo.snapshotFiles(paths)
            let entry = UndoEntry(kind: .discardFile, label: label, detail: detail, files: files)
            try await undo.record(entry)
            do {
                if !kept.isEmpty { try await git.run(StagingService.discardTrackedCommand(paths: kept)) }
                if !untracked.isEmpty { try await git.run(StagingService.cleanCommand(paths: untracked)) }
            } catch {
                try? await undo.complete(entry.id)
                throw error
            }
            try await undo.complete(entry.id)
        }
    }

    public func discard(lines selection: LineSelection) async throws {
        guard let command = try StagingService.lineCommand(selection, action: .discard), let patch = command.stdin else { return }
        let name = PathParts.split(selection.path).name
        let label = String(localized: "Discarded \(n(selection.count, "line")) in \(name)", bundle: .module)
        let detail = String(localized: "A copy stays in Undo history for 14 days", bundle: .module)
        try await perform("discard") {
            let blob = try await undo.storeBlob(patch)
            let entry = UndoEntry(kind: .discardLines, label: label, detail: detail, patch: blob)
            try await undo.record(entry)
            do {
                try await git.run(command)
            } catch {
                try? await undo.forget(entry.id)
                throw error
            }
            try await undo.complete(entry.id)
        }
    }

    @discardableResult
    public func commit(subject: String, body: String = "", amend: Bool = false, signoff: Bool = false, noVerify: Bool = false, andPush: Bool = false) async throws -> OID {
        let message = CommitMessage(subject: subject, body: body)
        guard !message.isEmpty else { throw GitError(.emptyMessage) }
        let service = CommitService(git: git)
        let state = snapshot?.state
        let tip = try await perform("commit") {
            let head = try await service.headState()
            let entry = UndoEntry(
                kind: amend ? .amend : (head.merging ? .merge : .commit),
                label: Self.commitLabel(subject: message.subject, amend: amend, merging: head.merging, state: state, head: head),
                detail: Self.commitDetail(amend: amend, head: head),
                head: head.undoHead,
                refsBefore: head.undoRefs
            )
            try await undo.record(entry)
            do {
                let tip = try await service.commit(message, amend: amend, signoff: signoff, noVerify: noVerify)
                try? await undo.complete(entry.id)
                return tip
            } catch {
                try? await undo.forget(entry.id)
                throw error
            }
        }
        if andPush { try await push() }
        return tip
    }

    public func lastCommitMessage() async throws -> CommitMessage? {
        try await CommitService(git: git).lastMessage()
    }

    public func restoreFile(path: String, from revision: String) async throws {
        let detail = String(localized: "Your earlier version stays in Undo history for 14 days", bundle: .module)
        try await perform("restore") {
            let source = try await git.run(.read(["rev-parse", "--verify", revision + "^{commit}"]), background: true).output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let commit = OID(source) else { throw GitError(.refNotFound) }
            let label = String(localized: "Restored \(PathParts.split(path).name) from \(commit.short)", bundle: .module)
            let files = try await undo.snapshotFiles([path])
            let entry = UndoEntry(kind: .restoreFile, label: label, detail: detail, objects: [commit], files: files)
            try await undo.record(entry)
            do {
                try await git.run(StagingService.restoreCommand(path: path, source: commit.rawValue))
            } catch {
                try? await undo.forget(entry.id)
                throw error
            }
            try await undo.complete(entry.id)
        }
    }

    public func restoreFile(path: String, from commit: OID) async throws {
        try await restoreFile(path: path, from: commit.rawValue)
    }

    public func workingDiff(path: String, staged: Bool) async throws -> FileDiff? {
        let file = snapshot?.working.first { $0.path == path }
        let untracked: Bool
        if staged {
            untracked = false
        } else if let file {
            untracked = file.status == .untracked
        } else {
            untracked = try await staging.trackedPaths([path]).isEmpty
        }
        return try await staging.diff(path: path, oldPath: staged ? file?.oldPath : nil, staged: staged, untracked: untracked, renameThreshold: renameThreshold)
    }

    private static func quoted(_ subject: String) -> String {
        let text = subject.count > 44 ? String(subject.prefix(43)) + "\u{2026}" : subject
        return "\u{201C}" + text + "\u{201D}"
    }

    private static func commitLabel(subject: String, amend: Bool, merging: Bool, state: RepoState?, head: CommitService.HeadState) -> String {
        if amend { return String(localized: "Amended \(quoted(subject))", bundle: .module) }
        if merging, case .merging(let source?) = state {
            return String(localized: "Merged \(source) into \(headName(head))", bundle: .module)
        }
        return String(localized: "Committed \(quoted(subject))", bundle: .module)
    }

    private static func commitDetail(amend: Bool, head: CommitService.HeadState) -> String {
        if amend, let tip = head.tip { return String(localized: "The previous version is \(tip.short)", bundle: .module) }
        return String(localized: "On \(headName(head))", bundle: .module)
    }

    private static func headName(_ head: CommitService.HeadState) -> String {
        if let ref = head.ref { return ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref }
        return head.tip?.short ?? "HEAD"
    }
}
