import VraiCore
import VraiGit

extension CoverageSamples {
    static var console: [GitCommand] {
        let commit = "0123456789abcdef0123456789abcdef01234567"
        let built: [GitCommand] = [
            ConsoleCommands.showObject(commit),
            ConsoleCommands.addNote(commit, message: "Reviewed"),
            ConsoleCommands.addNote(commit, message: "Reviewed again", replacing: true),
            ConsoleCommands.removeNote(commit),
            ConsoleCommands.note(commit),
            ConsoleCommands.trackedFiles,
            ConsoleCommands.grep("LaneLayout"),
            ConsoleCommands.grep("LaneLayout", at: commit),
            ConsoleCommands.searchCommits("snap nodes", scope: ["--branches", "HEAD"], limit: 20),
            ConsoleCommands.resolveCommit("main~1"),
            ConsoleCommands.resolveCommit(":/Graph"),
            ConsoleCommands.recentCheckouts,
            TypedCommand(command: .read(["log", "--oneline"])).command,
        ]
        let typed = [
            "git fast-export --all",
            "git fast-import --quiet",
            "git filter-branch --tree-filter true HEAD",
            "git instaweb --stop",
            "git gitweb",
            "git show-branch main",
            "git archimport",
            "git cvsexportcommit",
            "git cvsimport",
            "git cvsserver",
            "git p4",
            "git quiltimport",
            "git svn info",
            "git hash-object README.md",
            "git mktag",
            "git mktree",
            "git commit-tree HEAD^{tree} -m snapshot",
            "git write-tree",
            "git read-tree HEAD",
            "git checkout-index --all",
            "git unpack-file HEAD:README.md",
            "git get-tar-commit-id",
            "git var GIT_EDITOR",
            "git column",
            "git sh-i18n",
            "git sh-setup",
            "git daemon --export-all",
            "git fetch-pack origin",
            "git send-pack origin",
            "git http-backend",
            "git update-server-info",
            "git refs verify",
            "git cat-file -p HEAD",
            "git ls-tree HEAD",
            "git show-ref",
            "git name-rev HEAD",
            "git notes list",
        ].compactMap { TypedCommand($0)?.command }
        return built + typed
    }
}
