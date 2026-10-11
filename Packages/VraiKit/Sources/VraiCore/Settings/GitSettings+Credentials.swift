import Foundation
import VraiGit

extension GitSettings {
    public func credentialHelpers() async -> [CredentialHelper] {
        guard let result = try? await git.run(CredentialHelperCommands.configured, background: true), result.exitCode == 0 else { return [] }
        return CredentialHelper.effective(ConfigCommands.values(result.stdout))
    }

    public func setCredentialHelper(_ kind: CredentialHelper.Kind) async throws {
        let commands = CredentialHelperCommands.choose(kind)
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
