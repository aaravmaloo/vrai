import Foundation
import Observation
import VraiGit

@MainActor
@Observable
public final class GitSettings {
    public let git: GitProcess
    public private(set) var values = ConfigValues()
    public private(set) var table: [ConfigEntry] = []
    public private(set) var phase: LoadState = .idle
    public private(set) var busy: Set<String> = []
    public private(set) var revision = 0

    public init(git: GitProcess) {
        self.git = git
    }

    public var isLoaded: Bool { phase == .loaded }

    public func reload() async {
        if phase != .loaded { phase = .loading }
        do {
            let data = try await git.run(ConfigCommands.table, background: true).stdout
            let entries = ConfigParser.table(data).filter { $0.scope != .command }
            table = entries
            values = ConfigValues(entries.filter { $0.scope == .global })
            phase = .loaded
            revision += 1
        } catch let error as GitError {
            phase = .failed(error)
        } catch {
            phase = .failed(GitError(.unknown(exit: -1, stderr: String(describing: error))))
        }
    }

    nonisolated public static func commands(_ writes: [ConfigWrite], scope: ConfigEntry.Scope = .global) -> [GitCommand] {
        writes.map { ConfigCommands.write($0, scope: scope) }
    }

    public func write(_ writes: [ConfigWrite], action: String = "config") async throws {
        busy.insert(action)
        defer { busy.remove(action) }
        apply(writes)
        do {
            for command in Self.commands(writes) {
                try await git.run(command)
            }
        } catch {
            await reload()
            throw error
        }
        await reload()
    }

    private func apply(_ writes: [ConfigWrite]) {
        var entries = values.entries
        for change in writes {
            let key = ConfigCommands.canonical(change.key)
            entries.removeAll { ConfigCommands.canonical($0.key) == key }
            if let value = change.value { entries.append(ConfigEntry(scope: .global, key: change.key, value: value)) }
        }
        values = ConfigValues(entries)
    }

    public func set(_ key: String, _ value: String) async throws {
        try await write([ConfigWrite(key, value)], action: key)
    }

    public func unset(_ key: String) async throws {
        try await write([ConfigWrite(key, nil)], action: key)
    }

    public var defaultBranch: String? { values.value(ConfigKeys.defaultBranch) }
    public var pullMode: PullMode { PullMode(config: values) }
    public var autostash: Bool { values.bool(ConfigKeys.rebaseAutostash) ?? false }
    public var rerere: Bool { values.bool(ConfigKeys.rerere) ?? false }
    public var diffAlgorithm: DiffAlgorithm { DiffAlgorithm(config: values) }
    public var signing: SigningSettings { SigningSettings(config: values) }
    public var identity: Identity { Identity(config: values) }
    public var maintenanceRepositories: [String] { values.values(ConfigKeys.maintenanceRepo) }

    nonisolated public static func autostashWrites(_ on: Bool) -> [ConfigWrite] {
        [ConfigWrite(ConfigKeys.rebaseAutostash, ConfigBool.string(on)), ConfigWrite(ConfigKeys.mergeAutostash, ConfigBool.string(on))]
    }

    public func setDefaultBranch(_ name: String) async throws {
        try await write([ConfigWrite(ConfigKeys.defaultBranch, name)], action: ConfigKeys.defaultBranch)
    }

    public func setPullMode(_ mode: PullMode) async throws {
        try await write(mode.writes, action: ConfigKeys.pullRebase)
    }

    public func setAutostash(_ on: Bool) async throws {
        try await write(Self.autostashWrites(on), action: ConfigKeys.rebaseAutostash)
    }

    public func setRerere(_ on: Bool) async throws {
        try await write([ConfigWrite(ConfigKeys.rerere, ConfigBool.string(on))], action: ConfigKeys.rerere)
    }

    public func setDiffAlgorithm(_ algorithm: DiffAlgorithm) async throws {
        try await write([ConfigWrite(ConfigKeys.diffAlgorithm, algorithm.rawValue)], action: ConfigKeys.diffAlgorithm)
    }

    public func setSigning(_ on: Bool) async throws {
        try await write(SigningSettings.writes(signing: on), action: ConfigKeys.commitSign)
    }

    public func setSignFormat(_ format: SignFormat) async throws {
        try await write([ConfigWrite(ConfigKeys.signFormat, format.rawValue)], action: ConfigKeys.signFormat)
    }

    public func setSigningKey(_ key: String?) async throws {
        let value = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        try await write([ConfigWrite(ConfigKeys.signingKey, value?.isEmpty == false ? value : nil)], action: ConfigKeys.signingKey)
    }

    public func setName(_ name: String) async throws {
        try await write([ConfigWrite(ConfigKeys.userName, name)], action: ConfigKeys.userName)
    }

    public func setEmail(_ email: String) async throws {
        try await write([ConfigWrite(ConfigKeys.userEmail, email)], action: ConfigKeys.userEmail)
    }

    public func version() async -> String? {
        guard let result = try? await git.run(ConfigCommands.version, background: true) else { return nil }
        return GitVersion(parsing: result.output)?.description
    }
}
