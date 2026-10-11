import Foundation
import Testing
import VraiCore
import VraiGit

struct ExpertRiskTests {
    @Test func builtCommandsCarryTheRiskTagTheSheetShows() {
        #expect(TypedCommand.risk(of: RewriteCommands.reset(to: "HEAD~1", mode: .hard)) == .destructive)
        #expect(TypedCommand.risk(of: RewriteCommands.reset(to: "HEAD~1", mode: .soft)) == .rewrites)
        #expect(TypedCommand.risk(of: RewriteCommands.reset(to: "HEAD~1", mode: .mixed)) == .rewrites)
        #expect(TypedCommand.risk(of: BranchCommands.delete(name: "feature/line-staging", force: true)) == .destructive)
        #expect(TypedCommand.risk(of: BranchCommands.delete(name: "feature/line-staging", force: false)) == .safe)
        #expect(TypedCommand.risk(of: RewriteCommands.dropStash(index: 0)) == .destructive)
        #expect(TypedCommand.risk(of: SyncCommands.push(remote: "origin", refspec: "main", force: .withLease)) == .rewrites)
        #expect(TypedCommand.risk(of: SyncCommands.push(remote: "origin", refspec: "main", force: .force)) == .destructive)
        #expect(TypedCommand.risk(of: SyncCommands.push(remote: "origin", refspec: "main")) == .safe)
        #expect(TypedCommand.risk(of: StagingService.cleanCommand(paths: ["Notes/graph-perf.md"])) == .destructive)
        #expect(TypedCommand.risk(of: StagingService.discardTrackedCommand(paths: ["README.md"])) == .destructive)
        #expect(TypedCommand.risk(of: ConsoleCommands.addNote("HEAD", message: "Reviewed")) == .safe)
        #expect(TypedCommand.risk(of: ConsoleCommands.showObject("HEAD")) == .safe)
    }

    @Test func typedCommandsGetTheSameTagsAsTheirBuiltForms() throws {
        #expect(try #require(TypedCommand("git reset --hard HEAD~1")).risk == .destructive)
        #expect(try #require(TypedCommand("reset --soft HEAD~1")).risk == .rewrites)
        #expect(try #require(TypedCommand("git commit --amend --no-edit")).risk == .rewrites)
        #expect(try #require(TypedCommand("git rebase main")).risk == .rewrites)
        #expect(try #require(TypedCommand("git rebase --continue")).risk == .safe)
        #expect(try #require(TypedCommand("git branch -D feature/x")).risk == .destructive)
        #expect(try #require(TypedCommand("git stash drop")).risk == .destructive)
        #expect(try #require(TypedCommand("git filter-branch --tree-filter true HEAD")).risk == .destructive)
        #expect(try #require(TypedCommand("git push --force-with-lease origin main")).risk == .rewrites)
        #expect(try #require(TypedCommand("git status")).risk == .safe)
    }

    @Test func aBuiltCommandRunsUnchangedWhenItsPreviewIsNotEdited() {
        let samples: [GitCommand] = [
            ConsoleCommands.addNote("HEAD", message: "Reviewed by Ann \u{2018}quoted\u{2019} and \"double\" with $HOME"),
            ConsoleCommands.grep("snap nodes; rm -rf x"),
            RewriteCommands.reset(to: "HEAD~1", mode: .hard),
            SyncCommands.push(remote: "origin", refspec: "feature/line-staging", force: .withLease, setUpstream: true),
            RewriteCommands.stash(message: "WIP: lane colors", includeUntracked: true, paths: ["Docs/Design notes/Lane colors.md"]),
        ]
        for command in samples {
            let typed = TypedCommand(command: command)
            #expect(typed.command.arguments == command.arguments)
            #expect(typed.display == command.display)
            #expect(typed.changesRepository == (command.access == .write))
        }
    }

    @Test func editingAPreviewToItsOwnTextGivesTheSameArguments() throws {
        let samples: [GitCommand] = [
            ConsoleCommands.addNote("HEAD", message: "Reviewed by Ann and \"double\" with $HOME"),
            ConsoleCommands.grep("snap nodes; rm -rf x"),
            RewriteCommands.reset(to: "HEAD~1", mode: .hard),
            SyncCommands.push(remote: "origin", refspec: "feature/line-staging", force: .withLease, setUpstream: true),
            RewriteCommands.stash(message: "WIP: lane colors", includeUntracked: true, paths: ["Docs/Design notes/Lane colors.md", "Docs/Résumé des branches.md"]),
        ]
        for command in samples {
            let typed = try #require(TypedCommand(command.display))
            #expect(typed.command.arguments == command.arguments, "\(command.display)")
        }
    }

    @Test func consoleOnlyCommandsFromTheCoverageListAllParse() {
        let consoleOnly = [
            "fast-export", "fast-import", "filter-branch", "instaweb", "gitweb", "show-branch", "archimport", "cvsexportcommit",
            "cvsimport", "cvsserver", "p4", "quiltimport", "svn", "hash-object", "mktag", "mktree", "commit-tree", "write-tree",
            "read-tree", "checkout-index", "unpack-file", "get-tar-commit-id", "var", "column", "sh-i18n", "sh-setup", "daemon",
            "fetch-pack", "send-pack", "http-backend", "update-server-info"
        ]
        let covered = Set(CoverageSamples.console.compactMap(\.subcommand))
        #expect(consoleOnly.filter { !covered.contains($0) }.isEmpty)
        #expect(covered.isSuperset(of: ["cat-file", "notes", "ls-files", "grep", "log", "rev-parse"]))
        #expect(CoverageSamples.console.count == 50)
    }
}
