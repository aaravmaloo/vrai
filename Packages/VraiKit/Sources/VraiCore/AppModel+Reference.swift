import Foundation
import VraiGit

extension AppModel {
    public static let referenceCommands = ["rebase", "reset", "reflog", "bisect", "worktree", "cherry-pick"]

    public func manualCommand(for command: String) -> GitCommand {
        LongTailCommands.manual(command)
    }

    public func bugReportCommand(to directory: URL) -> GitCommand {
        LongTailCommands.bugReport(to: directory.path(percentEncoded: false))
    }

    @discardableResult
    public func bugReport(to directory: URL, note: String = "") async throws -> [URL] {
        let git = try neutralProcess()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? [])
        try await git.run(bugReportCommand(to: directory))
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            try Data((trimmed + "\n").utf8).write(to: directory.appending(path: "what-happened.txt"), options: .atomic)
        }
        let after = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        return after.filter { !before.contains($0) }.sorted().map { directory.appending(path: $0) }
    }

    public func manual(for command: String) async throws -> [[ManualSpan]] {
        let git = try neutralProcess()
        let result = try await git.run(manualCommand(for: command), background: true)
        var lines = LongTailParsers.manual(result.stdout)
        while let last = lines.last, last.allSatisfy({ $0.text.trimmingCharacters(in: .whitespaces).isEmpty }) { lines.removeLast() }
        guard !lines.isEmpty else { throw GitError(.unknown(exit: result.exitCode, stderr: result.errorOutput)) }
        return lines
    }
}
