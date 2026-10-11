import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "build the fixtures with Scripts/make-fixtures.sh"))
struct SettingsStoreTests {
    @Test func gitPaneWritesEveryKeyToTheGlobalConfig() async throws {
        let box = try await SettingsSandbox.make()
        defer { box.remove() }
        let settings = try box.app.makeGitSettings()
        await settings.reload()
        #expect(settings.isLoaded)
        #expect(settings.defaultBranch == "main")
        #expect(settings.pullMode == .merge)
        #expect(settings.rerere)
        #expect(settings.signing.commits)
        #expect(settings.signing.format == .ssh)
        #expect(settings.identity.name == "Avery Chen")

        try await settings.setDefaultBranch("trunk")
        #expect(try await box.readGlobal("init.defaultBranch") == "trunk")
        #expect(settings.defaultBranch == "trunk")

        try await settings.setPullMode(.rebase)
        #expect(try await box.readGlobal("pull.rebase") == "true")
        #expect(try await box.readGlobal("pull.ff") == nil)
        #expect(settings.pullMode == .rebase)
        try await settings.setPullMode(.fastForwardOnly)
        #expect(try await box.readGlobal("pull.rebase") == "false")
        #expect(try await box.readGlobal("pull.ff") == "only")
        #expect(settings.pullMode == .fastForwardOnly)
        try await settings.setPullMode(.merge)
        #expect(try await box.readGlobal("pull.rebase") == "false")
        #expect(try await box.readGlobal("pull.ff") == nil)

        try await settings.setAutostash(true)
        #expect(try await box.readGlobal("rebase.autoStash") == "true")
        #expect(try await box.readGlobal("merge.autoStash") == "true")
        #expect(settings.autostash)
        try await settings.setAutostash(false)
        #expect(try await box.readGlobal("rebase.autoStash") == "false")
        #expect(try await box.readGlobal("merge.autoStash") == "false")

        try await settings.setRerere(false)
        #expect(try await box.readGlobal("rerere.enabled") == "false")
        #expect(!settings.rerere)

        try await settings.setDiffAlgorithm(.histogram)
        #expect(try await box.readGlobal("diff.algorithm") == "histogram")
        #expect(settings.diffAlgorithm == .histogram)
    }

    @Test func accountsPaneWritesSigningAndIdentity() async throws {
        let box = try await SettingsSandbox.make()
        defer { box.remove() }
        let settings = try box.app.makeGitSettings()
        await settings.reload()

        try await settings.setSigning(false)
        #expect(try await box.readGlobal("commit.gpgsign") == "false")
        #expect(try await box.readGlobal("tag.gpgSign") == "false")
        #expect(!settings.signing.commits)
        try await settings.setSigning(true)
        #expect(try await box.readGlobal("commit.gpgsign") == "true")
        #expect(try await box.readGlobal("tag.gpgsign") == "true")

        try await settings.setSignFormat(.openpgp)
        #expect(try await box.readGlobal("gpg.format") == "openpgp")
        try await settings.setSignFormat(.ssh)
        #expect(try await box.readGlobal("gpg.format") == "ssh")
        let pub = box.home.appending(path: ".ssh/id_ed25519.pub").path(percentEncoded: false)
        try await settings.setSigningKey(pub)
        #expect(try await box.readGlobal("user.signingkey") == pub)
        #expect(settings.signing.key == pub)

        try await settings.setName("Avery Q. Chen")
        try await settings.setEmail("avery.chen@vrai.app")
        #expect(try await box.readGlobal("user.name") == "Avery Q. Chen")
        #expect(try await box.readGlobal("user.email") == "avery.chen@vrai.app")
        #expect(settings.identity == Identity(name: "Avery Q. Chen", email: "avery.chen@vrai.app"))
    }

