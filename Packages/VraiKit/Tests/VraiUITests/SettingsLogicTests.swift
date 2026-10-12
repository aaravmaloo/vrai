import Foundation
import Testing
import VraiCore
import VraiGit
@testable import VraiUI

@MainActor
struct SettingsLogicTests {
    @Test func everyPaneHasATitleAndAnAllowedIcon() {
        #expect(SettingsPane.allCases.map(\.rawValue) == ["general", "git", "accounts", "appearance", "shortcuts", "repository", "expert"])
        #expect(SettingsPane.allCases.map(\.icon) == ["gearshape", "arrow.triangle.branch", "person.crop.circle", "paintbrush", "keyboard", "folder", "terminal"])
        #expect(SettingsPane.allCases.allSatisfy { !$0.title.isEmpty })
    }

    @Test func theShortcutListCoversAppendixBAndTheMenuBar() {
        let all = ShortcutCatalog.groups.flatMap(\.items)
        let keys = Set(all.flatMap(\.keys))
        let appendixB = ["\u{2318}K", "\u{2318}\u{21A9}", "\u{21E7}\u{2318}F", "\u{2325}\u{2318}\u{21A9}", "\u{21E7}\u{2318}L", "Space", "\u{21E7}\u{2318}P", "\u{2318}Z", "\u{21E7}\u{2318}B", "\u{2318}J", "\u{21E7}\u{2318}M", "\u{2303}\u{2318}S", "\u{21E7}\u{2318}R", "\u{2325}\u{2318}0", "\u{21E7}\u{2318}S", "\u{2325}\u{2318}E", "\u{2318}1", "\u{2318}2", "\u{2318}3", "\u{2318},", "\u{2318}O", "\u{21E7}\u{2318}O", "\u{2325}\u{2318}N"]
        let menuBar = ["\u{2325}\u{21E7}\u{2318}F", "\u{2325}\u{21E7}\u{2318}L", "\u{2325}\u{21E7}\u{2318}P", "\u{2318}C", "\u{2325}\u{2318}C", "\u{2318}F", "\u{2318}B", "\u{2325}\u{21E7}\u{2318}R", "\u{21E7}\u{2318}A", "\u{21E7}\u{2318}1", "\u{2318}4", "\u{2318}T", "\u{2318}W", "\u{2318}M", "\u{2318}H", "\u{2318}Q"]
        for shortcut in appendixB + menuBar {
            #expect(keys.contains(shortcut), "missing \(shortcut)")
        }
        #expect(all.count >= 50)
    }

    @Test func searchFiltersByGroupLabelOrKey() {
        let groups = ShortcutCatalog.groups
        #expect(ShortcutCatalog.filter(groups, query: "").count == groups.count)
        let push = ShortcutCatalog.filter(groups, query: "push")
        #expect(push.flatMap(\.items).map(\.label).contains("Force push with lease"))
        #expect(push.flatMap(\.items).allSatisfy { $0.label.lowercased().contains("push") })
        let branch = ShortcutCatalog.filter(groups, query: "Branch")
        #expect(branch.first { $0.title == "Branch" }?.items.count == 5)
        #expect(ShortcutCatalog.filter(groups, query: "nothing like this").isEmpty)
        #expect(ShortcutCatalog.filter(groups, query: "  rebase ").flatMap(\.items).contains { $0.label == "Interactive rebase" })
    }

    @Test func keyCapsSplitModifiersFromTheKey() {
        #expect(ShortcutCatalog.caps("\u{2325}\u{21E7}\u{2318}F") == ["\u{2325}", "\u{21E7}", "\u{2318}", "F"])
        #expect(ShortcutCatalog.caps("\u{2318}\u{21A9}") == ["\u{2318}", "\u{21A9}"])
        #expect(ShortcutCatalog.caps("Space") == ["Space"])
        #expect(ShortcutCatalog.caps("\u{2318}") == ["\u{2318}"])
        #expect(ShortcutCatalog.spoken("\u{21E7}\u{2318}P") == "Shift Command P")
    }

