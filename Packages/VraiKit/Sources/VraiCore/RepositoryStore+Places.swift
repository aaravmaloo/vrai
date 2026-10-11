import Foundation
import VraiGit

extension RepositoryStore {
    public func reflog(ref: String = "HEAD", limit: Int = 500) async throws -> [ReflogEntry] {
        ReflogParser.parse(try await git.run(PlacesCommands.reflog(ref: ref, limit: limit), background: true).stdout)
    }

    public func allRefs() async throws -> [RefEntry] {
        let git = self.git
        async let listed = git.run(PlacesCommands.refs, background: true).stdout
        async let symbolic = git.run(PlacesCommands.symbolicHead, background: true)
        async let head = git.run(PlacesCommands.pseudoRef("HEAD"), background: true)
        let pseudo = await withTaskGroup(of: (Int, RefEntry?).self) { group in
            for (index, name) in PlacesCommands.pseudoRefs.enumerated() {
                group.addTask {
                    guard let result = try? await git.run(PlacesCommands.pseudoRef(name), background: true), result.exitCode == 0,
                          let oid = OID(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) else { return (index, nil) }
                    return (index, RefEntry(name: name, target: oid, kind: .pseudo))
                }
            }
            var found: [(Int, RefEntry)] = []
            for await (index, entry) in group { if let entry { found.append((index, entry)) } }
            return found.sorted { $0.0 < $1.0 }.map(\.1)
        }
        var entries: [RefEntry] = []
        let symbolicResult = try await symbolic
        let headResult = try await head
        let headOID = headResult.exitCode == 0 ? OID(headResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) : nil
        let headRef = symbolicResult.exitCode == 0 ? symbolicResult.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        if headRef != nil || headOID != nil {
            entries.append(RefEntry(name: "HEAD", target: headOID, symbolicTarget: headRef, kind: headRef == nil ? .pseudo : .symbolic))
        }
        entries += pseudo
        entries += RefListParser.parse(try await listed)
        return entries
    }

    @discardableResult
    public func listRefsInConsole() async throws -> GitResult {
        try await git.run(PlacesCommands.listRefs, source: .you)
    }

    public func blame(path: String, at revision: String? = nil) async throws -> [BlameLine] {
        BlameParser.parse(try await git.run(PlacesCommands.blame(path: path, at: revision ?? "HEAD"), background: true).stdout)
    }

    public func fileHistory(path: String, limit: Int? = nil) async throws -> [FileHistoryEntry] {
        FileHistoryParser.parse(try await git.run(PlacesCommands.fileHistory(path: path, renameThreshold: renameThreshold, limit: limit), background: true).stdout, path: path)
    }

    public func fileContents(path: String, at revision: String) async throws -> Data {
        try await git.run(PlacesCommands.showFile(path: path, at: revision)).stdout
    }

