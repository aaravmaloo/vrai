import Foundation

public struct RepositoryLocation: Sendable, Hashable {
    public var root: URL?
    public var gitDir: URL
    public var commonDir: URL
    public var isBare: Bool
    public var isShallow: Bool
    public var hooksDir: URL

    public static let command = GitCommand.read(["rev-parse", "--path-format=absolute", "--git-dir", "--git-common-dir", "--is-bare-repository", "--is-shallow-repository", "--git-path", "hooks", "--show-toplevel"])
    public static let bareCommand = GitCommand.read(["rev-parse", "--path-format=absolute", "--git-dir", "--git-common-dir", "--is-bare-repository", "--is-shallow-repository", "--git-path", "hooks"])

    public static func parse(_ data: Data) -> RepositoryLocation? {
        let lines = ParseSupport.string(data).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 5 else { return nil }
        let root = lines.count > 5 && !lines[5].isEmpty ? URL(filePath: lines[5], directoryHint: .isDirectory) : nil
        return RepositoryLocation(
            root: root,
            gitDir: URL(filePath: lines[0], directoryHint: .isDirectory),
            commonDir: URL(filePath: lines[1], directoryHint: .isDirectory),
            isBare: lines[2] == "true",
            isShallow: lines[3] == "true",
            hooksDir: URL(filePath: lines[4], directoryHint: .isDirectory)
        )
    }
}

public enum HookReader {
    public static let knownHooks = ["applypatch-msg", "pre-applypatch", "post-applypatch", "pre-commit", "pre-merge-commit", "prepare-commit-msg", "commit-msg", "post-commit", "pre-rebase", "post-checkout", "post-merge", "pre-push", "pre-receive", "update", "post-receive", "post-update", "reference-transaction", "push-to-checkout", "pre-auto-gc", "post-rewrite", "sendemail-validate", "fsmonitor-watchman", "post-index-change"]

    public static func read(_ directory: URL, fileManager: FileManager = .default) -> [Hook] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) else { return [] }
        return names.filter { !$0.hasSuffix(".sample") && !$0.hasPrefix(".") }.sorted().compactMap { name in
            let path = directory.appending(path: name).path(percentEncoded: false)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else { return nil }
            return Hook(name: name, path: path, enabled: fileManager.isExecutableFile(atPath: path))
        }
    }
}

public enum RepoStateReader {
    public static func read(gitDir: URL, head: Head, hasConflicts: Bool, fileManager: FileManager = .default) -> RepoState {
        func path(_ name: String) -> String { gitDir.appending(path: name).path(percentEncoded: false) }
        func exists(_ name: String) -> Bool { fileManager.fileExists(atPath: path(name)) }
        func text(_ name: String) -> String? {
            (try? String(contentsOfFile: path(name), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func number(_ name: String) -> Int? { text(name).flatMap { Int($0) } }
        func oid(_ name: String) -> OID? { text(name).flatMap { OID(String($0.prefix { !$0.isWhitespace })) } }

        if exists("rebase-merge") {
            let stopped = oid("rebase-merge/stopped-sha")
            let reason: RepoState.StopReason = hasConflicts ? .conflict : (exists("rebase-merge/amend") ? .edit : .other)
            let branch = text("rebase-merge/head-name").map { $0.hasPrefix("refs/heads/") ? String($0.dropFirst("refs/heads/".count)) : $0 }
            return .rebasing(step: number("rebase-merge/msgnum") ?? 0, total: number("rebase-merge/end") ?? 0, stoppedAt: stopped, reason: reason, branch: branch, onto: oid("rebase-merge/onto"))
        }
        if exists("rebase-apply") {
            if exists("rebase-apply/applying") {
                return .applyingPatches(step: number("rebase-apply/next") ?? 0, total: number("rebase-apply/last") ?? 0)
            }
            let branch = text("rebase-apply/head-name").map { $0.hasPrefix("refs/heads/") ? String($0.dropFirst("refs/heads/".count)) : $0 }
            return .rebasing(step: number("rebase-apply/next") ?? 0, total: number("rebase-apply/last") ?? 0, stoppedAt: oid("rebase-apply/original-commit"), reason: hasConflicts ? .conflict : .other, branch: branch, onto: oid("rebase-apply/onto"))
        }
        if exists("MERGE_HEAD") {
            let message = text("MERGE_MSG") ?? ""
            let source = message.firstMatch(of: #/^Merge (?:remote-tracking )?(?:branch|tag|commit) '([^']+)'/#).map { String($0.output.1) }
            return .merging(source: source ?? oid("MERGE_HEAD")?.short)
        }
        if exists("CHERRY_PICK_HEAD") { return .cherryPicking(oid("CHERRY_PICK_HEAD")) }
        if exists("REVERT_HEAD") { return .reverting(oid("REVERT_HEAD")) }
        if exists("sequencer/todo") {
            let first = text("sequencer/todo")?.split(separator: "\n").first.map(String.init) ?? ""
            if first.hasPrefix("revert") { return .reverting(nil) }
            return .cherryPicking(nil)
        }
        if exists("BISECT_START") || exists("BISECT_LOG") {
            if case .detached(let current) = head { return .bisecting(good: [], bad: nil, current: current, remaining: nil) }
            return .bisecting(good: [], bad: nil, current: nil, remaining: nil)
        }
        if case .detached(let id) = head { return .detached(id, nearestTag: nil) }
        return .clean
    }

    public static func bisectVars(_ data: Data) -> (current: OID?, remaining: Int?) {
        var current: OID?
        var remaining: Int?
        for line in ParseSupport.string(data).split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "'"))
            if parts[0] == "bisect_rev" { current = OID(value) }
            if parts[0] == "bisect_nr" { remaining = Int(value) }
        }
        return (current, remaining)
    }
}
