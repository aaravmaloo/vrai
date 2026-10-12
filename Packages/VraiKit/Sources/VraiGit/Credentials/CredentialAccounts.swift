import Foundation

public struct AccountLookup: Sendable, Hashable {
    public var usernames: [String]
    public var managed: Set<String>

    public init(usernames: [String] = [], managed: Set<String> = []) {
        self.usernames = usernames
        self.managed = managed
    }

    public var isSignedIn: Bool { !usernames.isEmpty }
}

public struct CredentialAccounts: Sendable {
    public let store: CredentialStore
    public let manager: CredentialManager?
    public var timeout: Duration = .seconds(15)

    public init(store: CredentialStore, manager: CredentialManager? = nil) {
        self.store = store
        self.manager = manager
    }

    public var git: GitProcess { store.git }

    public func manages(_ url: String) -> Bool {
        guard manager != nil, let host = RemoteURL(url)?.hostAndPort else { return false }
        return CredentialManager.isGitHub(host: host)
    }

    public func lookup(url: String, username: String? = nil) async -> AccountLookup {
        var listed: [String] = []
        if manages(url) { listed = (try? await bounded { try await listAccounts(url: url) }) ?? [] }
        let filled = try? await bounded { try await store.account(url: url, username: username) }
        var names = listed
        if let filled {
            names.removeAll { $0.caseInsensitiveCompare(filled) == .orderedSame }
            names.insert(filled, at: 0)
        }
        let managed = Set(names.filter { name in listed.contains { $0.caseInsensitiveCompare(name) == .orderedSame } })
        return AccountLookup(usernames: names, managed: managed)
    }

    public func listAccounts(url: String) async throws -> [String] {
        guard let manager else { return [] }
        let result = try await git.runCredentialManager(manager, CredentialManager.listCommand(url: url))
        return CredentialManager.accounts(result.output, url: url)
    }

    public func signIn(url: String) async throws -> [String] {
        guard let manager else { throw GitError(.gitNotFound) }
        try await git.runCredentialManager(manager, CredentialManager.loginCommand(url: url))
        return try await listAccounts(url: url)
    }

    public func signOut(url: String, username: String) async throws {
        if let manager, manages(url), try await listAccounts(url: url).contains(where: { $0.caseInsensitiveCompare(username) == .orderedSame }) {
            try await git.runCredentialManager(manager, CredentialManager.logoutCommand(account: username, url: url))
        } else {
            try await store.reject(url: url, username: username)
        }
    }

    public func version() async -> String? {
        guard let manager, let result = try? await bounded({ try await git.runCredentialManager(manager, CredentialManager.versionCommand) }) else { return nil }
        return CredentialManager.version(result.output)
    }

    enum Outcome<Value: Sendable>: Sendable {
        case done(Value)
        case late
    }

    func bounded<Value: Sendable>(_ work: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let limit = timeout
        return try await withThrowingTaskGroup(of: Outcome<Value>.self) { group in
            group.addTask { .done(try await work()) }
            group.addTask {
                try await Task.sleep(for: limit)
                return .late
            }
            defer { group.cancelAll() }
            guard case .done(let value)? = try await group.next() else { throw GitError(.cancelled) }
            return value
        }
    }
}