    public func exportFile(path: String, at revision: OID, to folder: URL? = nil) async throws -> URL {
        let data = try await fileContents(path: path, at: revision.rawValue)
        let base = folder ?? FileManager.default.temporaryDirectory.appending(path: "Vrai", directoryHint: .isDirectory)
        let directory = base.appending(path: revision.short, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = PathParts.split(path).name
        let url = directory.appending(path: name.isEmpty ? "file" : name)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o644)], ofItemAtPath: url.path(percentEncoded: false))
            try FileManager.default.removeItem(at: url)
        }
        try data.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o444)], ofItemAtPath: url.path(percentEncoded: false))
        return url
    }

    public func addWorktreeCommand(path: String, branch: String, createBranch: Bool, startPoint: String? = nil) -> GitCommand {
        PlacesCommands.addWorktree(path: resolvedPath(path), branch: branch, createBranch: createBranch, startPoint: startPoint)
    }

    public func removeWorktreeCommand(path: String, force: Bool) -> GitCommand {
        PlacesCommands.removeWorktree(path: path, force: force)
    }

    public func lockWorktreeCommand(path: String, locked: Bool, reason: String? = nil) -> GitCommand {
        locked ? PlacesCommands.lockWorktree(path: path, reason: reason) : PlacesCommands.unlockWorktree(path: path)
    }

    public func submoduleCommand(path: String?, action: SubmoduleAction) -> GitCommand {
        PlacesCommands.submodule(path: path, action: action)
    }

    public func addSubmoduleCommand(url: String, path: String, branch: String? = nil) -> GitCommand {
        PlacesCommands.addSubmodule(url: url, path: path, branch: branch)
    }

    public func resolvedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        if trimmed == "~" { return FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false) }
        if trimmed.hasPrefix("~/") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
            return (home.hasSuffix("/") ? home : home + "/") + trimmed.dropFirst(2)
        }
        if trimmed.hasPrefix("/") || trimmed.isEmpty { return trimmed }
        guard let root = snapshot?.root else { return trimmed }
        return root.appending(path: trimmed).standardizedFileURL.path(percentEncoded: false)
    }

    @discardableResult
    public func addWorktree(path: String, branch: String, createBranch: Bool, startPoint: String? = nil) async throws -> ActionSummary {
        try await perform("addWorktree") {
            let target = resolvedPath(path)
            try await git.run(PlacesCommands.addWorktree(path: target, branch: branch, createBranch: createBranch, startPoint: startPoint))
            let name = URL(filePath: target).lastPathComponent
            return ActionSummary(String(localized: "Added worktree \(name)", bundle: .module), detail: String(localized: "On \(branch).", bundle: .module))
        }
    }

    public func worktreeChanges(path: String) async -> Int? {
        let folder = URL(filePath: path, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)),
              let result = try? await git.process(at: folder).runAllowingFailure(PlacesCommands.worktreeStatus, background: true),
              result.exitCode == 0 else { return nil }
        let report = StatusParser.parse(result.stdout)
        return report.files.count + report.conflicts.count
    }

    @discardableResult
    public func removeWorktree(path: String, force: Bool = false) async throws -> ActionSummary {
        try await perform("removeWorktree") {
            let listed = WorktreeParser.parse(try await git.run(WorktreeParser.command, background: true).stdout)
            let worktree = listed.first { Self.samePath($0.path, path) } ?? Worktree(path: path)
            let name = URL(filePath: worktree.path).lastPathComponent
            var entry: UndoEntry?
            var captured: WorktreeCapture.Captured?
            if force, worktree.prunable == nil, FileManager.default.fileExists(atPath: worktree.path) {
                let place = worktree.branch ?? worktree.head?.short ?? name
                let message = String(localized: "On \(place): changes from worktree \(name)", bundle: .module)
                captured = try await WorktreeCapture.capture(git.process(at: URL(filePath: worktree.path, directoryHint: .isDirectory)), message: message)
                if let captured {
                    entry = UndoEntry(
                        kind: .worktreeRemove,
                        label: String(localized: "Removed worktree \(name)", bundle: .module),
                        detail: String(localized: "\(n(captured.changes, "uncommitted change")), kept as a stash", bundle: .module),
                        head: worktree.branch.map { "refs/heads/" + $0 } ?? worktree.head?.rawValue,
                        stashCommit: captured.stash,
                        message: message
                    )
                }
            }
            if worktree.locked { try await git.run(PlacesCommands.unlockWorktree(path: worktree.path)) }
            do {
                try await git.run(PlacesCommands.removeWorktree(path: worktree.path, force: force))
            } catch {
                if worktree.locked { _ = try? await git.run(PlacesCommands.lockWorktree(path: worktree.path, reason: worktree.lockReason)) }
                throw error
            }
            if let entry { try await undo.record(entry) }
            let detail = captured.map { String(localized: "Its \(n($0.changes, "uncommitted change")) stay in Undo history for 14 days.", bundle: .module) }
                ?? (worktree.branch != nil ? String(localized: "Its branch stays.", bundle: .module) : String(localized: "Its commits stay in the repository.", bundle: .module))
            return ActionSummary(String(localized: "Removed worktree \(name)", bundle: .module), detail: detail)
        }
    }

    @discardableResult
    public func setWorktreeLocked(path: String, locked: Bool, reason: String? = nil) async throws -> ActionSummary {
        try await perform("lockWorktree") {
            try await git.run(lockWorktreeCommand(path: path, locked: locked, reason: reason))
            let name = URL(filePath: path).lastPathComponent
            return ActionSummary(locked ? String(localized: "Locked \(name)", bundle: .module) : String(localized: "Unlocked \(name)", bundle: .module))
        }
    }

    @discardableResult
    public func pruneWorktrees() async throws -> ActionSummary {
        try await perform("pruneWorktrees") {
            let result = try await git.run(PlacesCommands.pruneWorktrees())
            let removed = (result.output + "\n" + result.errorOutput).split(separator: "\n").filter { $0.hasPrefix("Removing ") }.count
            guard removed > 0 else { return ActionSummary(String(localized: "No stale worktrees", bundle: .module), detail: String(localized: "Every worktree folder is still there.", bundle: .module)) }
            return ActionSummary(String(localized: "Pruned \(n(removed, "stale worktree"))", bundle: .module), detail: String(localized: "Their folders were already gone.", bundle: .module))
        }
    }

    @discardableResult
    public func submodule(path: String, action: SubmoduleAction, progress: ProgressHandler? = nil) async throws -> ActionSummary {
        try await perform("submodule") {
            let name = PathParts.split(path).name
            let command = PlacesCommands.submodule(path: path, action: action)
            switch action {
            case .initUpdate, .update, .updateRemote:
                try await runNetwork(command, progress: progress)
                let checkedOut = try? await submoduleHead(path)
                let detail = checkedOut.map { String(localized: "Checked out \($0.short).", bundle: .module) }
                switch action {
                case .initUpdate: return ActionSummary(String(localized: "Initialized \(name)", bundle: .module), detail: detail)
                default: return ActionSummary(String(localized: "Updated \(name)", bundle: .module), detail: detail)
                }
            case .sync:
                try await git.run(command)
                return ActionSummary(String(localized: "Synced submodule URLs", bundle: .module))
            case .record:
                try await git.run(command)
                return ActionSummary(String(localized: "Staged the new commit for \(name)", bundle: .module), detail: String(localized: "Commit to record it.", bundle: .module))
            case .deinit:
                try await git.run(command)
                return ActionSummary(String(localized: "Deinitialized \(name)", bundle: .module), detail: String(localized: "It stays in .gitmodules, so you can initialize it again later.", bundle: .module))
            }
        }
    }

    @discardableResult
    public func addSubmodule(url: String, path: String, branch: String? = nil, progress: ProgressHandler? = nil) async throws -> ActionSummary {
        try await perform("addSubmodule") {
            do {
                try await runNetwork(PlacesCommands.addSubmodule(url: url, path: path, branch: branch), progress: progress)
            } catch let error as GitError {
                if case .refExists = error.code { throw GitError(.pathExists, result: error.result) }
                throw error
            }
            return ActionSummary(String(localized: "Added submodule \(path)", bundle: .module), detail: String(localized: "Commit .gitmodules to record it.", bundle: .module))
        }
    }

    @discardableResult
    public func removeReplacement(object: String) async throws -> ActionSummary {
        try await perform("removeReplacement") {
            let ref = "refs/replace/" + object
            let before = try await resolve(ref)
            try await git.run(PlacesCommands.removeReplacement(object))
            if let before {
                let entry = UndoEntry(kind: .refDelete, label: String(localized: "Removed the replacement for \(String(object.prefix(7)))", bundle: .module), refsBefore: [ref: before])
                try await undo.record(entry)
                try? await undo.complete(entry.id)
            }
            return ActionSummary(String(localized: "Removed the replacement for \(String(object.prefix(7)))", bundle: .module), detail: String(localized: "git shows the original object again.", bundle: .module))
        }
    }

    public static func isSamePath(_ a: String, _ b: String) -> Bool {
        samePath(a, b)
    }

    func submoduleHead(_ path: String) async throws -> OID? {
        var root = snapshot?.root
        if root == nil { root = try await rewriteLocation().root }
        guard let root else { return nil }
        let process = git.process(at: root.appending(path: path, directoryHint: .isDirectory))
        let result = try await process.runAllowingFailure(.read(["rev-parse", "-q", "--verify", "HEAD"]), background: true)
        return result.exitCode == 0 ? OID(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) : nil
    }
}
