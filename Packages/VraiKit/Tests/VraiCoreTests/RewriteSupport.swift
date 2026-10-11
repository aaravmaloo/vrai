import Foundation
import Synchronization
import Testing
@testable import VraiCore
@testable import VraiGit

final class CommandLog: Sendable {
    private let storage = Mutex<[String]>([])

    func append(_ entry: ConsoleEntry) {
        storage.withLock { $0.append(entry.command) }
    }

    var commands: [String] { storage.withLock { $0 } }
}

enum EditorBuild {
    static let path: String? = compile()

    static var source: URL {
        var url = URL(filePath: #filePath)
        for _ in 0..<5 { url = url.deletingLastPathComponent() }
        return url.appending(path: "Helpers/vrai-editor/main.swift")
    }

    static func compile() -> String? {
        let directory = Sandbox.root.appending(path: "bin/" + UUID().uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appending(path: EditorHelper.name)
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xcrun")
        process.arguments = [
            "swiftc", "-swift-version", "6", "-warnings-as-errors",
            "-module-cache-path", Sandbox.root.appending(path: "module-cache").path(percentEncoded: false),
            source.path(percentEncoded: false), "-o", output.path(percentEncoded: false)
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: directory) }
        guard process.terminationStatus == 0 else { return nil }
        let installed = Sandbox.root.appending(path: "bin/" + EditorHelper.name).path(percentEncoded: false)
        return rename(output.path(percentEncoded: false), installed) == 0 ? installed : nil
    }
}

struct Scratch: Sendable {
    let root: URL
    let repository: URL
    let log = CommandLog()

    static func copy(_ scenario: String, repository name: String = "vrai") async throws -> Scratch {
        let source = Sandbox.root.appending(path: "fixtures/" + scenario, directoryHint: .isDirectory)
        let root = Sandbox.root.appending(path: "tests/" + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: root)
        let scratch = Scratch(root: root, repository: root.appending(path: name, directoryHint: .isDirectory))
        let worktrees = ["vrai-release", "vrai-review"].map { root.appending(path: $0).path(percentEncoded: false) }.filter { FileManager.default.fileExists(atPath: $0) }
        if !worktrees.isEmpty { _ = try await scratch.git(["worktree", "repair"] + worktrees) }
        for remote in try await scratch.git(["remote"]).split(separator: "\n").map(String.init) {
            let bare = root.appending(path: "remotes/\(remote).git", directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: bare.path(percentEncoded: false)) {
                _ = try await scratch.git(["remote", "set-url", remote, bare.absoluteString])
            }
        }
        return scratch
    }

    var process: GitProcess {
        get throws {
            GitProcess(executable: try GitExecutable.discover(), workingDirectory: repository, environment: .sandbox(root: Sandbox.root))
        }
    }

    @discardableResult
    func git(_ arguments: [String], stdin: Data? = nil) async throws -> String {
        try await process.run(GitCommand(arguments, stdin: stdin, access: .write)).output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func result(_ arguments: [String]) async throws -> GitResult {
        try await process.runAllowingFailure(GitCommand(arguments, access: .write))
    }

    func oid(_ revision: String) async throws -> OID {
        let text = try await git(["rev-parse", "--verify", revision + "^{commit}"])
        guard let oid = OID(text) else { throw GitError(.refNotFound) }
        return oid
    }

    func clean() async throws {
        try await git(["reset", "-q", "--hard"])
        try await git(["clean", "-q", "-fd"])
    }

    func file(_ path: String) throws -> String {
        try String(contentsOf: repository.appending(path: path), encoding: .utf8)
    }

    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: repository.appending(path: relative).path(percentEncoded: false))
    }

    func gitDir() async throws -> URL {
        URL(filePath: try await git(["rev-parse", "--absolute-git-dir"]), directoryHint: .isDirectory)
    }

    @MainActor
    func store() throws -> RepositoryStore {
        var environment = GitEnvironment.sandbox(root: Sandbox.root)
        if let helper = EditorBuild.path { environment.base[EditorHelper.environmentKey] = helper }
        let log = self.log
        let process = GitProcess(executable: try GitExecutable.discover(), workingDirectory: repository, environment: environment) { log.append($0) }
        return RepositoryStore(git: process)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

extension RepositoryStore {
    var recorded: [UndoEntry] {
        get async { await undo.entries }
    }
}
