import Foundation

extension UndoStore {
    func apply(_ entry: UndoEntry) async throws {
        switch entry.kind {
        case .discardFile, .restoreFile:
            try await restoreFiles(entry)
        case .discardLines:
            try await restorePatch(entry)
        case .branchDelete:
            try await restoreDeletedRefs(entry)
        case .tagDelete:
            try await restoreDeletedTags(entry)
        case .stashDrop:
            try await restoreStash(entry)
        case let kind where Self.refMovingKinds.contains(kind):
            try await restoreRefs(entry)
        default:
            if !trackedRefs(entry).isEmpty {
                try await restoreRefs(entry)
            } else if !entry.files.isEmpty {
                try await restoreFiles(entry)
            } else if entry.patch != nil {
                try await restorePatch(entry)
            } else if entry.stashCommit != nil {
                try await restoreStash(entry)
            } else {
                throw GitError(.undoNoLongerApplies)
            }
        }
    }

    func noLongerApplies(_ result: GitResult? = nil) -> GitError {
        GitError(.undoNoLongerApplies, result: result)
    }

    func runOrNoLongerApplies(_ command: GitCommand) async throws {
        let result = try await git.runAllowingFailure(command)
        guard result.succeeded else { throw noLongerApplies(result) }
    }

    func restoreRefs(_ entry: UndoEntry) async throws {
        let refs = trackedRefs(entry)
        guard !refs.isEmpty, try await !operationInProgress() else { throw noLongerApplies() }
        let headRef = try await symbolicHead()
        if refs.contains("HEAD"), headRef != nil { throw noLongerApplies() }
        var after: [String: OID] = [:]
        for ref in refs {
            let expected: OID
            if let recorded = entry.refsAfter {
                expected = recorded[ref] ?? Self.absent
            } else {
                expected = try await reflogAfter(ref, before: before(ref, in: entry), since: entry.date, kind: entry.kind)
            }
            guard try await currentValue(of: ref) == expected else { throw noLongerApplies() }
            after[ref] = expected
        }
        let changed = refs.filter { after[$0] != before($0, in: entry) }
        guard !changed.isEmpty else { throw noLongerApplies() }
        let root = try await worktreeRoot()
        let checkedOut = changed.first { $0 == "HEAD" || $0 == headRef }
        for ref in changed where ref != checkedOut {
            if let elsewhere = try await worktreePath(of: ref), elsewhere.standardizedFileURL.path != root.standardizedFileURL.path {
                throw noLongerApplies()
            }
        }
        if let ref = checkedOut {
            try await moveCheckedOut(ref, to: before(ref, in: entry), from: after[ref] ?? Self.absent, entry: entry)
        }
        for ref in changed where ref != checkedOut {
            let target = before(ref, in: entry)
            let current = after[ref] ?? Self.absent
            if target.isZero {
                try await runOrNoLongerApplies(.write(["update-ref", "-m", "vrai: undo " + entry.label, "-d", ref, current.rawValue]))
            } else {
                try await runOrNoLongerApplies(.write(["update-ref", "-m", "vrai: undo " + entry.label, ref, target.rawValue, current.isZero ? "" : current.rawValue]))
            }
        }
        if entry.kind == .resetHard, let stash = entry.stashCommit {
            let withIndex = try await git.runAllowingFailure(.write(["stash", "apply", "--index", stash.rawValue]))
            if !withIndex.succeeded {
                try await runOrNoLongerApplies(.write(["stash", "apply", stash.rawValue]))
            }
        }
    }

    func moveCheckedOut(_ ref: String, to target: OID, from current: OID, entry: UndoEntry) async throws {
        if target.isZero {
            try await runOrNoLongerApplies(.write(["update-ref", "-m", "vrai: undo " + entry.label, "-d", ref, current.rawValue]))
            return
        }
        switch entry.kind {
        case .commit, .amend:
            try await runOrNoLongerApplies(GitCommand(["reset", "--soft", target.rawValue], risk: .rewrites, access: .write))
        case .reset:
            let index = try await git.runAllowingFailure(.write(["write-tree"]), background: true)
            let tree = try await git.runAllowingFailure(.read(["rev-parse", "-q", "--verify", target.rawValue + "^{tree}"], acceptedExitCodes: [0, 1]), background: true)
            if index.succeeded, tree.succeeded, index.output.trimmingCharacters(in: .whitespacesAndNewlines) == tree.output.trimmingCharacters(in: .whitespacesAndNewlines) {
                try await runOrNoLongerApplies(GitCommand(["reset", "--soft", target.rawValue], risk: .rewrites, access: .write))
                return
            }
            let keep = try await git.runAllowingFailure(GitCommand(["reset", "--keep", target.rawValue], risk: .rewrites, access: .write))
            if keep.succeeded { return }
            try await runOrNoLongerApplies(GitCommand(["reset", "--mixed", "-q", target.rawValue], risk: .rewrites, access: .write))
        default:
            try await runOrNoLongerApplies(GitCommand(["reset", "--keep", target.rawValue], risk: .rewrites, access: .write))
        }
    }

