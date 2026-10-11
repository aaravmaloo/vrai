import Foundation
import VraiGit

public struct CloneRequest: Sendable, Hashable {
    public var url: String
    public var destination: URL
    public var branch: String?
    public var history: CloneHistory
    public var recurseSubmodules: Bool
    public var bare: Bool
    public var mirror: Bool
    public var scalar: Bool
    public var maintenance: Bool

    public init(url: String, destination: URL, branch: String? = nil, history: CloneHistory = .full, recurseSubmodules: Bool = true, bare: Bool = false, mirror: Bool = false, scalar: Bool = false, maintenance: Bool = true) {
        self.url = url
        self.destination = destination
        self.branch = branch
        self.history = history
        self.recurseSubmodules = recurseSubmodules
        self.bare = bare
        self.mirror = mirror
        self.scalar = scalar
        self.maintenance = maintenance
    }

    public var isBundle: Bool { AppModel.isBundlePath(url) }
    public var opensWindow: Bool { !bare && !mirror }

    public var command: GitCommand {
        let path = destination.path(percentEncoded: false)
        if scalar { return LongTailCommands.scalarClone(url: url, to: path, branch: branch, maintenance: maintenance) }
        return LongTailCommands.clone(url: url, to: path, branch: branch, history: isBundle ? .full : history, recurseSubmodules: recurseSubmodules, bare: bare, mirror: mirror)
    }

    public var repositoryURL: URL {
        scalar ? destination.appending(path: "src", directoryHint: .isDirectory) : destination
    }
}

public struct CloneHandle: Sendable {
    public let progress: AsyncStream<CloneProgress>
    public let task: Task<RepositoryReference, any Error>

    public func cancel() { task.cancel() }

    public var value: RepositoryReference {
        get async throws { try await task.value }
    }
}

extension AppModel {
    public nonisolated static func isBundlePath(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix(".bundle") && (trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || trimmed.hasPrefix("file://"))
    }

    public nonisolated static func isCloneURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }) else { return false }
        if isBundlePath(trimmed) { return true }
        if trimmed.wholeMatch(of: /[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:[A-Za-z0-9._~\/-]+/) != nil { return true }
        if trimmed.wholeMatch(of: /(?:https?|ssh|git):\/\/[A-Za-z0-9.@:_-]+\/[A-Za-z0-9._~\/-]+/) != nil { return true }
        if trimmed.wholeMatch(of: /file:\/\/\/.+/) != nil { return true }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") { return trimmed.count > 2 }
        return false
    }

    public nonisolated static func repositoryName(fromURL text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        let last = trimmed.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? ""
        var name = last
        for suffix in [".git", ".bundle"] where name.hasSuffix(suffix) { name.removeLast(suffix.count) }
        return name.isEmpty ? "repository" : name
    }

    public func expandingTilde(_ path: String, directory: Bool = true) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let hint: URL.DirectoryHint = directory ? .isDirectory : .notDirectory
        if trimmed == "~" { return homeFolder }
        if trimmed.hasPrefix("~/") { return homeFolder.appending(path: String(trimmed.dropFirst(2)), directoryHint: hint) }
        if trimmed.hasPrefix("file://"), let url = URL(string: trimmed) { return url }
        return URL(filePath: trimmed, directoryHint: hint)
    }

    public var homeFolder: URL {
        if let sandbox = launch.sandbox { return sandbox.appending(path: "home", directoryHint: .isDirectory) }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public var developerFolder: URL { homeFolder.appending(path: "Developer", directoryHint: .isDirectory) }
    public var desktopFolder: URL { homeFolder.appending(path: "Desktop", directoryHint: .isDirectory) }
    public var downloadsFolder: URL { homeFolder.appending(path: "Downloads", directoryHint: .isDirectory) }

    public func displayPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        let home = homeFolder.standardizedFileURL.path(percentEncoded: false).trimmingTrailingSlashes()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    func neutralProcess() throws -> GitProcess {
        let folder = homeFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try process(at: folder)
    }

    public func remoteHeads(url: String) async throws -> RemoteHeads {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let git = try neutralProcess()
        if Self.isBundlePath(trimmed) {
            let file = expandingTilde(trimmed, directory: false).path(percentEncoded: false)
            return LongTailParsers.remoteHeads(try await git.run(LongTailCommands.bundleListHeads(file: file), background: true).output)
        }
        return LongTailParsers.remoteHeads(try await git.run(LongTailCommands.lsRemote(url: trimmed), background: true).output)
    }

    public func cloneCommand(_ request: CloneRequest) -> GitCommand {
        request.command
    }

    public func startClone(_ request: CloneRequest) -> CloneHandle {
        let (stream, continuation) = AsyncStream.makeStream(of: CloneProgress.self, bufferingPolicy: .bufferingNewest(512))
        let destination = request.destination.standardizedFileURL
        let parent = destination.deletingLastPathComponent()
        let existed = FileManager.default.fileExists(atPath: destination.path(percentEncoded: false))
        let task = Task { @MainActor () throws -> RepositoryReference in
            defer { continuation.finish() }
            do {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            } catch {
                throw GitError(.pathExists)
            }
            let git = try self.process(at: parent)
            continuation.yield(CloneProgress(stage: .connecting, phase: String(localized: "Connecting", bundle: .module)))
            let parser = CloneLineParser(destination: destination.path(percentEncoded: false))
            let forward: @Sendable (String) -> Void = { line in
                if let progress = parser.consume(line) { continuation.yield(progress) }
            }
            do {
                if request.scalar {
                    _ = try await git.runScalar(request.command, progress: forward)
                } else {
                    _ = try await git.run(request.command, progress: forward)
                }
            } catch {
                if !existed { try? FileManager.default.removeItem(at: destination) }
                throw error
            }
            let reference = RepositoryReference(url: request.repositoryURL)
            if request.opensWindow {
                self.noteOpened(reference)
                self.request(reference)
            }
            continuation.yield(CloneProgress(stage: .finished, phase: String(localized: "Done", bundle: .module), fraction: 1))
            return reference
        }
        continuation.onTermination = { termination in
            if case .cancelled = termination { task.cancel() }
        }
        return CloneHandle(progress: stream, task: task)
    }

    public func clone(url: String, to destination: URL, branch: String? = nil, depth: Int? = nil, filter: String? = nil, recurseSubmodules: Bool = true, bare: Bool = false, mirror: Bool = false, bundle: URL? = nil) -> AsyncStream<CloneProgress> {
        var history = CloneHistory.full
        if let depth { history = .shallow(depth: depth) } else if filter == "tree:0" { history = .treeless } else if filter != nil { history = .blobless }
        let source = bundle?.path(percentEncoded: false) ?? url
        let handle = startClone(CloneRequest(url: source, destination: destination, branch: branch, history: history, recurseSubmodules: recurseSubmodules, bare: bare, mirror: mirror))
        let (stream, continuation) = AsyncStream.makeStream(of: CloneProgress.self)
        let relay = Task {
            for await progress in handle.progress { continuation.yield(progress) }
            continuation.finish()
        }
        continuation.onTermination = { termination in
            if case .cancelled = termination {
                handle.cancel()
                relay.cancel()
            }
        }
        return stream
    }
}

final class CloneLineParser: @unchecked Sendable {
    private let lock = NSLock()
    private var parser: CloneProgressParser

    init(destination: String) {
        parser = CloneProgressParser(destination: destination)
    }

    func consume(_ line: String) -> CloneProgress? {
        lock.withLock { parser.consume(line) }
    }
}