    @Test func aSignedCommitVerifiesWithTheKeySettingsWrote() async throws {
        let box = try await SettingsSandbox.make()
        defer { box.remove() }
        let settings = try box.app.makeGitSettings()
        await settings.reload()
        let key = try #require(SSHKeys.list(home: box.app.homeDirectory, fingerprints: false).first { $0.name == "id_ed25519" })
        try await settings.setSigningKey(SSHKeys.signingKeyValue(for: key))
        #expect(try await box.readGlobal("user.signingkey") == box.home.appending(path: ".ssh/id_ed25519").path(percentEncoded: false))
        try await settings.setSignFormat(.ssh)
        try await settings.setSigning(true)
        let store = try await box.store()
        try await store.stageAll(includeUntracked: true)
        _ = try await store.commit(subject: "Sign with the key Settings chose", noVerify: true)
        let signature = try await store.git.run(.read(["log", "-1", "--format=%G?"])).output.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(signature == "G")
    }

    @Test func repositoryPaneWritesALocalIdentity() async throws {
        let box = try await SettingsSandbox.make()
        defer { box.remove() }
        let store = try await box.store()
        var config = try await store.repositoryConfig()
        #expect(!config.hasLocalIdentity)
        #expect(config.identity.name == "Avery Chen")

        try await store.setLocalIdentity(Identity(name: "Avery at Work", email: "avery@work.example"))
        #expect(try await box.readLocal("user.name") == "Avery at Work")
        #expect(try await box.readLocal("user.email") == "avery@work.example")
        #expect(try await box.readGlobal("user.name") == "Avery Chen")
        config = try await store.repositoryConfig()
        #expect(config.hasLocalIdentity)
        #expect(config.identity.name == "Avery at Work")
        let globalName = try #require(config.entries.first { $0.scope == .global && $0.key == "user.name" })
        #expect(config.isOverridden(globalName))

        try await store.setConfig(key: "user.email", value: "avery+vrai@work.example", scope: .local)
        #expect(try await box.readLocal("user.email") == "avery+vrai@work.example")

        try await store.setLocalIdentity(nil)
        #expect(try await box.readLocal("user.name") == nil)
        #expect(try await box.readLocal("user.email") == nil)
        config = try await store.repositoryConfig()
        #expect(!config.hasLocalIdentity)
    }

    @Test func expertTableEditsAddsAndRemovesAcrossScopes() async throws {
        let box = try await SettingsSandbox.make()
        defer { box.remove() }
        let store = try await box.store()
        let table = try await store.configTable()
        #expect(table.contains { $0.scope == .global && $0.key == "user.email" && $0.value == "avery@vrai.app" })
        #expect(table.contains { $0.scope == .local && $0.key == "remote.origin.url" })
        #expect(!table.contains { $0.scope == .command })
        #expect(table.allSatisfy { $0.origin != nil })

        try await store.setConfig(key: "merge.conflictStyle", value: "zdiff3", scope: .local)
        #expect(try await box.readLocal("merge.conflictStyle") == "zdiff3")
        try await store.setConfig(key: "merge.conflictStyle", value: "diff3", scope: .global)
        #expect(try await box.readGlobal("merge.conflictStyle") == "diff3")

        try await store.replaceConfig(key: "merge.conflictStyle", old: "zdiff3", new: "merge", scope: .local)
        #expect(try await box.readLocal("merge.conflictStyle") == "merge")

        let git = try box.app.configProcess()
        try await git.run(.write(["config", "--global", "--add", "x.multi", "a"]))
        try await git.run(.write(["config", "--global", "--add", "x.multi", "b"]))
        try await store.replaceConfig(key: "x.multi", old: "b", new: "B", scope: .global)
        #expect(try await box.readAllGlobal("x.multi") == ["a", "B"])
        try await store.removeConfig(key: "x.multi", value: "a", scope: .global)
        #expect(try await box.readAllGlobal("x.multi") == ["B"])

        try await store.unsetConfig(key: "merge.conflictStyle", scope: .local)
        #expect(try await box.readLocal("merge.conflictStyle") == nil)
        try await store.unsetConfig(key: "merge.conflictStyle", scope: .local)
        try await store.unsetConfig(key: "merge.conflictStyle", scope: .global)
        #expect(try await box.readGlobal("merge.conflictStyle") == nil)

        await #expect(throws: GitError.self) { try await store.setConfig(key: "nodot", value: "x", scope: .local) }
    }