    @Test func copyHelpersJoinLikeTheVoiceRules() {
        #expect(SettingsCopy.list(["origin"]) == "origin")
        #expect(SettingsCopy.list(["origin", "mira"]) == "origin and mira")
        #expect(SettingsCopy.list(["pull.rebase", "pull.ff", "rebase.autoStash", "merge.autoStash"]) == "pull.rebase, pull.ff, rebase.autoStash and merge.autoStash")
        #expect(SettingsCopy.trimmed("/a/b/") == "/a/b")
        #expect(GeneralPane.interval(60) == "Every hour")
        #expect(GeneralPane.interval(15) == "Every 15 minutes")
        #expect(GitPaneForm.pullHelp(.rebase) == "Pull replays your commits on top of the upstream. Their hashes change.")
    }

    @Test func thePreviewSampleHasCommitsRowsAndADiff() {
        let sample = PreviewSample.make(now: Date(timeIntervalSince1970: 1_791_720_000))
        #expect(sample.commits.count == 5)
        #expect(sample.rows.count == 5)
        #expect(sample.lanes >= 2)
        #expect(sample.commits[1].isMerge)
        #expect(sample.diff.hunks.count == 1)
        #expect(sample.diff.hunks.first?.lines.filter { $0.kind == .add }.count == 2)
        #expect(sample.diff.hunks.first?.lines.filter { $0.kind == .del }.count == 1)
    }

    @Test func lfsAndHookCopyDescribeEachState() {
        #expect(LFSCopy.description(LFSInfo(version: "3.6.1", configured: false)).contains("git lfs install"))
        #expect(LFSCopy.description(LFSInfo(version: "3.6.1", configured: true)) == "This repository doesn't track any files with Git LFS.")
        #expect(LFSCopy.description(LFSInfo(version: "3.6.1", configured: true, patterns: ["*.png"], files: 42)) == "Tracking *.png: 42 files.")
        #expect(HookCopy.purpose("pre-push") == "Runs before each push. If it fails, nothing is pushed.")
        #expect(!HookCopy.purpose("post-index-change").isEmpty)
    }

    @Test func accountItemsMergeSavedAccountsWithRemoteHosts() {
        let saved = SignedInAccount(url: "https://github.com", username: "avery-chen", signedIn: Date(timeIntervalSince1970: 1_791_720_000))
        let remotes = [
            Remote(name: "origin", fetchURL: "https://avery@github.com/vrai-app/vrai.git", pushURL: nil, headBranch: nil, prune: false),
            Remote(name: "mirror", fetchURL: "https://git.example.com/vrai.git", pushURL: nil, headBranch: nil, prune: false),
            Remote(name: "ssh", fetchURL: "git@github.com:vrai-app/vrai.git", pushURL: nil, headBranch: nil, prune: false)
        ]
        let hosts = AccountList.hosts(accounts: [saved].compactMap { $0 }, remotes: remotes, managed: false)
        #expect(hosts.map(\.host) == ["github.com", "git.example.com"])
        #expect(hosts.first?.remote == "origin")
        #expect(hosts.first?.probe == "https://avery@github.com/vrai-app/vrai.git")
        #expect(hosts.first?.hint == "avery")
        #expect(hosts.first?.repository == "vrai-app/vrai")

        let checking = AccountList.items(hosts: hosts, lookups: [:])
        #expect(checking.map(\.status) == [.checking, .checking])
        let looked = AccountList.items(hosts: hosts, lookups: [
            "https://github.com": AccountLookup(usernames: ["avery", "mira"], managed: ["mira"]),
            "https://git.example.com": AccountLookup()
        ])
        #expect(looked.map(\.status) == [.ok, .ok, .none])
        #expect(looked.map(\.username) == ["avery", "mira", nil])
        #expect(looked.map(\.managed) == [false, true, false])
        #expect(Set(looked.map(\.id)).count == 3)
        let expired = AccountList.items(hosts: hosts, lookups: ["https://github.com": AccountLookup(usernames: ["avery"])], failing: ["github.com"])
        #expect(expired.first?.status == .expired)
        #expect(expired.last?.status == .checking)

        let managed = AccountList.hosts(accounts: [], remotes: [], managed: true)
        #expect(managed.map(\.url) == ["https://github.com"])
        #expect(AccountList.items(hosts: managed, lookups: [:]).isEmpty)
        #expect(AccountList.items(hosts: managed, lookups: ["https://github.com": AccountLookup()]).isEmpty)
        #expect(AccountList.items(hosts: managed, lookups: ["https://github.com": AccountLookup(usernames: ["avery"], managed: ["avery"])]).first?.status == .ok)
        #expect(AccountList.hosts(accounts: [], remotes: remotes, managed: true).first?.optional == false)
    }