    func symbolicHead() async throws -> String? {
        let result = try await git.run(.read(["symbolic-ref", "-q", "HEAD"], acceptedExitCodes: [0, 1]), background: true)
        let name = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.exitCode == 0 && !name.isEmpty ? name : nil
    }

    func worktreePath(of ref: String) async throws -> URL? {
        guard ref.hasPrefix("refs/heads/") else { return nil }
        let output = try await git.run(.read(["for-each-ref", "--format=%(worktreepath)", ref]), background: true).output.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : URL(filePath: output, directoryHint: .isDirectory)
    }

    struct ReflogLine {
        var new: OID
        var time: Int
        var message: String
    }

    func reflogAfter(_ ref: String, before: OID, since: Date, kind: UndoEntry.Kind) async throws -> OID {
        let result = try await git.runAllowingFailure(.read(["reflog", "show", "--date=unix", "--format=%H%x00%gd%x00%gs", "-n", "200", ref]), background: true)
        guard result.succeeded, !result.stdout.isEmpty else { return try await currentValue(of: ref) }
        var lines: [ReflogLine] = []
        for row in result.output.split(separator: "\n") {
            let fields = row.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3, let oid = OID(fields[0]),
                  let open = fields[1].lastIndex(of: "{"), let time = Int(fields[1][fields[1].index(after: open)...].dropLast())
            else { continue }
            lines.append(ReflogLine(new: oid, time: time, message: fields[2]))
        }
        let chronological = Array(lines.reversed())
        let floor = Int(since.timeIntervalSince1970) - 2
        for start in chronological.indices {
            let old = start == 0 ? Self.absent : chronological[start - 1].new
            let line = chronological[start]
            guard line.time >= floor, old == before, Self.reflog(line.message, matches: kind) else { continue }
            var end = start
            if kind == .cherryPick || kind == .revert {
                while end + 1 < chronological.count, Self.reflog(chronological[end + 1].message, matches: kind) { end += 1 }
            }
            return chronological[end].new
        }
        return before
    }

    static func reflog(_ message: String, matches kind: UndoEntry.Kind) -> Bool {
        switch kind {
        case .commit: message.hasPrefix("commit:") || message.hasPrefix("commit (initial):") || message.hasPrefix("commit (merge):")
        case .amend: message.hasPrefix("commit (amend):")
        case .merge: message.hasPrefix("merge ") || message.hasPrefix("merge:") || message.hasPrefix("commit (merge):")
        case .pull: message.hasPrefix("pull") || message.hasPrefix("commit (merge):")
        case .rebase: message.isEmpty || message.contains("rebase") || message.contains("replay")
        case .reset, .resetHard: message.hasPrefix("reset:")
        case .cherryPick: message.hasPrefix("cherry-pick")
        case .revert: message.hasPrefix("revert")
        default: true
        }
    }

    func restoreFiles(_ entry: UndoEntry) async throws {
        guard !entry.files.isEmpty else { throw noLongerApplies() }
        let paths = Array(entry.files.keys)
        if let expected = entry.filesAfter {
            let now = try await hashWorktree(paths, write: false)
            for path in paths where now[path] != expected[path] { throw noLongerApplies() }
        } else if entry.kind == .discardFile {
            try await checkDiscardedFilesUnchanged(paths)
        }
        let modes = try await protectedModes(entry.id)
        let root = try await worktreeRoot()
        let fileManager = FileManager.default
        for path in entry.files.keys.sorted() {
            guard let oid = entry.files[path] else { continue }
            let url = root.appending(path: path)
            let full = url.path(percentEncoded: false)
            let existing = try? fileManager.attributesOfItem(atPath: full)
            if oid.isZero {
                if existing != nil { try fileManager.removeItem(at: url) }
                continue
            }
            let data = try await git.run(.read(["cat-file", "blob", oid.rawValue]), background: true).stdout
            let mode = modes[oid] ?? "100644"
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let wasLink = existing?[.type] as? FileAttributeType == .typeSymbolicLink
            if mode == "120000" {
                if existing != nil { try fileManager.removeItem(at: url) }
                try fileManager.createSymbolicLink(atPath: full, withDestinationPath: String(decoding: data, as: UTF8.self))
                continue
            }
            if wasLink { try fileManager.removeItem(at: url) }
            var permissions = wasLink ? 0o644 : ((existing?[.posixPermissions] as? NSNumber)?.intValue ?? 0o644)
            try data.write(to: url, options: .atomic)
            permissions = mode == "100755" ? permissions | 0o111 : permissions & ~0o111
            try fileManager.setAttributes([.posixPermissions: NSNumber(value: permissions)], ofItemAtPath: full)
        }
    }

