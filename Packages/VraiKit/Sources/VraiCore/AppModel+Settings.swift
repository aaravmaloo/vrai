import Foundation
import VraiGit

extension AppModel {
    public var configDirectory: URL {
        launch.sandbox ?? FileManager.default.homeDirectoryForCurrentUser
    }

    public func configProcess() throws -> GitProcess {
        try process(at: configDirectory)
    }

    public func makeGitSettings() throws -> GitSettings {
        GitSettings(git: try configProcess())
    }

    public var homeDirectory: URL {
        if let home = environment.base["HOME"], !home.isEmpty { return URL(filePath: home, directoryHint: .isDirectory) }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public var sshFolder: URL { SSHKeys.folder(home: homeDirectory) }

    public var credentialHelper: String? {
        launch.sandbox.map { CredentialStore.storeHelper(file: $0.appending(path: "git-credentials")) }
    }

    public var globalConfigPath: String {
        GlobalConfigFile.path(environment: environment.base)
    }

    public var globalConfigDisplay: String {
        GlobalConfigFile.display(globalConfigPath, environment: environment.base)
    }

    public func credentials() throws -> CredentialStore {
        CredentialStore(git: try configProcess(), helper: credentialHelper)
    }

    public func signOut(_ account: SignedInAccount) async throws {
        try await credentials().reject(url: account.url, username: account.username)
        preferences.forget(account)
    }

    public func signIn(url: String, username: String, token: String) async throws -> SignedInAccount? {
        try await credentials().approve(url: url, username: username, password: token)
        return preferences.noteSignedIn(url: url, username: username, at: now)
    }

    public var credentialManagerCandidates: [String] {
        if let sandbox = launch.sandbox { return [sandbox.appending(path: "bin/" + CredentialManager.name).path(percentEncoded: false)] }
        return CredentialManager.standardLocations + CredentialManager.searchPath(environment.base)
    }

    public func locateCredentialManager(_ helpers: [CredentialHelper]) -> CredentialManager? {
        CredentialManager.locate(configured: launch.isSandboxed ? [] : helpers, candidates: credentialManagerCandidates)
    }

    public func credentialAccounts(_ setup: CredentialSetup) throws -> CredentialAccounts {
        CredentialAccounts(store: try credentials(), manager: setup.managerActive ? setup.manager : nil)
    }

    public func signInWithCredentialManager(url: String, setup: CredentialSetup, known: [String]) async throws -> String? {
        let accounts = try await credentialAccounts(setup).signIn(url: url)
        let added = accounts.first { name in !known.contains { $0.caseInsensitiveCompare(name) == .orderedSame } } ?? accounts.first
        if let added { preferences.noteSignedIn(url: url, username: added, at: now) }
        return added
    }

    public func signOut(url: String, username: String, setup: CredentialSetup) async throws {
        try await credentialAccounts(setup).signOut(url: url, username: username)
        preferences.forget(url: url, username: username)
    }

    @discardableResult
    public func useGit(at path: String?) throws -> GitExecutable {
        let executable: GitExecutable
        if let path, !path.isEmpty {
            let binary = try GitBinaries.inspect(path)
            guard binary.isSupported else { throw GitError(.gitTooOld(found: binary.version, needed: GitVersion.minimum)) }
            executable = GitExecutable(url: URL(filePath: path), version: binary.version)
        } else {
            executable = try GitExecutable.discover()
        }
        preferences.gitPath = path.flatMap { $0.isEmpty ? nil : $0 }
        gitExecutable = executable
        gitError = nil
        return executable
    }

    public nonisolated static func gitBinaries(including path: String?) async -> [GitBinary] {
        await Task.detached(priority: .utility) { GitBinaries.find(including: [path]) }.value
    }
}
