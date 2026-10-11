import Foundation
import VraiGit

public enum OpenInspection: Sendable, Hashable {
    case repository(RepositoryReference)
    case notARepository(URL)
    case missing(URL)
}

public struct FoundRepository: Sendable, Hashable, Identifiable {
    public var url: URL
    public var detail: String
    public var isWorktree: Bool

    public var id: String { url.path(percentEncoded: false) }
}

public struct RecentStatus: Sendable, Hashable {
    public var branch: String?
    public var detached: Bool
    public var changes: Int
    public var ahead: Int
    public var behind: Int
    public var missing: Bool
    public var empty: Bool
    public var tag: String?

    public static let missingFolder = RecentStatus(branch: nil, detached: false, changes: 0, ahead: 0, behind: 0, missing: true, empty: false)
}

extension AppModel {
    public func inspect(path: String) async -> OpenInspection {
        let url = expandingTilde(path).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory), isDirectory.boolValue else { return .missing(url) }
        guard let git = try? process(at: url), let result = try? await git.runAllowingFailure(.read(["rev-parse", "--show-toplevel"]), background: true), result.exitCode == 0 else {
            return .notARepository(url)
        }
        let top = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !top.isEmpty else { return .notARepository(url) }
        return .repository(RepositoryReference(url: URL(filePath: top, directoryHint: .isDirectory)))
    }

    public func defaultBranchName() async -> String {
        guard let git = try? neutralProcess(), let result = try? await git.runAllowingFailure(.read(["config", "--get", "init.defaultBranch"], acceptedExitCodes: [0, 1]), background: true) else { return "main" }
        let name = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "main" : name
    }

    public func isValidBranchName(_ name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let git = try? neutralProcess(), let result = try? await git.runAllowingFailure(LongTailCommands.checkRefFormat(branch: trimmed), background: true) else { return false }
        return result.exitCode == 0
    }

    public func initCommand(at folder: URL, initialBranch: String?) -> GitCommand {
        LongTailCommands.initRepository(at: folder.path(percentEncoded: false).trimmingTrailingSlashes(), initialBranch: initialBranch)
    }

    @discardableResult
    public func initRepository(at folder: URL, initialBranch: String? = nil, gitignoreTemplate: GitignoreTemplate = .none, readme: Bool = false) async throws -> RepositoryReference {
        let target = folder.standardizedFileURL
        let parent = target.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let git = try process(at: parent)
        try await git.run(initCommand(at: target, initialBranch: initialBranch))
        if let contents = gitignoreTemplate.contents {
            let file = target.appending(path: TextFileKind.gitignore.fileName)
            if !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                try Data(contents.utf8).write(to: file, options: .atomic)
            }
        }
        if readme {
            let file = target.appending(path: "README.md")
            if !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                try Data(("# " + target.lastPathComponent + "\n").utf8).write(to: file, options: .atomic)
            }
        }
        let reference = RepositoryReference(url: target)
        noteOpened(reference)
        request(reference)
        return reference
    }

    public func nearbyRepositories(in folder: URL, limit: Int = 12) async -> [FoundRepository] {
        let children = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var found: [FoundRepository] = []
        for child in children {
            let marker = child.appending(path: ".git")
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: marker.path(percentEncoded: false), isDirectory: &isDirectory) else { continue }
            let status = await recentStatus(at: child)
            found.append(FoundRepository(url: child, detail: Self.describe(status), isWorktree: !isDirectory.boolValue))
            if found.count >= limit { break }
        }
        return found
    }

    static func describe(_ status: RecentStatus) -> String {
        if status.empty { return String(localized: "New, no commits yet", bundle: .module) }
        let branch = status.branch ?? String(localized: "detached HEAD", bundle: .module)
        if status.changes > 0 { return String(localized: "\(n(status.changes, "change")) on \(branch)", bundle: .module) }
        return String(localized: "Clean, on \(branch)", bundle: .module)
    }

    public func recentStatus(at url: URL) async -> RecentStatus {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)), let git = try? process(at: url),
              let result = try? await git.runAllowingFailure(StatusParser.command, background: true), result.exitCode == 0 else {
            return .missingFolder
        }
        let report = StatusParser.parse(result.stdout)
        var status = RecentStatus(branch: report.branch, detached: report.branch == nil, changes: report.files.count + report.conflicts.count, ahead: report.ahead, behind: report.behind, missing: false, empty: report.isInitial)
        if status.detached, !status.empty, let described = try? await git.runAllowingFailure(SharedCommands.exactTag(), background: true), described.exitCode == 0 {
            let tag = described.output.trimmingCharacters(in: .whitespacesAndNewlines)
            status.tag = tag.isEmpty ? nil : tag
        }
        return status
    }

    public func recentStatuses() async -> [String: RecentStatus] {
        var out: [String: RecentStatus] = [:]
        for recent in recents {
            out[recent.path] = await recentStatus(at: URL(filePath: recent.path, directoryHint: .isDirectory))
        }
        return out
    }

    public var gitProblem: GitError? {
        if gitExecutable == nil { return gitError ?? GitError(.gitNotFound) }
        return nil
    }

    public func installCommandLineTools() {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xcode-select")
        process.arguments = ["--install"]
        try? process.run()
    }
}
