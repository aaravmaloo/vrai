import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
struct SettingsSandbox {
    let root: URL
    let app: AppModel

    var gitconfig: URL { root.appending(path: "gitconfig") }
    var credentials: URL { root.appending(path: "git-credentials") }
    var home: URL { root.appending(path: "home", directoryHint: .isDirectory) }

    func repository(_ scenario: String = "everyday", _ name: String = "vrai") -> URL {
        root.appending(path: "fixtures/\(scenario)/\(name)", directoryHint: .isDirectory)
    }

    static func make(_ scenarios: [String] = ["everyday"]) async throws -> SettingsSandbox {
        let fm = FileManager.default
        let root = Sandbox.root.appending(path: "tests/settings-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: root.appending(path: "fixtures", directoryHint: .isDirectory), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appending(path: "home/.config", directoryHint: .isDirectory), withIntermediateDirectories: true)
        let oldPrefix = Sandbox.root.path(percentEncoded: false).trimmingSuffix("/")
        let newPrefix = root.path(percentEncoded: false).trimmingSuffix("/")
        try fm.copyItem(at: Sandbox.root.appending(path: "home/.ssh", directoryHint: .isDirectory), to: root.appending(path: "home/.ssh", directoryHint: .isDirectory))
        let config = try String(contentsOf: Sandbox.root.appending(path: "gitconfig"), encoding: .utf8)
        try Data(config.replacingOccurrences(of: oldPrefix + "/", with: newPrefix + "/").utf8).write(to: root.appending(path: "gitconfig"))
        fm.createFile(atPath: root.appending(path: "git-credentials").path(percentEncoded: false), contents: Data(), attributes: [.posixPermissions: NSNumber(value: 0o600)])
        for scenario in scenarios {
            let source = Sandbox.root.appending(path: "fixtures/\(scenario)", directoryHint: .isDirectory)
            let target = root.appending(path: "fixtures/\(scenario)", directoryHint: .isDirectory)
            try fm.copyItem(at: source, to: target)
        }
        let app = AppModel(launch: LaunchOptions(sandbox: root))
        let sandbox = SettingsSandbox(root: root, app: app)
        for scenario in scenarios {
            let repo = sandbox.repository(scenario, scenario == "empty" ? "pocket-notes" : "vrai")
            guard fm.fileExists(atPath: repo.path(percentEncoded: false)) else { continue }
            let git = try app.process(at: repo)
            for name in try await git.run(.read(["remote"])).output.split(separator: "\n") {
                let url = try await git.run(.read(["remote", "get-url", String(name)])).output.trimmingCharacters(in: .whitespacesAndNewlines)
                guard url.contains(oldPrefix + "/") else { continue }
                try await git.run(.write(["remote", "set-url", String(name), url.replacingOccurrences(of: oldPrefix + "/", with: newPrefix + "/")]))
            }
        }
        return sandbox
    }

    func store(_ scenario: String = "everyday") async throws -> RepositoryStore {
        let store = try app.store(for: RepositoryReference(url: repository(scenario, scenario == "empty" ? "pocket-notes" : "vrai")))
        try await store.refresh()
        return store
    }

    func readGlobal(_ key: String) async throws -> String? {
        let git = try app.configProcess()
        let result = try await git.run(.read(["config", "--global", "--get", key], acceptedExitCodes: [0, 1]))
        return result.exitCode == 0 ? result.output.trimmingCharacters(in: .newlines) : nil
    }

    func readAllGlobal(_ key: String) async throws -> [String] {
        let git = try app.configProcess()
        let result = try await git.run(.read(["config", "--global", "--get-all", key], acceptedExitCodes: [0, 1]))
        return result.output.split(separator: "\n").map(String.init)
    }

    func readLocal(_ key: String, scenario: String = "everyday") async throws -> String? {
        let git = try app.process(at: repository(scenario))
        let result = try await git.run(.read(["config", "--local", "--get", key], acceptedExitCodes: [0, 1]))
        return result.exitCode == 0 ? result.output.trimmingCharacters(in: .newlines) : nil
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
