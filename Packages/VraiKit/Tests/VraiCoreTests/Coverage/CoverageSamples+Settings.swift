import Foundation
import VraiCore
import VraiGit

extension CoverageSamples {
    static var settings: [GitCommand] {
        [
            ConfigCommands.table,
            ConfigCommands.version,
            ConfigCommands.get("init.defaultBranch", scope: .global),
            ConfigCommands.getAll("maintenance.repo", scope: .global),
            ConfigCommands.set("pull.rebase", "true", scope: .global),
            ConfigCommands.add("x.multi", "a", scope: .local),
            ConfigCommands.replace("x.multi", old: "a", new: "b", scope: .local),
            ConfigCommands.unset("pull.ff", scope: .global),
            ConfigCommands.remove("x.multi", value: "b", scope: .local),
            ConfigCommands.write(ConfigWrite("rerere.enabled", "true"), scope: .global)
        ]
        + GitSettings.commands(PullMode.fastForwardOnly.writes + GitSettings.autostashWrites(true) + SigningSettings.writes(signing: true))
        + GitSettings.commands(RepositoryStore.localIdentityWrites(Identity(name: "Avery Chen", email: "avery@vrai.app")), scope: .local)
        + [
            MaintenanceCommands.register,
            MaintenanceCommands.unregister,
            MaintenanceCommands.run(),
            MaintenanceCommands.run(auto: true),
            MaintenanceCommands.registered,
            HookCommands.run("pre-commit"),
            HookCommands.run("commit-msg", arguments: ["COMMIT_EDITMSG"]),
            LFSCommands.env,
            LFSCommands.track,
            LFSCommands.files,
            StatusParser.command(renameThreshold: 60),
            SnapshotBuilder.numstatHead(renameThreshold: 60),
            SnapshotBuilder.numstatCached(renameThreshold: 60),
            StagingService.diffCommand(path: "README.md", oldPath: nil, staged: true, untracked: false, renameThreshold: 60),
            CredentialStore(git: GitProcess(executable: GitExecutable(url: URL(filePath: GitExecutable.commandLineToolsShim), version: GitVersion.minimum), workingDirectory: URL(filePath: NSTemporaryDirectory()), environment: .user()), helper: nil).rejectCommand()
        ]
    }
}
