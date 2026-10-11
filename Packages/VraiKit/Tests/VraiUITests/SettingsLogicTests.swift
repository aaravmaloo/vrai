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
        let menuBar = ["\u{2325}\u{21E7}\u{2318}F", "\u{2325}\u{21E7}\u{2318}L", "\u{2325}\u{21E7}\u{2318}P", "\u{2318}C", "\u{2325}\u{2318}C", "\u{2318}F", "\u{2318}B", "\u{2325}\u{21E7}\u{2318}R", "\u{21E7}\u{2318}A", "\u{21E7}\u{2318}1", "\u{2318}4", "\u{2318}W", "\u{2318}M", "\u{2318}H", "\u{2318}Q"]
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
        #expect(SettingsCopy.stored(in: "~/.gitconfig", as: ["init.defaultBranch"]) == "Stored in ~/.gitconfig as init.defaultBranch.")
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
        let items = AccountList.items(accounts: [saved].compactMap { $0 }, windows: [], active: nil)
        #expect(items.count == 1)
        #expect(items.first?.status == .ok)
        #expect(items.first?.host == "github.com")
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