    @Test func hooksToggleTheExecutableBitAndRunByHand() async throws {
        let box = try await SettingsSandbox.make()
        defer { box.remove() }
        let store = try await box.store()
        let hooks = try #require(store.snapshot?.hooks)
        #expect(hooks.map(\.name).contains("pre-commit"))
        let prePush = try #require(hooks.first { $0.name == "pre-push" })
        #expect(!prePush.enabled)

        try await store.setHookEnabled(name: "pre-push", enabled: true)
        #expect(FileManager.default.isExecutableFile(atPath: prePush.path))
        #expect(store.snapshot?.hooks.first { $0.name == "pre-push" }?.enabled == true)
        try await store.setHookEnabled(name: "pre-push", enabled: false)
        #expect(!FileManager.default.isExecutableFile(atPath: prePush.path))
        #expect(store.snapshot?.hooks.first { $0.name == "pre-push" }?.enabled == false)

        let passed = try await store.runHook(name: "pre-commit")
        #expect(passed.passed)
        let message = try await store.runHook(name: "commit-msg")
        #expect(message.passed)

        let marker = try #require(store.snapshot?.gitDir).appending(path: "vrai-fail-pre-commit")
        try Data().write(to: marker)
        let failed = try await store.runHook(name: "pre-commit")
        #expect(failed.exitCode == 1)
        #expect(failed.output.contains("swift-format lint --strict: 2 problems"))
        #expect(store.hookCommand(name: "pre-commit").display == "git hook run pre-commit")
    }

    @Test func maintenanceRegistersUnregistersAndRuns() async throws {
        let box = try await SettingsSandbox.make()
        defer { box.remove() }
        let store = try await box.store()
        #expect(try await store.maintenanceRegistered() == false)

        try await store.setMaintenance(registered: true)
        #expect(try await store.maintenanceRegistered())
        let registered = try await box.readAllGlobal("maintenance.repo")
        #expect(registered.count == 1)
        #expect(registered.first?.hasSuffix("/fixtures/everyday/vrai") == true)
        #expect(try await box.readLocal("maintenance.strategy") == "incremental")

        try await store.setMaintenance(registered: true)
        #expect(try await box.readAllGlobal("maintenance.repo").count == 1)

        let summary = try await store.runMaintenance()
        #expect(summary.message == "Maintenance finished")

        try await store.setMaintenance(registered: false)
        #expect(try await store.maintenanceRegistered() == false)
        #expect(try await box.readAllGlobal("maintenance.repo").isEmpty)
        try await store.setMaintenance(registered: false)
    }

    @Test func lfsStatusSaysWhenGitLFSIsMissing() async throws {
        let box = try await SettingsSandbox.make()
        defer { box.remove() }
        let store = try await box.store()
        let probe = try await store.git.runAllowingFailure(LFSCommands.env, background: true)
        let status = await store.lfsStatus()
        if LFSCommands.isMissing(probe) {
            #expect(status == .notInstalled)
        } else if case .installed(let info) = status {
            #expect(!info.version.isEmpty)
        } else {
            Issue.record("git lfs env ran but the status says not installed")
        }
    }

    @Test func sshKeysComeFromTheSandboxHomeOnly() async throws {
        let box = try await SettingsSandbox.make()
        defer { box.remove() }
        #expect(box.app.homeDirectory.path(percentEncoded: false).hasPrefix(box.root.path(percentEncoded: false)))
        let keys = SSHKeys.list(home: box.app.homeDirectory)
        let key = try #require(keys.first { $0.name == "id_ed25519" })
        #expect(key.type == "ED25519")
        #expect(key.comment == "avery@vrai.app")
        #expect(key.fingerprint?.hasPrefix("SHA256:") == true)
        #expect(key.publicKey.hasPrefix("ssh-ed25519 "))
        #expect(!keys.contains { $0.name.contains("stranger") })
        let settings = try box.app.makeGitSettings()
        await settings.reload()
        #expect(SSHKeys.matches(key, signingKey: settings.signing.key))
    }

