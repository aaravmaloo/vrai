import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
struct SettingsPreferencesTests {
    func defaults() -> (UserDefaults, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "vrai-settings-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (LaunchOptions(sandbox: dir).makeDefaults(), dir)
    }

    @Test func launchOptionOpensSettingsOnAPane() {
        let options = LaunchOptions(arguments: ["Vrai", "-VraiSettings", "accounts", "-VraiAppearance", "dark"])
        #expect(options.settings == "accounts")
        #expect(options.appearance == .dark)
        #expect(LaunchOptions(arguments: ["Vrai"]).settings == nil)
    }

    @Test func accountsAreRememberedPerHostAndUser() {
        let (store, dir) = defaults()
        defer { try? FileManager.default.removeItem(at: dir) }
        let preferences = Preferences(defaults: store)
        #expect(preferences.accounts.isEmpty)
        let first = preferences.noteSignedIn(url: "https://avery@github.com/vrai-app/vrai.git", username: "avery-chen", at: Date(timeIntervalSince1970: 100))
        #expect(first?.host == "github.com")
        #expect(first?.url == "https://github.com")
        preferences.noteSignedIn(url: "http://127.0.0.1:47818/vrai.git", username: "avery", at: Date(timeIntervalSince1970: 200))
        preferences.noteSignedIn(url: "https://github.com", username: "avery-chen", at: Date(timeIntervalSince1970: 300))
        #expect(preferences.accounts.map(\.host) == ["github.com", "127.0.0.1:47818"])
        #expect(preferences.accounts.first?.signedIn == Date(timeIntervalSince1970: 300))
        #expect(preferences.accounts.last?.url == "http://127.0.0.1:47818")
        #expect(preferences.accounts.last?.displayHost == "127.0.0.1")
        #expect(preferences.noteSignedIn(url: "/local/path", username: "x") == nil)
        #expect(preferences.noteSignedIn(url: "https://example.com", username: "  ") == nil)

        let reloaded = Preferences(defaults: store)
        #expect(reloaded.accounts == preferences.accounts)
        reloaded.forget(reloaded.accounts[0])
        #expect(Preferences(defaults: store).accounts.map(\.host) == ["127.0.0.1:47818"])
    }

    @Test func gitPathIsStoredAndCleared() {
        let (store, dir) = defaults()
        defer { try? FileManager.default.removeItem(at: dir) }
        let preferences = Preferences(defaults: store)
        #expect(preferences.gitPath == nil)
        preferences.gitPath = "/opt/homebrew/bin/git"
        #expect(store.string(forKey: "gitPath") == "/opt/homebrew/bin/git")
        #expect(Preferences(defaults: store).gitPath == "/opt/homebrew/bin/git")
        preferences.gitPath = nil
        #expect(store.string(forKey: "gitPath") == nil)
    }
}
