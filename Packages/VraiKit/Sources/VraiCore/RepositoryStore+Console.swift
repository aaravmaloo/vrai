import Foundation
import VraiGit

public enum ConsoleCommands {
    public static func showObject(_ id: String) -> GitCommand {
        .read(["cat-file", "-p", id])
    }

    public static func addNote(_ id: String, message: String, replacing: Bool = false) -> GitCommand {
        .write(["notes", "add"] + (replacing ? ["-f"] : []) + ["-m", message, id])
    }

    public static func removeNote(_ id: String) -> GitCommand {
        .write(["notes", "remove", id])
    }

    public static func note(_ id: String) -> GitCommand {
        .read(["notes", "show", id], acceptedExitCodes: [0, 1])
    }

    public static let trackedFiles = GitCommand.read(["ls-files", "-z"])

    public static func grep(_ text: String, at revision: String? = nil, perFile: Int = 5) -> GitCommand {
        var arguments = ["grep", "-n", "-z", "-I", "-F", "-i", "--no-color", "--max-count=\(perFile)", "-e", text]
        if let revision { arguments.append(revision) }
        arguments.append("--")
        return .read(arguments, acceptedExitCodes: [0, 1])
    }

    public static func searchCommits(_ text: String, scope: [String], limit: Int) -> GitCommand {
        .read(LogParser.historyArguments(scope: scope, limit: limit, extra: ["-i", "-F", "--grep=" + text]))
    }

    public static func resolveCommit(_ text: String) -> GitCommand {
        .read(["rev-parse", "--verify", "--quiet", text.hasPrefix(":/") ? text : text + "^{commit}"], acceptedExitCodes: [0, 1, 128])
    }

    public static func commit(_ id: OID) -> GitCommand {
        .read(LogParser.historyArguments(scope: [id.rawValue], limit: 1, extra: ["--no-walk"]))
    }

    public static let recentCheckouts = GitCommand.read(["log", "-g", "-z", "--format=%gs", "-n", "300", "HEAD", "--"], acceptedExitCodes: [0, 128])
}

extension RepositoryStore {
    public func run(typed text: String) async throws -> TypedRun {
        guard let typed = TypedCommand(text) else { throw GitError(.unknown(exit: -1, stderr: text)) }
        return try await run(typed)
    }

    public func run(_ typed: TypedCommand) async throws -> TypedRun {
        console.remember(typed.display)
        let marker = console.begin(typed.display, source: .you)
        defer { console.end(marker) }
        let result = try await perform("console", refresh: typed.changesRepository) {
            try await git.runAllowingFailure(typed.command, source: .you)
        }
        let entry = console.entry(for: result)
        var spilled: URL?
        if let entry {
            console.setExpanded(entry.id, true)
            spilled = console.spill(result, for: entry.id)
        }
        return TypedRun(typed: typed, result: result, entryID: entry?.id, fullOutput: spilled)
    }

    @discardableResult
    public func showObject(id: OID) async throws -> GitResult {
        let result = try await git.run(ConsoleCommands.showObject(id.rawValue))
        if let entry = console.entry(for: result) { console.setExpanded(entry.id, true) }
        return result
    }

    public func addNote(id: OID, message: String, replacing: Bool = false) async throws {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw GitError(.emptyMessage) }
        try await perform("note", refresh: false) {
            _ = try await git.run(ConsoleCommands.addNote(id.rawValue, message: text, replacing: replacing))
        }
    }

    public func removeNote(id: OID) async throws {
        try await perform("note", refresh: false) {
            _ = try await git.run(ConsoleCommands.removeNote(id.rawValue))
        }
    }

    public func note(id: OID) async -> String? {
        guard let result = try? await git.run(ConsoleCommands.note(id.rawValue), background: true), result.exitCode == 0 else { return nil }
        let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    public func trackedFiles() async throws -> [String] {
        let data = try await git.run(ConsoleCommands.trackedFiles, background: true).stdout
        return ParseSupportBridge.nulFields(data).filter { !$0.isEmpty }
    }

    public func grep(text: String, at revision: String? = nil, limit: Int = 200) async throws -> [GrepMatch] {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let result = try await git.run(ConsoleCommands.grep(needle, at: revision), background: true)
        return GrepMatch.parse(result.stdout, revision: revision, limit: limit)
    }

    public func searchCommits(_ text: String, limit: Int = 20) async throws -> [Commit] {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, let snapshot else { return [] }
        var found: [Commit] = []
        if Self.looksLikeRange(needle) {
            let range = try await git.run(.read(LogParser.historyArguments(scope: [needle], limit: limit), acceptedExitCodes: [0, 128]), background: true)
            if range.exitCode == 0 { found.append(contentsOf: LogParser.history(range.stdout)) }
        } else if Self.looksLikeRevision(needle) {
            let resolved = try await git.run(ConsoleCommands.resolveCommit(needle), background: true)
            if resolved.exitCode == 0, let id = OID(resolved.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                let data = try await git.run(ConsoleCommands.commit(id), background: true).stdout
                found.append(contentsOf: LogParser.history(data))
            }
        }
        var scope = ["--branches", "--remotes", "--tags"]
        if snapshot.headOID != nil { scope.append("HEAD") }
        let data = try await git.run(ConsoleCommands.searchCommits(needle, scope: scope, limit: limit), background: true).stdout
        for commit in LogParser.history(data) where !found.contains(where: { $0.id == commit.id }) {
            found.append(commit)
        }
        return Array(found.prefix(limit))
    }

    public nonisolated static func looksLikeRevision(_ text: String) -> Bool {
        guard !text.contains(where: \.isWhitespace), !text.hasPrefix("-") else { return false }
        if text.count >= 4, text.count <= 64, text.allSatisfy(\.isHexDigit) { return true }
        return text.contains("~") || text.contains("^") || text.contains("@{") || text.hasPrefix(":/") || text == "HEAD" || text.hasPrefix("HEAD")
    }

    public nonisolated static func looksLikeRange(_ text: String) -> Bool {
        guard !text.contains(where: \.isWhitespace), !text.hasPrefix("-") else { return false }
        return text.contains("..")
    }

    public func recentBranches() async -> [String] {
        guard let snapshot else { return [] }
        let names = Set(snapshot.branches.map(\.name))
        var out: [String] = []
        func add(_ name: String) {
            if names.contains(name), !out.contains(name) { out.append(name) }
        }
        if let current = snapshot.head.branchName { add(current) }
        if let result = try? await git.run(ConsoleCommands.recentCheckouts, background: true), result.exitCode == 0 {
            for line in ParseSupportBridge.nulFields(result.stdout) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let match = trimmed.wholeMatch(of: /checkout: moving from (\S+) to (\S+)/) else { continue }
                add(String(match.output.2))
                add(String(match.output.1))
            }
        }
        for name in names.sorted() { add(name) }
        return out
    }
}
