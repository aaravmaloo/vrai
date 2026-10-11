import Foundation

public enum SubmoduleAction: String, Sendable, Hashable, Codable, CaseIterable {
    case initUpdate
    case update
    case updateRemote
    case sync
    case record
    case `deinit`
}

public enum PlacesCommands {
    public static func addWorktree(path: String, branch: String, createBranch: Bool, startPoint: String? = nil) -> GitCommand {
        var arguments = ["worktree", "add"]
        if createBranch {
            arguments += ["-b", branch, "--", path]
            if let startPoint, !startPoint.isEmpty, startPoint != "HEAD" { arguments.append(startPoint) }
        } else {
            arguments += ["--", path, branch]
        }
        return .write(arguments)
    }

    public static func removeWorktree(path: String, force: Bool) -> GitCommand {
        var arguments = ["worktree", "remove"]
        if force { arguments.append("--force") }
        arguments += ["--", path]
        return .write(arguments, risk: force ? .destructive : .safe)
    }

    public static func lockWorktree(path: String, reason: String?) -> GitCommand {
        var arguments = ["worktree", "lock"]
        if let reason, !reason.isEmpty { arguments += ["--reason", reason] }
        arguments += ["--", path]
        return .write(arguments)
    }

    public static func unlockWorktree(path: String) -> GitCommand {
        .write(["worktree", "unlock", "--", path])
    }

    public static func pruneWorktrees() -> GitCommand {
        .write(["worktree", "prune", "--verbose"])
    }

    public static let listWorktrees = WorktreeParser.command

    public static func submodule(path: String?, action: SubmoduleAction) -> GitCommand {
        let paths = path.map { ["--", $0] } ?? []
        switch action {
        case .initUpdate:
            return .write(["submodule", "update", "--init", "--recursive", "--progress"] + paths)
        case .update:
            return .write(["submodule", "update", "--recursive", "--progress"] + paths)
        case .updateRemote:
            return .write(["submodule", "update", "--init", "--remote", "--merge", "--progress"] + paths)
        case .sync:
            return .write(["submodule", "sync", "--recursive"] + paths)
        case .record:
            return .write(["add", "--"] + (path.map { [$0] } ?? []))
        case .deinit:
            return .write(["submodule", "deinit", "-f"] + (path.map { ["--", $0] } ?? ["--all"]), risk: .destructive)
        }
    }

    public static func addSubmodule(url: String, path: String, branch: String? = nil) -> GitCommand {
        var arguments = ["submodule", "add", "--progress"]
        if let branch, !branch.isEmpty { arguments += ["-b", branch] }
        arguments += ["--", url]
        if !path.isEmpty { arguments.append(path) }
        return .write(arguments)
    }

    public static func reflog(ref: String = "HEAD", limit: Int = 500) -> GitCommand {
        ReflogParser.command(ref: ref, limit: limit)
    }

    public static func restoreReflog(_ selector: String) -> GitCommand {
        GitCommand(["reset", "--keep", selector], risk: .rewrites, access: .write)
    }

    public static func blame(path: String, at revision: String?) -> GitCommand {
        BlameParser.command(path: path, at: revision)
    }

    public static func annotate(path: String, at revision: String?) -> GitCommand {
        var arguments = ["annotate"]
        if let revision, !revision.isEmpty { arguments.append(revision) }
        return .read(arguments + ["--", path])
    }

    public static func fileHistory(path: String, renameThreshold: Int = 50, limit: Int? = nil) -> GitCommand {
        FileHistoryParser.command(path: path, renameThreshold: renameThreshold, limit: limit)
    }

    public static func showFile(path: String, at revision: String) -> GitCommand {
        .read(["show", revision + ":" + path])
    }

    public static let refs = RefListParser.command

    public static let listRefs = GitCommand.read(["for-each-ref", "--format=%(refname) %(objectname:short)"])

    public static func pseudoRef(_ name: String) -> GitCommand {
        .read(["rev-parse", "-q", "--verify", "--end-of-options", name], acceptedExitCodes: [0, 1])
    }

    public static let symbolicHead = GitCommand.read(["symbolic-ref", "-q", "HEAD"], acceptedExitCodes: [0, 1])

    public static func removeReplacement(_ object: String) -> GitCommand {
        .write(["replace", "-d", object], risk: .destructive)
    }

    public static let pseudoRefs = ["ORIG_HEAD", "FETCH_HEAD", "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_HEAD", "AUTO_MERGE"]
}

extension UndoEntry.Kind {
    public static let worktreeRemove = UndoEntry.Kind(rawValue: "worktreeRemove")
    public static let refDelete = UndoEntry.Kind(rawValue: "refDelete")
}

extension GitProcess {
    public nonisolated func process(at directory: URL) -> GitProcess {
        GitProcess(executable: executable, workingDirectory: directory, environment: environment) { [self] entry in
            self.forward(entry)
        }
    }
}
