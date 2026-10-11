import Foundation

public enum WorktreeCapture {
    public struct Captured: Sendable, Hashable {
        public var stash: OID
        public var changes: Int
    }

    public static func capture(_ process: GitProcess, message: String) async throws -> Captured? {
        let status = StatusParser.parse(try await process.run(.read(["status", "--porcelain=v2", "-z", "--untracked-files=all"]), background: true).stdout)
        guard !status.files.isEmpty || !status.conflicts.isEmpty else { return nil }
        let head = try await process.runAllowingFailure(.read(["rev-parse", "-q", "--verify", "HEAD"]), background: true)
        guard head.succeeded, let headOID = OID(trimmed(head.output)) else { return nil }
        let created = try await process.runAllowingFailure(.write(["stash", "create", message]), background: true)
        var stash = created.succeeded ? OID(trimmed(created.output)) : nil
        let untracked = ParseSupport.nulFields(try await process.run(.read(["ls-files", "-z", "--others", "--exclude-standard"]), background: true).stdout).filter { !$0.isEmpty }
        guard stash != nil || !untracked.isEmpty else { return nil }
        let headTree = headOID.rawValue + "^{tree}"
        if stash == nil {
            let index = try await commitTree(process, tree: headTree, parents: [headOID], message: "index on " + message)
            stash = try await commitTree(process, tree: headTree, parents: [headOID, index], message: message)
        }
        guard let base = stash else { return nil }
        guard !untracked.isEmpty else { return Captured(stash: base, changes: status.files.count) }
        let indexFile = FileManager.default.temporaryDirectory.appending(path: "vrai-untracked-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: indexFile) }
        let environment = ["GIT_INDEX_FILE": indexFile.path(percentEncoded: false)]
        let list = Data((untracked.joined(separator: "\u{0}") + "\u{0}").utf8)
        try await process.run(GitCommand(["update-index", "--add", "-z", "--stdin"], stdin: list, access: .write, environment: environment), background: true)
        let untrackedTree = trimmed(try await process.run(GitCommand(["write-tree"], access: .write, environment: environment), background: true).output)
        let untrackedCommit = try await commitTree(process, tree: untrackedTree, parents: [], message: "untracked files on " + message)
        let parents = trimmed(try await process.run(.read(["rev-list", "--parents", "-n", "1", base.rawValue]), background: true).output).split(separator: " ").dropFirst().compactMap { OID(String($0)) }
        guard parents.count >= 2 else { return Captured(stash: base, changes: status.files.count) }
        let full = try await commitTree(process, tree: base.rawValue + "^{tree}", parents: Array(parents.prefix(2)) + [untrackedCommit], message: message)
        return Captured(stash: full, changes: status.files.count)
    }

    static func commitTree(_ process: GitProcess, tree: String, parents: [OID], message: String) async throws -> OID {
        var arguments = ["commit-tree", "--no-gpg-sign", "-m", message]
        for parent in parents { arguments += ["-p", parent.rawValue] }
        arguments.append(tree)
        var command = GitCommand.write(arguments)
        command.environment = UndoStore.identity
        let output = try await process.run(command, background: true).output
        guard let oid = OID(trimmed(output)) else { throw GitError(.unknown(exit: 0, stderr: output)) }
        return oid
    }

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
