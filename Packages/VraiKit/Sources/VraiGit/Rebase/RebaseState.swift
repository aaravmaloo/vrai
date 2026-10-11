import Foundation

public enum OperationInProgress: String, Sendable, Hashable, CaseIterable {
    case merge
    case rebase
    case applyingPatches
    case cherryPick
    case revert
    case bisect

    public static func current(gitDir: URL, fileManager: FileManager = .default) -> OperationInProgress? {
        func exists(_ name: String) -> Bool { fileManager.fileExists(atPath: gitDir.appending(path: name).path(percentEncoded: false)) }
        if exists("rebase-merge") { return .rebase }
        if exists("rebase-apply") { return exists("rebase-apply/applying") ? .applyingPatches : .rebase }
        if exists("MERGE_HEAD") { return .merge }
        if exists("CHERRY_PICK_HEAD") { return .cherryPick }
        if exists("REVERT_HEAD") { return .revert }
        if exists("sequencer/todo") {
            let todo = (try? String(contentsOf: gitDir.appending(path: "sequencer/todo"), encoding: .utf8)) ?? ""
            let first = todo.split(separator: "\n").first { !$0.hasPrefix("#") } ?? ""
            return first.hasPrefix("revert") ? .revert : .cherryPick
        }
        if exists("BISECT_START") || exists("BISECT_LOG") { return .bisect }
        return nil
    }
}

public struct RebaseState: Sendable, Hashable {
    public var headName: String?
    public var origHead: OID?
    public var onto: OID?
    public var updatedRefs: [String: OID]

    public var refsBefore: [String: OID] {
        var refs = updatedRefs
        if let headName, let origHead { refs[headName] = origHead }
        if headName == nil, let origHead { refs["HEAD"] = origHead }
        return refs
    }

    public var head: String? {
        headName ?? origHead?.rawValue
    }

    public static func read(gitDir: URL) -> RebaseState? {
        for folder in ["rebase-merge", "rebase-apply"] {
            let directory = gitDir.appending(path: folder, directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { continue }
            func text(_ name: String) -> String? {
                (try? String(contentsOf: directory.appending(path: name), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let name = text("head-name").flatMap { $0.hasPrefix("refs/") ? $0 : nil }
            return RebaseState(
                headName: name,
                origHead: text("orig-head").flatMap(OID.init),
                onto: text("onto").flatMap(OID.init),
                updatedRefs: parseUpdateRefs(text("update-refs") ?? "")
            )
        }
        return nil
    }

    public static func parseUpdateRefs(_ text: String) -> [String: OID] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        var refs: [String: OID] = [:]
        var index = 0
        while index + 1 < lines.count {
            if lines[index].hasPrefix("refs/"), let before = OID(lines[index + 1]), !before.isZero {
                refs[lines[index]] = before
                index += 3
            } else {
                index += 1
            }
        }
        return refs
    }

    public static func sequencerHead(gitDir: URL) -> OID? {
        let url = gitDir.appending(path: "sequencer/head")
        return (try? String(contentsOf: url, encoding: .utf8)).flatMap { OID($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}
