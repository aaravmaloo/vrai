import Foundation
import Testing
@testable import VraiGit

struct ScratchRepository {
    let root: URL
    let git: GitProcess

    static func make() async throws -> ScratchRepository {
        let root = TestSandbox.root.appending(path: "tests/\(UUID().uuidString)/repo", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let git = GitProcess(executable: try GitExecutable.discover(), workingDirectory: root, environment: TestSandbox.environment)
        let repository = ScratchRepository(root: root, git: git)
        try await repository.run(["init", "-q", "--initial-branch=main"])
        return repository
    }

    func url(_ path: String) -> URL { root.appending(path: path) }

    func write(_ path: String, _ data: Data?) throws {
        let target = url(path)
        if let data {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target)
        } else if FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: target)
        }
    }

    func write(_ path: String, _ text: String) throws {
        try write(path, Data(text.utf8))
    }

    func read(_ path: String) -> Data? {
        try? Data(contentsOf: url(path))
    }

    @discardableResult
    func run(_ arguments: [String], stdin: Data? = nil) async throws -> String {
        try await git.run(.write(arguments, stdin: stdin)).output
    }

    func runAllowingFailure(_ arguments: [String], stdin: Data? = nil) async throws -> GitResult {
        try await git.runAllowingFailure(.write(arguments, stdin: stdin))
    }

    func indexContent(_ path: String) async throws -> Data? {
        let listed = try await git.run(.read(["ls-files", "-z", "--", path])).stdout
        guard !listed.isEmpty else { return nil }
        return try await git.run(.read(["cat-file", "blob", ":" + path])).stdout
    }

    func commitAll(_ message: String) async throws {
        try await run(["add", "-A"])
        try await run(["commit", "-q", "--allow-empty", "-m", message])
    }
}
