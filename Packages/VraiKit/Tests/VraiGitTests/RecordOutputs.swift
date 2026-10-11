import Foundation
import Testing
@testable import VraiGit

struct RecordOutputs {
    static let enabled = ProcessInfo.processInfo.environment["VRAI_RECORD"] == "1"

    static func commands(blamePath: String?) -> [(String, GitCommand)] {
        var list: [(String, GitCommand)] = [
            ("location", RepositoryLocation.command),
            ("status", StatusParser.command),
            ("refs", RefParser.command),
            ("remotes", ConfigParser.remotesCommand),
            ("stashes", StashParser.command),
            ("worktrees", WorktreeParser.command),
            ("submodule-status", SubmoduleParser.statusCommand),
            ("gitmodules", SubmoduleParser.gitmodulesCommand),
            ("submodule-stage", SubmoduleParser.stageCommand(paths: ["Vendor/libgit2", "Vendor/cmark-gfm", "Vendor/swift-argument-parser"])),
            ("reflog", ReflogParser.command()),
            ("config", ConfigParser.tableCommand),
            ("history", .read(LogParser.historyArguments(scope: ["--branches", "--remotes", "--tags", "HEAD"]), acceptedExitCodes: [0, 128])),
            ("signatures", .read(["log", "-z", "--format=" + LogParser.signatureFormat, "--branches", "--remotes", "--tags", "HEAD", "--"], acceptedExitCodes: [0, 128])),
            ("detail-head", .read(["show", "-z", "--decorate=full", "--raw", "--numstat", "--find-renames=50%", "--first-parent", "-m", "--format=" + LogParser.detailFormat, "HEAD", "--"], acceptedExitCodes: [0, 128])),
            ("diff-worktree", .read(["diff", "--no-color", "--no-ext-diff", "--find-renames"])),
            ("diff-cached", .read(["diff", "--cached", "--no-color", "--no-ext-diff", "--find-renames"])),
            ("numstat-head", .read(["diff", "HEAD", "--numstat", "-z", "--find-renames", "--no-ext-diff", "--ignore-submodules=dirty"], acceptedExitCodes: [0, 128]))
        ]
        if let blamePath { list.append(("blame", BlameParser.command(path: blamePath, at: "HEAD"))) }
        return list
    }

    static let fixtures: [(name: String, repo: String, blame: String?)] = [
        ("everyday", "everyday/vrai", "Sources/VraiGit/Graph/LaneLayout.swift"),
        ("conflict", "conflict/vrai", nil),
        ("rebase", "rebase/vrai", nil),
        ("detached", "detached/vrai", nil),
        ("bisect", "bisect/vrai", nil),
        ("empty", "empty/pocket-notes", nil),
        ("edge", "edge/edge", "Résumé.md"),
        ("worktree-review", "everyday/vrai-review", nil)
    ]

    @Test(.enabled(if: enabled && TestSandbox.available))
    func recordFixtureOutputs() async throws {
        for fixture in Self.fixtures {
            let git = try TestSandbox.process(fixture.repo)
            let folder = Recorded.directory.appending(path: fixture.name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, command) in Self.commands(blamePath: fixture.blame) {
                let result = try await git.runAllowingFailure(command)
                try Recorded.normalize(result.stdout).write(to: folder.appending(path: name + ".out"))
            }
            let conflicted = try await git.runAllowingFailure(.read(["diff", "--name-only", "--diff-filter=U", "-z"]))
            for path in ParseSupport.nulFields(conflicted.stdout) where !path.isEmpty {
                let source = TestSandbox.repository(fixture.repo).appending(path: path)
                if let data = try? Data(contentsOf: source) {
                    try data.write(to: folder.appending(path: "conflict-" + path.replacingOccurrences(of: "/", with: "_") + ".txt"))
                }
            }
        }
        let errors = Recorded.directory.appending(path: "errors", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: errors, withIntermediateDirectories: true)
        let cases: [(String, String, GitCommand)] = [
            ("offline-fetch", "offline/vrai", .write(["fetch", "origin"])),
            ("push-rejected", "push-rejected/vrai", .write(["push", "origin", "feature/graph-renderer"])),
            ("unknown-revision", "everyday/vrai", .read(["log", "no-such-branch", "--"])),
            ("branch-exists", "everyday/vrai", .write(["branch", "main"])),
            ("invalid-branch-name", "everyday/vrai", .write(["branch", "bad..name"])),
            ("not-fully-merged", "edge/edge", .write(["branch", "-d", "other"])),
            ("checked-out-elsewhere", "everyday/vrai", .write(["switch", "release/0.9"])),
            ("local-changes", "everyday/vrai", .write(["switch", "main"])),
            ("nothing-to-stash", "detached/vrai", .write(["stash", "push"])),
            ("not-a-repository", "", .read(["status"]))
        ]
        for (name, repo, command) in cases {
            let git = try TestSandbox.process(repo)
            let result = try await git.runAllowingFailure(command)
            try Recorded.normalize(result.stderr).write(to: errors.appending(path: name + ".err"))
            try Recorded.normalize(result.stdout).write(to: errors.appending(path: name + ".out"))
            try Data("\(result.exitCode)\n\(command.arguments.joined(separator: " "))\n".utf8).write(to: errors.appending(path: name + ".meta"))
        }
    }
}