    func checkDiscardedFilesUnchanged(_ paths: [String]) async throws {
        var tracked = Set<String>()
        let listed = try await git.run(GitCommand(["ls-files", "-z", "--"] + paths, environment: ["GIT_LITERAL_PATHSPECS": "1"]), background: true).stdout
        tracked = Set(ParseSupport.nulFields(listed).filter { !$0.isEmpty })
        let root = try await worktreeRoot()
        for path in paths {
            if tracked.contains(path) {
                let diff = try await git.run(GitCommand(["diff", "--quiet", "--", path], acceptedExitCodes: [0, 1], environment: ["GIT_LITERAL_PATHSPECS": "1"]), background: true)
                if diff.exitCode != 0 { throw noLongerApplies() }
            } else if (try? FileManager.default.attributesOfItem(atPath: root.appending(path: path).path(percentEncoded: false))) != nil {
                throw noLongerApplies()
            }
        }
    }

    func protectedModes(_ id: UUID) async throws -> [OID: String] {
        var modes: [OID: String] = [:]
        for ref in try await refNames(of: id) {
            let result = try await git.runAllowingFailure(.read(["ls-tree", "-z", ref]), background: true)
            guard result.succeeded else { continue }
            for record in ParseSupport.nulFields(result.stdout) {
                guard let tab = record.firstIndex(of: "\t") else { continue }
                let parts = record[..<tab].split(separator: " ")
                if parts.count == 3, parts[1] == "blob", let oid = OID(String(parts[2])) { modes[oid] = String(parts[0]) }
            }
        }
        return modes
    }

    func restorePatch(_ entry: UndoEntry) async throws {
        guard let patch = entry.patch else { throw noLongerApplies() }
        let data = try await git.run(.read(["cat-file", "blob", patch.rawValue]), background: true).stdout
        try await runOrNoLongerApplies(StagingService.applyCommand(data, cached: false, reverse: false))
    }

    func restoreDeletedRefs(_ entry: UndoEntry) async throws {
        guard !entry.refsBefore.isEmpty else { throw noLongerApplies() }
        for ref in entry.refsBefore.keys {
            if try await !currentValue(of: ref).isZero { throw noLongerApplies() }
        }
        for ref in entry.refsBefore.keys.sorted() {
            guard let oid = entry.refsBefore[ref] else { continue }
            if ref.hasPrefix("refs/heads/") {
                try await runOrNoLongerApplies(.write(["branch", String(ref.dropFirst("refs/heads/".count)), oid.rawValue]))
            } else {
                try await runOrNoLongerApplies(.write(["update-ref", "-m", "vrai: undo " + entry.label, ref, oid.rawValue, ""]))
            }
        }
    }

    func restoreDeletedTags(_ entry: UndoEntry) async throws {
        guard !entry.refsBefore.isEmpty else { throw noLongerApplies() }
        var missing: [String] = []
        for ref in entry.refsBefore.keys.sorted() {
            let current = try await currentValue(of: ref)
            if current.isZero {
                missing.append(ref)
            } else if current != entry.refsBefore[ref] {
                throw noLongerApplies()
            }
        }
        for ref in missing {
            guard let oid = entry.refsBefore[ref] else { continue }
            try await runOrNoLongerApplies(.write(["update-ref", ref, oid.rawValue]))
        }
    }

    func restoreStash(_ entry: UndoEntry) async throws {
        guard let stash = entry.stashCommit else { throw noLongerApplies() }
        let listed = try await git.run(.read(["stash", "list", "--format=%H"]), background: true).output
        if listed.split(separator: "\n").contains(where: { $0 == stash.rawValue }) { throw noLongerApplies() }
        try await runOrNoLongerApplies(.write(["stash", "store", "-m", entry.message ?? entry.label, stash.rawValue]))
    }
}
