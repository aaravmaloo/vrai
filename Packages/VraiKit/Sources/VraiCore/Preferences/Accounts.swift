import Foundation
import VraiGit

public struct SignedInAccount: Codable, Sendable, Hashable, Identifiable {
    public var host: String
    public var username: String
    public var url: String
    public var signedIn: Date

    public var id: String { url + "\u{0}" + username }

    public init(host: String, username: String, url: String, signedIn: Date) {
        self.host = host
        self.username = username
        self.url = url
        self.signedIn = signedIn
    }

    public init?(url: String, username: String, signedIn: Date) {
        guard let parsed = RemoteURL(url), parsed.kind == .network, let host = parsed.hostAndPort else { return nil }
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        self.host = host
        self.username = name
        self.url = (parsed.scheme ?? "https") + "://" + host
        self.signedIn = signedIn
    }

    public var displayHost: String {
        RemoteURL(url)?.host ?? host
    }
}

extension Preferences {
    @discardableResult
    public func noteSignedIn(url: String, username: String, at date: Date = Date()) -> SignedInAccount? {
        guard let account = SignedInAccount(url: url, username: username, signedIn: date) else { return nil }
        var list = accounts.filter { !($0.url == account.url && $0.username == account.username) }
        list.insert(account, at: 0)
        accounts = list
        return account
    }

    public func forget(_ account: SignedInAccount) {
        accounts.removeAll { $0.id == account.id }
    }

    public func forget(url: String, username: String) {
        guard let target = SignedInAccount(url: url, username: username, signedIn: Date()) else { return }
        accounts.removeAll { $0.url.lowercased() == target.url.lowercased() && $0.username == target.username }
    }
}
