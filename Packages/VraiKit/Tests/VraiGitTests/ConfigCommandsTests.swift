import Foundation
import Testing
@testable import VraiGit

struct ConfigCommandsTests {
    static func values(_ pairs: [(ConfigEntry.Scope, String, String)]) -> ConfigValues {
        ConfigValues(pairs.map { ConfigEntry(scope: $0.0, key: $0.1, value: $0.2) })
    }

    @Test func canonicalKeysLowercaseSectionAndNameButKeepTheSubsection() {
        #expect(ConfigCommands.canonical("init.defaultBranch") == "init.defaultbranch")
        #expect(ConfigCommands.canonical("Branch.Feature/Graph.Remote") == "branch.Feature/Graph.remote")
        #expect(ConfigCommands.canonical("gpg.ssh.allowedSignersFile") == "gpg.ssh.allowedsignersfile")
        #expect(ConfigCommands.canonical("nodot") == "nodot")
    }

    @Test func validKeysNeedASectionAndAName() {
        #expect(ConfigCommands.isValidKey("merge.conflictStyle"))
        #expect(ConfigCommands.isValidKey("remote.origin.url"))
        #expect(ConfigCommands.isValidKey("branch.feature/graph-renderer.merge"))
        #expect(!ConfigCommands.isValidKey("nodot"))
        #expect(!ConfigCommands.isValidKey("a.b c"))
        #expect(!ConfigCommands.isValidKey("1abc.def"))
        #expect(!ConfigCommands.isValidKey("user.name=x"))
    }

    @Test func buildersProduceTheExactCommands() {
        #expect(ConfigCommands.set("init.defaultBranch", "trunk", scope: .global).display == "git config --global init.defaultBranch trunk")
        #expect(ConfigCommands.set("user.name", "Avery Chen", scope: .local).display == "git config --local user.name \"Avery Chen\"")
        #expect(ConfigCommands.unset("pull.ff", scope: .global).arguments == ["config", "--global", "--unset-all", "pull.ff"])
        #expect(ConfigCommands.unset("pull.ff", scope: .global).acceptedExitCodes == [0, 5])
        #expect(ConfigCommands.replace("x.multi", old: "b", new: "B", scope: .global).arguments == ["config", "--global", "--replace-all", "--fixed-value", "x.multi", "B", "b"])
        #expect(ConfigCommands.remove("x.multi", value: "a", scope: .local).arguments == ["config", "--local", "--unset-all", "--fixed-value", "x.multi", "a"])
        #expect(ConfigCommands.get("user.name", scope: .global).arguments == ["config", "--global", "-z", "--get", "user.name"])
        #expect(ConfigCommands.get("user.name").access == .read)
        #expect(ConfigCommands.set("a.b", "c", scope: .global).access == .write)
        #expect(ConfigCommands.table.arguments == ["config", "--list", "--show-scope", "--show-origin", "-z"])
        #expect(ConfigCommands.write(ConfigWrite("pull.ff", nil), scope: .global).arguments.contains("--unset-all"))
        #expect(ConfigEntry.Scope.system.isWritable == false)
        #expect(ConfigEntry.Scope.command.flag == nil)
    }

    @Test func valuesAreReadCaseInsensitivelyAndLastWins() {
        let config = Self.values([(.global, "init.defaultbranch", "main"), (.global, "rerere.enabled", "yes"), (.global, "x.multi", "a"), (.global, "x.multi", "b")])
        #expect(config.value("init.defaultBranch") == "main")
        #expect(config.bool("rerere.enabled") == true)
        #expect(config.values("x.MULTI") == ["a", "b"])
        #expect(config.value("x.multi") == "b")
        #expect(config.value("missing.key") == nil)
        #expect(ConfigBool.parse("off") == false)
        #expect(ConfigBool.parse("maybe") == nil)
    }

    @Test func zeroTerminatedValuesParse() {
        #expect(ConfigCommands.value(Data("main\0".utf8)) == "main")
        #expect(ConfigCommands.value(Data()) == nil)
        #expect(ConfigCommands.values(Data("/a\0/b c\0".utf8)) == ["/a", "/b c"])
    }

    @Test func pullModeReadsAndWritesLikeThePrototype() {
        #expect(PullMode(config: Self.values([(.global, "pull.rebase", "false")])) == .merge)
        #expect(PullMode(config: Self.values([(.global, "pull.rebase", "true")])) == .rebase)
        #expect(PullMode(config: Self.values([(.global, "pull.rebase", "merges")])) == .rebase)
        #expect(PullMode(config: Self.values([(.global, "pull.ff", "only")])) == .fastForwardOnly)
        #expect(PullMode(config: Self.values([])) == .merge)
        #expect(PullMode.merge.writes == [ConfigWrite("pull.rebase", "false"), ConfigWrite("pull.ff", nil)])
        #expect(PullMode.rebase.writes == [ConfigWrite("pull.rebase", "true"), ConfigWrite("pull.ff", nil)])
        #expect(PullMode.fastForwardOnly.writes == [ConfigWrite("pull.rebase", "false"), ConfigWrite("pull.ff", "only")])
    }

