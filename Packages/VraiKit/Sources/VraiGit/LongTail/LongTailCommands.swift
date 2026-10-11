import Foundation

public enum ArchiveFormat: String, Sendable, Hashable, CaseIterable, Codable {
    case zip
    case tarGz = "tar.gz"
    case tar

    public var fileExtension: String { rawValue }
}

public enum TextFileKind: String, Sendable, Hashable, CaseIterable, Codable {
    case gitignore = ".gitignore"
    case gitattributes = ".gitattributes"
    case mailmap = ".mailmap"

    public var fileName: String { rawValue }
}

public enum CloneHistory: Sendable, Hashable, Codable {
    case full
    case blobless
    case treeless
    case shallow(depth: Int)

    public var depth: Int? {
        if case .shallow(let depth) = self { return depth }
        return nil
    }

    public var filter: String? {
        switch self {
        case .blobless: "blob:none"
        case .treeless: "tree:0"
        default: nil
        }
    }
}

public enum MaintenanceTask: String, Sendable, Hashable, CaseIterable, Codable {
    case gc
    case gcAggressive
    case gcPruneNow
    case fsck
    case prune
    case repack
    case commitGraph
    case backfill
    case packRefs
    case multiPackIndex
    case prunePacked

    public var command: GitCommand {
        switch self {
        case .gc: LongTailCommands.write(["gc"])
        case .gcAggressive: LongTailCommands.write(["gc", "--aggressive"])
        case .gcPruneNow: LongTailCommands.write(["gc", "--prune=now"])
        case .fsck: LongTailCommands.read(["fsck", "--no-progress"])
        case .prune: LongTailCommands.write(["prune", "--expire=2.weeks.ago"])
        case .repack: LongTailCommands.write(["repack", "-a", "-d", "--write-bitmap-index"])
        case .commitGraph: LongTailCommands.write(["commit-graph", "write", "--reachable", "--changed-paths"])
        case .backfill: LongTailCommands.write(["backfill"])
        case .packRefs: LongTailCommands.write(["pack-refs", "--all"])
        case .multiPackIndex: LongTailCommands.write(["multi-pack-index", "write"])
        case .prunePacked: LongTailCommands.write(["prune-packed"])
        }
    }
}

public enum LongTailCommands {
    static func write(_ arguments: [String], stdin: Data? = nil) -> GitCommand {
        let sub = arguments.first ?? ""
        let rest = Array(arguments.dropFirst())
        return GitCommand(arguments, stdin: stdin, risk: CommandParser.risk(sub: sub, rest: rest), access: .write)
    }

    static func read(_ arguments: [String], stdin: Data? = nil, acceptedExitCodes: Set<Int32> = [0]) -> GitCommand {
        GitCommand(arguments, stdin: stdin, access: .read, acceptedExitCodes: acceptedExitCodes)
    }

    public static func clone(url: String, to destination: String, branch: String? = nil, history: CloneHistory = .full, recurseSubmodules: Bool = false, bare: Bool = false, mirror: Bool = false, progress: Bool = true) -> GitCommand {
        var arguments = ["clone"]
        if progress { arguments.append("--progress") }
        if let branch, !branch.isEmpty, !mirror { arguments += ["--branch", branch] }
        if recurseSubmodules, !bare, !mirror { arguments.append("--recurse-submodules") }
        if let depth = history.depth { arguments += ["--depth", String(depth)] }
        if let filter = history.filter { arguments.append("--filter=" + filter) }
        if mirror {
            arguments.append("--mirror")
        } else if bare {
            arguments.append("--bare")
        }
        arguments += ["--", url, destination]
        return write(arguments)
    }

    public static func scalarClone(url: String, to destination: String, branch: String? = nil, maintenance: Bool = true) -> GitCommand {
        var arguments = ["scalar", "clone"]
        if let branch, !branch.isEmpty { arguments += ["--branch", branch] }
        if !maintenance { arguments.append("--no-maintenance") }
        arguments += [url, destination]
        var command = GitCommand(arguments, access: .write)
        command.display = CommandDisplay.render(arguments)
        return command
    }

