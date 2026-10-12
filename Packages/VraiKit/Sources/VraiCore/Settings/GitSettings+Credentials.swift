import Foundation
import VraiGit

public struct CredentialSetup: Sendable, Hashable {
    public var helpers: [CredentialHelper]
    public var manager: CredentialManager?
    public var managerVersion: String?
    public var managerStore: String?
    public var keychainAvailable: Bool

    public init(helpers: [CredentialHelper] = [], manager: CredentialManager? = nil, managerVersion: String? = nil, managerStore: String? = nil, keychainAvailable: Bool = true) {
        self.helpers = helpers
        self.manager = manager
        self.managerVersion = managerVersion
        self.managerStore = managerStore
        self.keychainAvailable = keychainAvailable
    }

    public var managerActive: Bool { manager != nil && helpers.contains { $0.kind == .manager } }
    public var primary: CredentialHelper? { helpers.first }
}

extension GitSettings {
    public static let credentialStoreKey = "credential.credentialStore"

    public func credentialHelpers() async -> [CredentialHelper] {
        guard let result = try? await git.run(CredentialHelperCommands.configured, background: true), result.exitCode == 0 else { return [] }
        return CredentialHelper.effective(ConfigCommands.values(result.stdout))
    }

    public func credentialSetup(locate: ([CredentialHelper]) -> CredentialManager?) async -> CredentialSetup {
        let helpers = await credentialHelpers()
        let manager = locate(helpers)
        let version = manager == nil ? nil : await CredentialAccounts(store: CredentialStore(git: git), manager: manager).version()
        let keychain = await isInstalled("git-credential-osxkeychain")
        let store = table.last { ConfigCommands.canonical($0.key) == ConfigCommands.canonical(Self.credentialStoreKey) }?.value
        return CredentialSetup(helpers: helpers, manager: manager, managerVersion: version, managerStore: store, keychainAvailable: keychain)
    }

    func isInstalled(_ name: String) async -> Bool {
        guard let result = try? await git.run(.read(["--exec-path"]), background: true) else { return false }
        let folder = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folder.isEmpty else { return false }
        return FileManager.default.isExecutableFile(atPath: URL(filePath: folder, directoryHint: .isDirectory).appending(path: name).path(percentEncoded: false))
    }

    public func setCredentialHelper(_ kind: CredentialHelper.Kind) async throws {
        try await applyCredentialCommands(CredentialHelperCommands.choose(kind))
    }

    public func clearCredentialHelpers() async throws {
        try await applyCredentialCommands(CredentialHelperCommands.chooseNone)
    }

    public func setCredentialManager(_ manager: CredentialManager) async throws {
        let global = try await git.run(ConfigCommands.getAll(CredentialHelperCommands.key, scope: .global), background: true)
        let azure = values.has(CredentialHelperCommands.azureUseHttpPath)
        if CredentialHelperCommands.isConfigured(manager: manager, in: ConfigCommands.values(global.stdout)) {
            guard !azure else { return }
            try await applyCredentialCommands([ConfigCommands.set(CredentialHelperCommands.azureUseHttpPath, "true", scope: .global)])
            return
        }
        try await applyCredentialCommands(CredentialHelperCommands.choose(manager: manager, azureConfigured: azure))
    }

    func applyCredentialCommands(_ commands: [GitCommand]) async throws {
        guard !commands.isEmpty else { return }
        do {
            for command in commands {
                try await git.run(command)
            }
        } catch {
            await reload()
            throw error
        }
        await reload()
    }

    var home: String? { git.environment.base["HOME"] }

    @discardableResult
    public func forgetCachedPasswords() async throws -> Int {
        let caches = await credentialHelpers().filter { $0.kind == .cache }
        for helper in caches {
            try await git.run(CredentialHelperCommands.forgetCached(socket: helper.socket.map { CredentialHelperCommands.expandHome($0, home: home) }))
        }
        return caches.count
    }

    @discardableResult
    public func deleteSavedPasswords() async throws -> Int {
        let stores = await credentialHelpers().filter { $0.kind == .store }
        for helper in stores {
            let file = helper.file.map { CredentialHelperCommands.expandHome($0, home: home) }
            for scheme in CredentialHelperCommands.schemes {
                try await git.run(CredentialHelperCommands.eraseStored(file: file, scheme: scheme))
            }
        }
        return stores.count
    }
}