    @Test func diffAlgorithmAndSigningFollowGitDefaults() {
        #expect(DiffAlgorithm(config: Self.values([])) == .myers)
        #expect(DiffAlgorithm(config: Self.values([(.global, "diff.algorithm", "Histogram")])) == .histogram)
        #expect(SignFormat(config: Self.values([])) == .openpgp)
        #expect(SignFormat(config: Self.values([(.global, "gpg.format", "ssh")])) == .ssh)
        let signing = SigningSettings(config: Self.values([(.global, "commit.gpgsign", "true"), (.global, "user.signingkey", "~/.ssh/id_ed25519.pub"), (.global, "gpg.format", "x509")]))
        #expect(signing.commits)
        #expect(!signing.tags)
        #expect(signing.format == .x509)
        #expect(signing.key == "~/.ssh/id_ed25519.pub")
        #expect(SigningSettings.writes(signing: false) == [ConfigWrite("commit.gpgsign", "false"), ConfigWrite("tag.gpgSign", "false")])
        #expect(Identity.isValidEmail("avery@vrai.app"))
        #expect(!Identity.isValidEmail("avery"))
    }

    @Test func maintenanceRegistrationComparesResolvedPaths() {
        let repo = URL(filePath: "/var/folders/xy/T/vrai-sandbox/everyday/vrai", directoryHint: .isDirectory)
        #expect(MaintenanceCommands.isRegistered(["/private/var/folders/xy/T/vrai-sandbox/everyday/vrai"], repository: repo))
        #expect(!MaintenanceCommands.isRegistered(["/private/var/folders/xy/T/vrai-sandbox/everyday/other"], repository: repo))
        #expect(MaintenanceCommands.run(auto: true).display == "git maintenance run --auto")
        #expect(MaintenanceCommands.register.display == "git maintenance register")
        #expect(MaintenanceCommands.unregister.display == "git maintenance unregister")
        #expect(MaintenanceCommands.registered.arguments == ["config", "--global", "-z", "--get-all", "maintenance.repo"])
    }

    @Test func hookCommandsAndSummaries() throws {
        #expect(HookCommands.run("pre-commit").display == "git hook run pre-commit")
        #expect(HookCommands.run("commit-msg", arguments: ["/tmp/msg"]).arguments == ["hook", "run", "commit-msg", "--", "/tmp/msg"])
        let folder = FileManager.default.temporaryDirectory.appending(path: "vrai-hooks-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appending(path: "pre-push")
        try Data("#!/bin/sh\n# Runs the tests before every push\nswift test\n".utf8).write(to: script)
        #expect(HookCommands.summary(of: script.path(percentEncoded: false)) == "Runs the tests before every push")
        let plain = folder.appending(path: "pre-commit")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: plain)
        #expect(HookCommands.summary(of: plain.path(percentEncoded: false)) == nil)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o644)], ofItemAtPath: plain.path(percentEncoded: false))
        try HookCommands.setEnabled(true, path: plain.path(percentEncoded: false))
        #expect(FileManager.default.isExecutableFile(atPath: plain.path(percentEncoded: false)))
        let mode = try FileManager.default.attributesOfItem(atPath: plain.path(percentEncoded: false))[.posixPermissions] as? NSNumber
        #expect(mode?.uint16Value == 0o755)
        try HookCommands.setEnabled(false, path: plain.path(percentEncoded: false))
        #expect(!FileManager.default.isExecutableFile(atPath: plain.path(percentEncoded: false)))
    }