    public static func lsRemote(url: String) -> GitCommand {
        read(["ls-remote", "--symref", "--", url, "HEAD", "refs/heads/*"])
    }

    public static func bundleListHeads(file: String) -> GitCommand {
        read(["bundle", "list-heads", file])
    }

    public static func bundleVerify(file: String) -> GitCommand {
        read(["bundle", "verify", "--quiet", file])
    }

    public static func initRepository(at path: String, initialBranch: String?) -> GitCommand {
        var arguments = ["init"]
        if let initialBranch, !initialBranch.isEmpty { arguments.append("--initial-branch=" + initialBranch) }
        arguments.append(path)
        return write(arguments)
    }

    public static func checkRefFormat(branch: String) -> GitCommand {
        read(["check-ref-format", "--branch", branch], acceptedExitCodes: [0, 1, 128])
    }

    public static func addFiles(_ paths: [String]) -> GitCommand {
        write(["add", "--"] + paths)
    }

    public static func initialCommit(message: String) -> GitCommand {
        write(["commit", "-q", "-F", "-"], stdin: Data(message.utf8))
    }

    public static func commitReusing(_ id: String) -> GitCommand {
        write(["commit", "-q", "--no-verify", "-C", id])
    }

    public static func addAll(_ paths: [String]) -> GitCommand {
        write(["add", "-A", "--"] + paths)
    }

    public static func commit(message: String, author: String? = nil, date: String? = nil) -> GitCommand {
        var arguments = ["commit", "-q", "--no-verify", "-F", "-"]
        if let author { arguments.append("--author=" + author) }
        if let date { arguments.append("--date=" + date) }
        return write(arguments, stdin: Data((message.hasSuffix("\n") ? message : message + "\n").utf8))
    }

    public static func fixup(_ id: String) -> GitCommand {
        write(["commit", "--fixup=" + id])
    }

    public static func hasStagedChanges() -> GitCommand {
        read(["diff-index", "--cached", "--quiet", "HEAD", "--"], acceptedExitCodes: [0, 1])
    }

    public static func hasUnstagedChanges() -> GitCommand {
        read(["diff-files", "--quiet", "--"], acceptedExitCodes: [0, 1])
    }

    public static func historyReword(_ id: String, editor: String? = nil) -> GitCommand {
        var command = write(["history", "reword", id])
        command.editor = editor
        return command
    }

    public static func historySplit(_ id: String, paths: [String], editor: String? = nil) -> GitCommand {
        let answers = Data(String(repeating: "a\n", count: max(1, paths.count) * 4).utf8)
        var command = write(["history", "split", id, "--"] + paths, stdin: answers)
        command.editor = editor
        return command
    }

    public static func commitFiles(_ id: String) -> GitCommand {
        read(["diff-tree", "--no-commit-id", "-r", "-z", "--name-status", "--root", "--find-renames", id])
    }

    public static func mergesSince(_ id: String) -> GitCommand {
        read(["rev-list", "--merges", "--count", id + "..HEAD", "--"])
    }

    public static func formatPatch(_ id: String, number: Int, to directory: String) -> GitCommand {
        write(["format-patch", "-1", "--start-number", String(number), "-o", directory, id])
    }

    public static func formatSeries(base: String, tip: String, to directory: String, coverLetter: Bool = false) -> GitCommand {
        var arguments = ["format-patch", "-o", directory]
        if coverLetter { arguments.append("--cover-letter") }
        arguments.append(base + ".." + tip)
        return write(arguments)
    }

    public static func sendEmail(files: [String], to recipient: String? = nil) -> GitCommand {
        var arguments = ["send-email"]
        if let recipient, !recipient.isEmpty { arguments.append("--to=" + recipient) }
        return write(arguments + files)
    }

    public static func imapSend(mbox: Data? = nil) -> GitCommand {
        write(["imap-send"], stdin: mbox)
    }