    @Test func passwordChoicesListWhatIsInstalled() {
        let manager = CredentialManager(executable: URL(filePath: CredentialManager.packagePath))
        let keychain = CredentialSetup(helpers: CredentialHelper.effective(["osxkeychain", "osxkeychain"]), keychainAvailable: true)
        #expect(CredentialChoices.selection(keychain) == "keychain")
        #expect(CredentialChoices.options(keychain).map(\.value) == ["keychain", "store", ""])
        #expect(AccountsCopy.summary(keychain) == "git uses osxkeychain.")
        #expect(AccountsCopy.storage(keychain, environment: [:]) == "git's osxkeychain helper keeps tokens in your login keychain.")

        let gcm = CredentialSetup(helpers: CredentialHelper.effective(["osxkeychain", "", CredentialManager.packagePath]), manager: manager, managerVersion: "2.6.1", keychainAvailable: true)
        #expect(gcm.managerActive)
        #expect(CredentialChoices.selection(gcm) == "manager")
        #expect(CredentialChoices.options(gcm).map(\.value) == ["manager", "keychain", "store", ""])
        #expect(CredentialChoices.options(gcm).first?.label == "Git Credential Manager")
        #expect(AccountsCopy.summary(gcm) == "git uses Git Credential Manager 2.6.1.")
        #expect(AccountsCopy.storage(gcm, environment: [:]) == "Git Credential Manager keeps tokens in your login keychain.")
        var plaintext = gcm
        plaintext.managerStore = "plaintext"
        #expect(AccountsCopy.storage(plaintext, environment: [:]) == "Git Credential Manager keeps tokens in its plaintext store.")

        let installedNotChosen = CredentialSetup(helpers: CredentialHelper.effective(["osxkeychain"]), manager: manager, keychainAvailable: true)
        #expect(!installedNotChosen.managerActive)
        #expect(CredentialChoices.options(installedNotChosen).map(\.value) == ["manager", "keychain", "store", ""])

        let missing = CredentialSetup(helpers: CredentialHelper.effective(["/usr/local/share/gcm-core/git-credential-manager"]), keychainAvailable: false)
        #expect(!missing.managerActive)
        #expect(CredentialChoices.selection(missing) == "/usr/local/share/gcm-core/git-credential-manager")
        #expect(CredentialChoices.options(missing).map(\.value) == ["store", "/usr/local/share/gcm-core/git-credential-manager", ""])

        let nothing = CredentialSetup(helpers: [], keychainAvailable: true)
        #expect(CredentialChoices.selection(nothing) == "")
        #expect(AccountsCopy.summary(nothing) == "No helper is set, so git asks for a password every time.")
        #expect(AccountsCopy.summary(nil) == "Reading credential.helper\u{2026}")

        let cache = CredentialSetup(helpers: CredentialHelper.effective(["cache --timeout=900", "store --file=~/.vrai-credentials"]), keychainAvailable: true)
        #expect(CredentialChoices.options(cache).map(\.value) == ["keychain", "store", "cache", ""])
        #expect(AccountsCopy.summary(cache) == "git asks cache and store, in that order.")
        let store = CredentialSetup(helpers: CredentialHelper.effective(["store --file=~/.vrai-credentials"]))
        #expect(AccountsCopy.storage(store, environment: ["HOME": "/Users/avery"]) == "git credential-store keeps tokens unencrypted in /Users/avery/.vrai-credentials.")
        #expect(AccountsCopy.storage(nothing, environment: [:]) == "No credential helper is set, so git saves no tokens and asks every time.")
    }

    @Test func settingsErrorCopyCoversConfigFailures() {
        let result = GitResult(command: ConfigCommands.set("a.b", "c", scope: .global), exitCode: 5, stdout: Data(), stderr: Data("error: cannot overwrite multiple values with a single value\n".utf8), startedAt: Date(), duration: .zero)
        let copy = ErrorCopy(GitError(.unknown(exit: 5, stderr: result.errorOutput), result: result))
        #expect(copy.title == "git didn't change that setting")
        #expect(copy.message == "error: cannot overwrite multiple values with a single value")
        let hook = GitResult(command: HookCommands.run("pre-commit"), exitCode: 1, stdout: Data(), stderr: Data(), startedAt: Date(), duration: .zero)
        #expect(ErrorCopy(GitError(.unknown(exit: 1, stderr: ""), result: hook)).title == "The hook didn't run")
    }
}