    @Test func accountsSignInAndOutThroughTheSandboxCredentialStore() async throws {
        let box = try await SettingsSandbox.make()
        defer { box.remove() }
        let account = try await box.app.signIn(url: "https://git.example.com", username: "avery", token: "vrai_test_token")
        #expect(account?.host == "git.example.com")
        #expect(box.app.preferences.accounts.map(\.host) == ["git.example.com"])
        var stored = try String(contentsOf: box.credentials, encoding: .utf8)
        #expect(stored.contains("https://avery:vrai_test_token@git.example.com"))
        let reloaded = Preferences(defaults: box.app.defaults)
        #expect(reloaded.accounts.first?.username == "avery")

        try await box.app.signOut(try #require(account))
        stored = try String(contentsOf: box.credentials, encoding: .utf8)
        #expect(!stored.contains("git.example.com"))
        #expect(box.app.preferences.accounts.isEmpty)
    }

    @Test func gitBinaryChoiceIsRememberedAndValidated() async throws {
        let box = try await SettingsSandbox.make()
        defer { box.remove() }
        let current = try #require(box.app.gitExecutable)
        let binaries = await AppModel.gitBinaries(including: current.path)
        #expect(binaries.contains { $0.path == current.path })
        try box.app.useGit(at: current.path)
        #expect(box.app.preferences.gitPath == current.path)
        #expect(Preferences(defaults: box.app.defaults).gitPath == current.path)
        #expect(throws: GitError.self) { try box.app.useGit(at: box.root.appending(path: "no-git").path(percentEncoded: false)) }
        #expect(box.app.gitExecutable?.path == current.path)
        try box.app.useGit(at: nil)
        #expect(box.app.preferences.gitPath == nil)
        #expect(box.app.globalConfigPath == box.gitconfig.path(percentEncoded: false))
        #expect(box.app.globalConfigDisplay == "$VRAI_SANDBOX/gitconfig")
    }

    @Test func renameThresholdReachesStatusAndStagedDiffs() async throws {
        let box = try await SettingsSandbox.make()
        defer { box.remove() }
        let store = try await box.store()
        let repo = box.repository()
        let lines = (1...40).map { "line \($0) of the moved file" }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: repo.appending(path: "Moved.txt"))
        try await store.git.run(.write(["add", "--", "Moved.txt"]))
        try await store.git.run(.write(["commit", "-q", "--no-gpg-sign", "--no-verify", "-m", "Add a file to move"]))
        try FileManager.default.moveItem(at: repo.appending(path: "Moved.txt"), to: repo.appending(path: "Renamed.txt"))
        var edited = lines
        for index in stride(from: 0, to: 40, by: 3) { edited[index] = "changed \(index)" }
        try Data((edited.joined(separator: "\n") + "\n").utf8).write(to: repo.appending(path: "Renamed.txt"))
        try await store.git.run(.write(["add", "-A", "--", "Moved.txt", "Renamed.txt"]))

        store.renameThreshold = 50
        try await store.refresh()
        #expect(store.snapshot?.working.first { $0.path == "Renamed.txt" }?.status == .renamed)
        store.renameThreshold = 90
        try await store.refresh()
        #expect(store.snapshot?.working.first { $0.path == "Renamed.txt" }?.status == .added)
        #expect(store.snapshot?.working.contains { $0.path == "Moved.txt" && $0.status == .deleted } == true)
        #expect(StagingService.diffCommand(path: "Renamed.txt", oldPath: "Moved.txt", staged: true, untracked: false, renameThreshold: 90).arguments.contains("--find-renames=90%"))
    }
}
