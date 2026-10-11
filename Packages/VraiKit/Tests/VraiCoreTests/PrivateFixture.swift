import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
struct PrivateFixture {
    let repo: URL
    let store: RepositoryStore

    var git: GitProcess { store.git }

    static func copy(_ scenario: String, _ repository: String) async throws -> PrivateFixture {
        let base = Sandbox.root.appending(path: "tests/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let source = Sandbox.root.appending(path: "fixtures/\(scenario)", directoryHint: .isDirectory)
        let target = base.appending(path: scenario, directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: source, to: target)
        let repo = target.appending(path: repository, directoryHint: .isDirectory)
        let git = try Sandbox.git(at: repo)
        let oldPrefix = source.path(percentEncoded: false).trimmingSuffix("/")
        let newPrefix = target.path(percentEncoded: false).trimmingSuffix("/")
        for name in try await git.run(.read(["remote"])).output.split(separator: "\n") {
            let url = try await git.run(.read(["remote", "get-url", String(name)])).output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard url.contains(oldPrefix) else { continue }
            try await git.run(.write(["remote", "set-url", String(name), url.replacingOccurrences(of: oldPrefix, with: newPrefix)]))
        }
        let store = RepositoryStore(git: git)
        try await store.refresh()
        return PrivateFixture(repo: repo, store: store)
    }

    static func everyday() async throws -> PrivateFixture {
        try await copy("everyday", "vrai")
    }

    @discardableResult
    func run(_ arguments: [String], stdin: Data? = nil) async throws -> String {
        try await git.run(.write(arguments, stdin: stdin)).output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func output(_ arguments: [String]) async throws -> String {
        try await git.run(.read(arguments)).output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func head() async throws -> String {
        try await output(["rev-parse", "HEAD"])
    }

    func url(_ path: String) -> URL { repo.appending(path: path) }

    func write(_ path: String, _ data: Data) throws {
        try FileManager.default.createDirectory(at: url(path).deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url(path))
    }

    func write(_ path: String, _ text: String) throws {
        try write(path, Data(text.utf8))
    }

    func read(_ path: String) -> Data? {
        try? Data(contentsOf: url(path))
    }

    func exists(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url(path).path(percentEncoded: false))) != nil
    }

    func hash(_ path: String) async throws -> String {
        try await output(["hash-object", "--no-filters", "--", path])
    }

    func stagedDiff(_ path: String) async throws -> [String] {
        try await output(["diff", "--cached", "--no-color", "-U0", "--", path]).split(separator: "\n").map(String.init).filter {
            ($0.hasPrefix("+") || $0.hasPrefix("-")) && !$0.hasPrefix("+++") && !$0.hasPrefix("---")
        }
    }

    func status() async throws -> String {
        try await output(["status", "--porcelain=v1", "--untracked-files=all"])
    }
}

extension GitError {
    var hookName: String? {
        if case .hookFailed(let name, _) = code { return name }
        return nil
    }

    var hookOutput: String? {
        if case .hookFailed(_, let output) = code { return output }
        return nil
    }
}

@MainActor @discardableResult
func expectGitError(_ name: String, _ body: () async throws -> Void, sourceLocation: SourceLocation = #_sourceLocation) async -> GitError? {
    do {
        try await body()
        Issue.record("expected GitError.\(name)", sourceLocation: sourceLocation)
        return nil
    } catch let error as GitError {
        #expect(error.code.name == name, "\(error)", sourceLocation: sourceLocation)
        return error
    } catch {
        Issue.record("unexpected error \(error)", sourceLocation: sourceLocation)
        return nil
    }
}