    @Test func lfsOutputParses() {
        let env = "git-lfs/3.6.1 (GitHub; darwin arm64; go 1.23.3)\ngit version 2.54.0\n\nEndpoint=https://github.com/vrai-app/vrai.git/info/lfs (auth=none)\nLocalWorkingDir=/x\ngit config filter.lfs.process = \"git-lfs filter-process\"\ngit config filter.lfs.smudge = \"git-lfs smudge -- %f\"\ngit config filter.lfs.clean = \"git-lfs clean -- %f\"\n"
        #expect(LFSCommands.version(env) == "3.6.1")
        #expect(LFSCommands.configured(env))
        #expect(!LFSCommands.configured("git-lfs/3.6.1\ngit config filter.lfs.process = \"\"\ngit config filter.lfs.clean = \"\"\n"))
        let track = "Listing tracked patterns\n    *.png (.gitattributes)\n    Assets/** (Assets/.gitattributes)\nListing excluded patterns\n    *.txt (.gitattributes)\n"
        #expect(LFSCommands.patterns(track) == ["*.png", "Assets/**"])
        #expect(LFSCommands.fileCount("a.png\nb.png\n") == 2)
        let missing = GitResult(command: LFSCommands.env, exitCode: 1, stdout: Data(), stderr: Data("git: 'lfs' is not a git command. See 'git --help'.\n".utf8), startedAt: Date(), duration: .zero)
        #expect(LFSCommands.isMissing(missing))
        #expect(LFSCommands.env.display == "git lfs env")
    }

    @Test func sshKeyParsing() {
        let key = SSHKeys.parse(publicKey: "ssh-ed25519 AAAAC3Nza avery@vrai.app", name: "id_ed25519", path: "/home/.ssh/id_ed25519.pub")
        #expect(key?.type == "ED25519")
        #expect(key?.comment == "avery@vrai.app")
        #expect(SSHKeys.parse(publicKey: "not a key", name: "x", path: "/x.pub") == nil)
        let print = SSHKeys.parseFingerprint("256 SHA256:ODyZRHcVVua+q6g0Wd3lLT8e9JxrYdPFdO5ragz333M avery@vrai.app (ED25519)\n")
        #expect(print?.fingerprint == "SHA256:ODyZRHcVVua+q6g0Wd3lLT8e9JxrYdPFdO5ragz333M")
        #expect(print?.type == "ED25519")
        #expect(SSHKeys.keyType("ssh-rsa") == "RSA")
        #expect(SSHKeys.keyType("ecdsa-sha2-nistp256") == "ECDSA")
        if let key {
            #expect(SSHKeys.matches(key, signingKey: "/home/.ssh/id_ed25519"))
            #expect(SSHKeys.matches(key, signingKey: "/home/.ssh/id_ed25519.pub"))
            #expect(SSHKeys.matches(key, signingKey: "~/.ssh/id_ed25519.pub"))
            #expect(SSHKeys.matches(key, signingKey: "key::ssh-ed25519 AAAAC3Nza"))
            #expect(!SSHKeys.matches(key, signingKey: "/home/.ssh/other.pub"))
            #expect(!SSHKeys.matches(key, signingKey: nil))
        }
    }

    @Test func globalConfigFileFollowsGitsRules() throws {
        #expect(GlobalConfigFile.path(environment: ["GIT_CONFIG_GLOBAL": "/sandbox/gitconfig", "HOME": "/u"]) == "/sandbox/gitconfig")
        let home = FileManager.default.temporaryDirectory.appending(path: "vrai-home-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let homePath = home.path(percentEncoded: false).trimmingSuffix("/")
        try FileManager.default.createDirectory(at: home.appending(path: ".config/git"), withIntermediateDirectories: true)
        #expect(GlobalConfigFile.path(environment: ["HOME": homePath]) == homePath + "/.gitconfig")
        try Data().write(to: home.appending(path: ".config/git/config"))
        #expect(GlobalConfigFile.path(environment: ["HOME": homePath]) == homePath + "/.config/git/config")
        #expect(GlobalConfigFile.display("/Users/avery/.gitconfig", environment: [:], home: "/Users/avery") == "~/.gitconfig")
        #expect(GlobalConfigFile.display("/tmp/vrai-sandbox/gitconfig", environment: ["VRAI_SANDBOX": "/tmp/vrai-sandbox"], home: "/Users/avery") == "$VRAI_SANDBOX/gitconfig")
    }

    @Test func configLockMapsToLockFileExists() {
        let result = GitResult(command: ConfigCommands.set("x.y", "1", scope: .global), exitCode: 255, stdout: Data(), stderr: Data("error: could not lock config file /tmp/s/gitconfig: File exists\n".utf8), startedAt: Date(), duration: .zero)
        #expect(ErrorClassifier.code(for: result) == .lockFileExists(path: "/tmp/s/gitconfig.lock"))
    }

    @Test func gitBinarySources() {
        #expect(GitBinaries.source(of: "/opt/homebrew/bin/git") == .homebrew)
        #expect(GitBinaries.source(of: "/Applications/Xcode.app/Contents/Developer/usr/bin/git") == .xcode)
        #expect(GitBinaries.source(of: "/Users/someone/bin/git") == .other)
        #expect(!GitBinaries.find().isEmpty)
    }
}