    public static func requestPull(base: String, url: String, end: String) -> GitCommand {
        read(["request-pull", base, url, end])
    }

    public static func archive(ref: String, format: ArchiveFormat, prefix: String, output: String, paths: [String] = []) -> GitCommand {
        var arguments = ["archive", "--format=" + format.rawValue]
        if !prefix.isEmpty { arguments.append("--prefix=" + prefix) }
        arguments += ["-o", output, ref]
        if !paths.isEmpty { arguments += ["--"] + paths }
        return write(arguments)
    }

    public static func archiveCommitID(stdin: Data) -> GitCommand {
        read(["get-tar-commit-id"], stdin: stdin, acceptedExitCodes: [0, 1])
    }

    public static func bundleCreate(file: String, refs: [String]) -> GitCommand {
        write(["bundle", "create", file] + (refs.isEmpty ? ["--all"] : refs))
    }

    public static func applyPatches(files: [String], threeWay: Bool, signoff: Bool) -> GitCommand {
        var arguments = ["am"]
        if threeWay { arguments.append("--3way") }
        if signoff { arguments.append("--signoff") }
        return write(arguments + ["--"] + files)
    }

    public static func mailsplit(file: String, to directory: String) -> GitCommand {
        read(["mailsplit", "-o" + directory, "--", file])
    }

    public static func mailinfo(message: String, patch: String, mail: Data) -> GitCommand {
        read(["mailinfo", message, patch], stdin: mail)
    }

    public static func sparseList() -> GitCommand {
        read(["sparse-checkout", "list"], acceptedExitCodes: [0, 128])
    }

    public static func sparseSet(_ folders: [String]) -> GitCommand {
        write(["sparse-checkout", "set", "--cone"] + folders)
    }

    public static func sparseDisable() -> GitCommand {
        write(["sparse-checkout", "disable"])
    }

    public static func topLevelFolders(_ revision: String = "HEAD") -> GitCommand {
        read(["ls-tree", "-d", "-z", "--name-only", revision])
    }

    public static func lastModified(_ paths: [String], revision: String = "HEAD") -> GitCommand {
        read(["last-modified", "-z", revision, "--"] + paths)
    }

    public static func commitDates(_ ids: [String]) -> GitCommand {
        read(["show", "-s", "--no-show-signature", "--format=%H%x00%ct%x00%s"] + ids)
    }

    public static func countObjects() -> GitCommand {
        read(["count-objects", "-v"])
    }

    public static func repoInfo() -> GitCommand {
        read(["repo", "info", "-z", "layout.bare", "layout.shallow", "object.format", "references.format"])
    }

    public static func repoStructure() -> GitCommand {
        read(["repo", "structure", "--format=lines"])
    }

    public static func commitCount() -> GitCommand {
        read(["rev-list", "--count", "--all", "--"])
    }

    public static func firstCommit() -> GitCommand {
        read(["log", "--max-parents=0", "-z", "--format=%H%x00%s%x00%at", "HEAD", "--"])
    }

    public static func contributors(_ revision: String = "HEAD") -> GitCommand {
        read(["shortlog", "-sne", revision, "--"])
    }

    public static func packIndex(_ index: Data) -> GitCommand {
        read(["show-index"], stdin: index)
    }

    public static func verifyPack(_ indexPath: String) -> GitCommand {
        read(["verify-pack", "-s", indexPath], acceptedExitCodes: [0, 1, 128])
    }

    public static func repairPackIndex(_ packPath: String) -> GitCommand {
        write(["index-pack", packPath])
    }

    public static func objectFormat() -> GitCommand {
        read(["rev-parse", "--show-object-format"])
    }

    public static func partialCloneFilter() -> GitCommand {
        read(["config", "--get-regexp", "^remote\\..*\\.partialclonefilter$"], acceptedExitCodes: [0, 1])
    }

    public static func ignoreCheck(_ path: String) -> GitCommand {
        read(["check-ignore", "-v", "--no-index", "--", path], acceptedExitCodes: [0, 1])
    }

