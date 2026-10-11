import Foundation
@testable import VraiCore
@testable import VraiGit

enum CoverageSamples {
    static let oid = OID("0123456789abcdef0123456789abcdef01234567")!
    static let other = OID("89abcdef0123456789abcdef0123456789abcdef")!
    static let folder = URL(filePath: "/tmp/vrai-coverage", directoryHint: .isDirectory)

    @MainActor static var all: [GitCommand] {
        core + longTail + places + console + settings
    }

    static var core: [GitCommand] {
        reads + staging + sync + branches + rewrite + credentials
    }

    static var reads: [GitCommand] {
        [
            StatusParser.command,
            RepositoryLocation.command,
            RepositoryLocation.bareCommand,
            RefParser.command,
            ConfigParser.remotesCommand,
            ConfigParser.tableCommand,
            StashParser.command,
            WorktreeParser.command,
            SubmoduleParser.statusCommand,
            SubmoduleParser.gitmodulesCommand,
            ReflogParser.command(),
            BlameParser.command(path: "README.md"),
            LogParser.detailCommand(oid),
            GitCommand.read(LogParser.historyArguments(scope: ["HEAD"])),
            InteractivePlan.listCommand(onto: oid.rawValue),
            SnapshotBuilder.numstatHead,
            SnapshotBuilder.numstatCached,
            SnapshotBuilder.numstatWorktree,
            StagingService.headCommand,
            StagingService.symbolicHeadCommand,
            CommitService.lastMessageCommand
        ]
    }

    static var staging: [GitCommand] {
        [
            StagingService.stageCommand(paths: ["README.md"]),
            StagingService.unstageCommand(paths: ["README.md"], unborn: false),
            StagingService.stageAllCommand(includeUntracked: true),
            StagingService.unstageAllCommand(unborn: false),
            StagingService.discardTrackedCommand(paths: ["README.md"]),
            StagingService.cleanCommand(paths: ["notes.txt"]),
            StagingService.restoreCommand(path: "README.md", source: oid.rawValue),
            StagingService.applyCommand(Data(), cached: true, reverse: false),
            StagingService.diffCommand(path: "README.md", oldPath: nil, staged: false, untracked: false),
            SubmoduleParser.stageCommand(paths: ["Vendor/cmark-gfm"]),
            CommitService.command(CommitMessage(subject: "Coverage")),
            MessageCommands.mergeMessage([MergeHead(oid: oid, name: "feature/x", kind: .branch)]),
            MessageCommands.cleanup("Merge branch 'feature/x'\n\n# Conflicts:\n"),
            MessageCommands.addTrailers([.coAuthor(name: "Mira", email: "mira@vrai.app")], to: "Coverage\n")
        ]
    }

    static var sync: [GitCommand] {
        [
            SyncCommands.fetch(),
            SyncCommands.fetchBranch(remote: "origin", branch: "main"),
            SyncCommands.backgroundFetch(),
            SyncCommands.pull(mode: .rebase),
            SyncCommands.push(remote: "origin", refspec: "main"),
            SyncCommands.deleteRemoteBranch(remote: "origin", name: "old"),
            SyncCommands.pushTag(name: "v1.0.0", remote: "origin"),
            SyncCommands.deleteRemoteTag(name: "v1.0.0", remote: "origin"),
            SyncCommands.addRemote(name: "mira", url: "https://example.com/mira.git"),
            SyncCommands.renameRemote(from: "mira", to: "upstream"),
            SyncCommands.setRemoteURL(name: "origin", url: "https://example.com/vrai.git"),
            SyncCommands.unsetRemotePushURL(name: "origin"),
            SyncCommands.setRemotePrune(name: "origin", prune: true),
            SyncCommands.removeRemote(name: "mira")
        ]
    }

    static var branches: [GitCommand] {
        [
            BranchCommands.create(name: "feature/x", switchTo: true),
            BranchCommands.switchTo("main"),
            BranchCommands.track("origin/main"),
            BranchCommands.detach(at: oid.rawValue),
            BranchCommands.stashForSwitch(),
            BranchCommands.delete(name: "feature/x", force: false),
            BranchCommands.rename(from: "feature/x", to: "feature/y"),
            BranchCommands.setUpstream(branch: "main", upstream: "origin/main"),
            BranchCommands.createTag(name: "v1.0.0", message: "Release"),
            BranchCommands.deleteTag(name: "v1.0.0")
        ]
    }

    static var rewrite: [GitCommand] {
        var out: [GitCommand] = [
            RewriteCommands.merge(source: "feature/x", mode: .mergeCommit),
            RewriteCommands.checkout(.ours, path: "README.md"),
            RewriteCommands.remove(path: "README.md"),
            RewriteCommands.add(path: "README.md"),
            RewriteCommands.unmergedStages(path: "README.md"),
            RewriteCommands.mergeFile(ours: oid, base: other, theirs: oid),
            RewriteCommands.abort(.rebase),
            RewriteCommands.rebase(onto: "main"),
            RewriteCommands.interactiveRebase(onto: "main"),
            RewriteCommands.replay(onto: "main", branch: "feature/x"),
            RewriteCommands.updateRefs([RefUpdate(ref: "refs/heads/main", new: oid, old: other)], reason: "coverage"),
            RewriteCommands.refreshIndex,
            RewriteCommands.moveWorktree(from: other, to: oid),
            RewriteCommands.cherryPick(ids: [oid]),
            RewriteCommands.revert(id: oid),
            RewriteCommands.reset(to: oid.rawValue, mode: .keep),
            RewriteCommands.stashCreate,
            RewriteCommands.stash(message: "coverage"),
            RewriteCommands.applyStash(index: 0),
            RewriteCommands.dropStash(index: 0),
            RewriteCommands.branchFromStash(index: 0, name: "from-stash"),
            RewriteCommands.startBisect(bad: "HEAD", good: oid.rawValue),
            RewriteCommands.markBisect(.good),
            RewriteCommands.endBisect,
            ConflictRestart.mergeOneFile(path: "README.md", stages: UnmergedStages(base: .init(oid: other, mode: "100644"), ours: .init(oid: oid, mode: "100644"), theirs: .init(oid: oid, mode: "100644"))),
            ConflictRestart.mergeIndex(paths: ["README.md"]),
            ConflictRestart.mergedBlob(path: "README.md")
        ]
        for operation in [OperationInProgress.merge, .rebase, .applyingPatches, .cherryPick, .revert] {
            if let command = RewriteCommands.continueOperation(operation) { out.append(command) }
            if let command = RewriteCommands.skip(operation) { out.append(command) }
        }
        return out
    }

    static var credentials: [GitCommand] {
        let git = GitProcess(executable: GitExecutable(url: URL(filePath: "/usr/bin/git"), version: GitVersion(2, 54)), workingDirectory: folder, environment: GitEnvironment(base: [:]))
        let store = CredentialStore(git: git)
        return [store.approveCommand(), store.rejectCommand()]
    }
}
