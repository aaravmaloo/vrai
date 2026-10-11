import Foundation
import VraiGit

public struct RepositoryConfig: Sendable, Hashable {
    public var entries: [ConfigEntry]

    public init(entries: [ConfigEntry]) {
        self.entries = entries
    }

    public var local: ConfigValues { ConfigValues(entries.filter { $0.scope == .local || $0.scope == .worktree }) }
    public var global: ConfigValues { ConfigValues(entries.filter { $0.scope == .global }) }
    public var effective: ConfigValues { ConfigValues(entries.sorted { $0.scope.rank > $1.scope.rank }) }

    public var hasLocalIdentity: Bool {
        local.has(ConfigKeys.userName) || local.has(ConfigKeys.userEmail)
    }

    public var identity: Identity { Identity(config: effective) }

    public func isOverridden(_ entry: ConfigEntry) -> Bool {
        let key = ConfigCommands.canonical(entry.key)
        return entries.contains { ConfigCommands.canonical($0.key) == key && $0.scope.rank < entry.scope.rank }
    }
}

extension RepositoryStore {
    public func configTable() async throws -> [ConfigEntry] {
        let data = try await git.run(ConfigCommands.table, background: true).stdout
        return ConfigParser.table(data).filter { $0.scope != .command }
    }

    public func repositoryConfig() async throws -> RepositoryConfig {
        RepositoryConfig(entries: try await configTable())
    }

    public func setConfig(key: String, value: String, scope: ConfigEntry.Scope) async throws {
        guard scope.isWritable, ConfigCommands.isValidKey(key) else { throw GitError(.unknown(exit: 1, stderr: "error: invalid key: " + key)) }
        try await perform("config") {
            _ = try await git.run(ConfigCommands.set(key, value, scope: scope))
        }
    }

    public func unsetConfig(key: String, scope: ConfigEntry.Scope) async throws {
        guard scope.isWritable else { return }
        try await perform("config") {
            _ = try await git.run(ConfigCommands.unset(key, scope: scope))
        }
    }

    public func replaceConfig(key: String, old: String, new: String, scope: ConfigEntry.Scope) async throws {
        guard scope.isWritable else { return }
        try await perform("config") {
            _ = try await git.run(ConfigCommands.replace(key, old: old, new: new, scope: scope))
        }
    }

    public func removeConfig(key: String, value: String, scope: ConfigEntry.Scope) async throws {
        guard scope.isWritable else { return }
        try await perform("config") {
            _ = try await git.run(ConfigCommands.remove(key, value: value, scope: scope))
        }
    }

    nonisolated public static func localIdentityWrites(_ identity: Identity?) -> [ConfigWrite] {
        [ConfigWrite(ConfigKeys.userName, identity?.name.flatMap { $0.isEmpty ? nil : $0 }), ConfigWrite(ConfigKeys.userEmail, identity?.email.flatMap { $0.isEmpty ? nil : $0 })]
    }

    public func setLocalIdentity(_ identity: Identity?) async throws {
        try await perform("identity") {
            for change in Self.localIdentityWrites(identity) {
                try await git.run(ConfigCommands.write(change, scope: .local))
            }
        }
    }

    public func setHookEnabled(name: String, enabled: Bool) async throws {
        guard let hook = snapshot?.hooks.first(where: { $0.name == name }) else { throw GitError(.refNotFound) }
        try await perform("hooks") {
            try HookCommands.setEnabled(enabled, path: hook.path)
        }
    }

    public func hookCommand(name: String, messageFile: URL? = nil) -> GitCommand {
        var arguments: [String] = []
        var stdin: Data?
        if HookCommands.messageHooks.contains(name) {
            arguments = [messageFile?.path(percentEncoded: false) ?? "COMMIT_EDITMSG"]
        } else if name == "pre-push" {
            let remote = snapshot?.remotes.first { $0.name == "origin" } ?? snapshot?.remotes.first
            arguments = [remote?.name ?? "origin", remote.map { $0.pushURL ?? $0.fetchURL } ?? "origin"]
            stdin = Data()
        }
        return HookCommands.run(name, arguments: arguments, stdin: stdin)
    }

    public func runHook(name: String) async throws -> HookRun {
        var folder: URL?
        var messageFile: URL?
        if HookCommands.messageHooks.contains(name) {
            let created = FileManager.default.temporaryDirectory.appending(path: "vrai-hook-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: created, withIntermediateDirectories: true)
            let file = created.appending(path: "COMMIT_EDITMSG")
            let message = (try? await git.run(.read(["log", "-1", "--format=%B"]), background: true).output) ?? ""
            try Data((message.isEmpty ? "Run by Vrai\n" : message).utf8).write(to: file)
            folder = created
            messageFile = file
        }
        defer { if let folder { try? FileManager.default.removeItem(at: folder) } }
        let command = hookCommand(name: name, messageFile: messageFile)
        return try await perform("hook:" + name) {
            let result = try await git.runAllowingFailure(command)
            let output = (result.output + result.errorOutput).trimmingCharacters(in: .whitespacesAndNewlines)
            return HookRun(name: name, exitCode: result.exitCode, output: output, duration: result.duration)
        }
    }

    public func maintenanceRegistered() async throws -> Bool {
        guard let snapshot else { return false }
        let data = try await git.run(MaintenanceCommands.registered, background: true).stdout
        let target = snapshot.root ?? snapshot.commonDir
        return MaintenanceCommands.isRegistered(ConfigCommands.values(data), repository: target)
    }

    @discardableResult
    public func setMaintenance(registered: Bool) async throws -> ActionSummary {
        let current = try await maintenanceRegistered()
        return try await perform("maintenance", refresh: false) {
            if registered, !current {
                try await git.run(MaintenanceCommands.register)
            } else if !registered, current {
                try await git.run(MaintenanceCommands.unregister)
            }
            return registered
                ? ActionSummary(String(localized: "Background maintenance is on", bundle: .module), detail: String(localized: "git keeps this repository fast while you work.", bundle: .module))
                : ActionSummary(String(localized: "Background maintenance is off", bundle: .module))
        }
    }

    @discardableResult
    public func runMaintenance(auto: Bool = false) async throws -> ActionSummary {
        try await perform("maintenance") {
            try await git.run(MaintenanceCommands.run(auto: auto))
            return ActionSummary(String(localized: "Maintenance finished", bundle: .module), detail: String(localized: "Commit graph, prefetch and loose objects are up to date.", bundle: .module))
        }
    }

    public func lfsStatus() async -> LFSStatus {
        guard let env = try? await git.runAllowingFailure(LFSCommands.env, background: true) else { return .notInstalled }
        if LFSCommands.isMissing(env) { return .notInstalled }
        let text = env.output + "\n" + env.errorOutput
        guard env.exitCode == 0, let version = LFSCommands.version(text) else { return .notInstalled }
        var info = LFSInfo(version: version, configured: LFSCommands.configured(text))
        if let track = try? await git.runAllowingFailure(LFSCommands.track, background: true), track.exitCode == 0 {
            info.patterns = LFSCommands.patterns(track.output)
        }
        if !info.patterns.isEmpty, let files = try? await git.runAllowingFailure(LFSCommands.files, background: true), files.exitCode == 0 {
            info.files = LFSCommands.fileCount(files.output)
        }
        return .installed(info)
    }
}
