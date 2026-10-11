import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

struct SyncErrorRecorder {
    static let enabled = ProcessInfo.processInfo.environment["VRAI_RECORD"] == "1"
    static let folder = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../VraiGitTests/Fixtures/git/errors", directoryHint: .isDirectory).standardizedFileURL

    struct Case {
        var name: String
        var scenario: String
        var arguments: [String]
        var prepare: [[String]] = []
        var auth: AuthMode = .none
        var preReceive: String?
        var clean = false
    }

    enum AuthMode {
        case none
        case storedToken
        case noHelper
    }

    static let cases: [Case] = [
        Case(name: "sync-auth-fetch", scenario: "auth", arguments: ["fetch", "origin"], auth: .storedToken),
        Case(name: "sync-auth-no-credentials", scenario: "auth", arguments: ["push", "origin", "main"], auth: .noHelper),
        Case(name: "sync-offline-push", scenario: "offline", arguments: ["push", "origin", "feature/graph-renderer"]),
        Case(name: "sync-offline-pull", scenario: "offline", arguments: ["pull", "--no-rebase"]),
        Case(name: "sync-remote-not-found", scenario: "everyday", arguments: ["fetch", "nope"]),
        Case(name: "sync-no-such-remote", scenario: "everyday", arguments: ["remote", "remove", "nope"]),
        Case(name: "sync-push-non-fast-forward", scenario: "everyday", arguments: ["push", "origin", "HEAD:refs/heads/main"]),
        Case(name: "sync-push-stale-lease", scenario: "push-rejected", arguments: ["push", "--force-with-lease", "origin", "feature/graph-renderer"]),
        Case(name: "sync-protected-branch", scenario: "everyday", arguments: ["push", "--force", "origin", "HEAD:refs/heads/main"], preReceive: "#!/bin/sh\necho 'GH006: Protected branch update failed for refs/heads/main.' >&2\nexit 1\n"),
        Case(name: "sync-push-no-upstream", scenario: "everyday", arguments: ["push"], prepare: [["switch", "-q", "-c", "lonely"]]),
        Case(name: "sync-pull-no-upstream", scenario: "everyday", arguments: ["pull", "--no-rebase"], prepare: [["switch", "-q", "-c", "lonely"]]),
        Case(name: "sync-pull-detached", scenario: "detached", arguments: ["pull", "--no-rebase"]),
        Case(name: "sync-pull-diverged", scenario: "everyday", arguments: ["pull", "--ff-only"], clean: true),
        Case(name: "sync-pull-rebase-dirty", scenario: "everyday", arguments: ["pull", "--rebase"]),
        Case(name: "sync-switch-merge-staged", scenario: "everyday", arguments: ["switch", "--merge", "main"]),
        Case(name: "sync-tag-invalid", scenario: "everyday", arguments: ["tag", "bad..tag"]),
        Case(name: "sync-tag-exists", scenario: "everyday", arguments: ["tag", "v0.9.1"]),
        Case(name: "sync-tag-not-found", scenario: "everyday", arguments: ["tag", "-d", "nope"]),
        Case(name: "sync-delete-current", scenario: "everyday", arguments: ["branch", "-D", "feature/graph-renderer"]),
        Case(name: "sync-delete-elsewhere", scenario: "everyday", arguments: ["branch", "-D", "release/0.9"]),
        Case(name: "sync-rename-missing", scenario: "everyday", arguments: ["branch", "-m", "nope", "other"]),
        Case(name: "sync-upstream-missing", scenario: "everyday", arguments: ["branch", "--set-upstream-to=origin/nope", "main"]),
        Case(name: "sync-branch-missing", scenario: "everyday", arguments: ["branch", "--set-upstream-to=origin/main", "nope"]),
        Case(name: "sync-remote-exists", scenario: "everyday", arguments: ["remote", "add", "origin", "https://example.com/x.git"]),
        Case(name: "sync-remote-invalid-name", scenario: "everyday", arguments: ["remote", "add", "bad..name", "https://example.com/x.git"]),
        Case(name: "sync-unknown-scheme", scenario: "everyday", arguments: ["fetch", "weird"], prepare: [["remote", "add", "weird", "htps://example.com/x.git"]]),
        Case(name: "sync-src-refspec", scenario: "everyday", arguments: ["push", "origin", "nope"]),
        Case(name: "sync-delete-missing-remote-ref", scenario: "everyday", arguments: ["push", "origin", "--delete", "nope"]),
        Case(name: "sync-switch-invalid", scenario: "everyday", arguments: ["switch", "nope"])
    ]

    @Test(.enabled(if: enabled && Sandbox.available))
    func recordSyncErrors() async throws {
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        for item in Self.cases {
            let copy = try ScenarioCopy.make(item.scenario)
            defer { copy.remove() }
            if item.clean { try await copy.clean() }
            for step in item.prepare { _ = try await copy.git(step) }
            if let preReceive = item.preReceive { try copy.setHook("pre-receive", preReceive, in: copy.remote("origin").appending(path: "hooks")) }
            var environment: GitEnvironment?
            var port: Int?
            switch item.auth {
            case .none: break
            case .storedToken:
                port = try AuthServer.port(in: copy)
                environment = try copy.isolatedEnvironment(seed: "http://avery:vrai_expired_token@127.0.0.1%3a\(port ?? 0)\n")
            case .noHelper:
                port = try AuthServer.port(in: copy)
                environment = try copy.isolatedEnvironment(helper: false)
            }
            if let port { try await AuthServer.acquire(port: port) }
            let result = try await copy.process(environment: environment).runAllowingFailure(GitCommand(item.arguments, access: .write))
            if port != nil { AuthServer.release() }
            #expect(result.exitCode != 0, "\(item.name) should fail")
            try Self.normalize(result.stderr, copy: copy).write(to: Self.folder.appending(path: item.name + ".err"))
            try Self.normalize(result.stdout, copy: copy).write(to: Self.folder.appending(path: item.name + ".out"))
            try Data("\(result.exitCode)\n\(item.arguments.joined(separator: " "))\n".utf8).write(to: Self.folder.appending(path: item.name + ".meta"))
        }
    }

    static func normalize(_ data: Data, copy: ScenarioCopy) -> Data {
        var text = String(decoding: data, as: UTF8.self)
        let root = copy.root.path(percentEncoded: false).trimmingSuffix("/")
        let replacement = "/SANDBOX/fixtures/" + copy.scenario
        text = text.replacingOccurrences(of: "/private" + root, with: replacement)
        text = text.replacingOccurrences(of: root, with: replacement)
        let sandbox = Sandbox.root.path(percentEncoded: false).trimmingSuffix("/")
        text = text.replacingOccurrences(of: "/private" + sandbox, with: "/SANDBOX")
        text = text.replacingOccurrences(of: sandbox, with: "/SANDBOX")
        return Data(text.utf8)
    }
}