    public static func attributes(_ paths: [String]) -> GitCommand {
        read(["check-attr", "-z", "--all", "--"] + paths)
    }

    public static func mailmapPreview(file: String, contacts: [String]) -> GitCommand {
        read(["check-mailmap", "--mailmap-file=" + file] + contacts)
    }

    public static func assumeUnchanged(_ path: String, _ on: Bool) -> GitCommand {
        write(["update-index", on ? "--assume-unchanged" : "--no-assume-unchanged", "--", path])
    }

    public static func skipWorktree(_ path: String, _ on: Bool) -> GitCommand {
        write(["update-index", on ? "--skip-worktree" : "--no-skip-worktree", "--", path])
    }

    public static func intentToAdd(_ paths: [String]) -> GitCommand {
        write(["add", "--intent-to-add", "--"] + paths)
    }

    public static func cleanPreview(ignored: Bool, paths: [String] = []) -> GitCommand {
        var arguments = ["clean", "-n", "-d"]
        if ignored { arguments.append("-x") }
        return read(arguments + ["--"] + paths)
    }

    public static func clean(ignored: Bool, paths: [String] = []) -> GitCommand {
        var arguments = ["clean", "-f", "-d"]
        if ignored { arguments.append("-x") }
        return write(arguments + ["--"] + paths)
    }

    public static func moveFile(from: String, to: String) -> GitCommand {
        write(["mv", "--", from, to])
    }

    public static func removeFile(_ path: String, keepFile: Bool) -> GitCommand {
        write(["rm", keepFile ? "--cached" : "-f", "--", path])
    }

    public static func bugReport(to directory: String) -> GitCommand {
        write(["bugreport", "-o", directory])
    }

    public static func diagnose(to directory: String) -> GitCommand {
        write(["diagnose", "-o", directory])
    }

    public static func compare(_ left: String, _ right: String, limit: Int = 200) -> GitCommand {
        read(["log", "--left-right", "-z", "--max-count=\(limit)", "--format=%m%x00%H%x00%s%x00%an%x00%at", left + "..." + right, "--"])
    }

    public static func compareCounts(_ left: String, _ right: String) -> GitCommand {
        read(["rev-list", "--left-right", "--count", left + "..." + right, "--"])
    }

    public static func mergeBase(_ left: String, _ right: String) -> GitCommand {
        read(["merge-base", left, right], acceptedExitCodes: [0, 1])
    }

    public static func cherry(upstream: String, head: String) -> GitCommand {
        read(["cherry", upstream, head])
    }

    public static func patchID(stdin: Data) -> GitCommand {
        read(["patch-id", "--stable"], stdin: stdin)
    }

    public static func commitPatch(_ id: String) -> GitCommand {
        read(["show", "--format=", "--patch", "--no-color", "--no-ext-diff", id, "--"])
    }

    public static func rawDiff(_ left: String, _ right: String) -> GitCommand {
        read(["diff-tree", "-r", "-z", "--raw", "--merge-base", left, right])
    }

    public static func pairStats(_ raw: Data) -> GitCommand {
        read(["diff-pairs", "-z", "--numstat"], stdin: raw)
    }

    public static func nameRev(_ id: String) -> GitCommand {
        read(["name-rev", "--name-only", "--no-undefined", "--refs=refs/heads/*", id], acceptedExitCodes: [0, 128])
    }

    public static func showRef(_ name: String) -> GitCommand {
        read(["show-ref", "--verify", "--", name], acceptedExitCodes: [0, 1])
    }

    public static func manual(_ command: String) -> GitCommand {
        var value = read(["help", "--man", command])
        value.environment = ["MANPAGER": "cat", "PAGER": "cat", "MANWIDTH": "92", "GIT_PAGER": "cat"]
        return value
    }

    public static func remoteURL(_ remote: String) -> GitCommand {
        read(["remote", "get-url", remote], acceptedExitCodes: [0, 2, 128])
    }
}
