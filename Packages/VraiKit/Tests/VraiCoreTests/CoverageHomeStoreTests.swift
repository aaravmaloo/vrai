import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct CoverageHomeStoreTests {
    static let lane = "Sources/VraiGit/Graph/LaneLayout.swift"
    static let cell = "Sources/VraiUI/History/GraphCell.swift"
    static let mergeLabels = ConflictLabels(ours: "HEAD", base: "base", theirs: "mira/spike/metal-graph")

    func conflicted() async throws -> (Scratch, RepositoryStore) {
        let scratch = try await Scratch.copy("conflict")
        let store = try scratch.store()
        try await store.refresh()
        return (scratch, store)
    }

    func looseCount(_ repository: URL) async throws -> Int {
        let output = try await Sandbox.git(at: repository).run(.read(["count-objects", "-v"])).output
        let line = output.split(separator: "\n").first { $0.hasPrefix("count: ") } ?? "count: 0"
        return Int(line.dropFirst("count: ".count)) ?? 0
    }

    @Test func startOverRecreatesTheConflictedMerge() async throws {
        let (scratch, store) = try await conflicted()
        defer { scratch.remove() }
        let original = try scratch.file(Self.lane)
        try await store.resolve(path: Self.lane, block: 1, with: .ours)
        #expect(try scratch.file(Self.lane) != original)
        #expect(try await store.startOver(path: Self.lane))
        #expect(try scratch.file(Self.lane) == original)
        #expect(try await scratch.git(["ls-files", "-u", "--", Self.lane]).split(separator: "\n").count == 3)
        #expect(scratch.log.commands.contains { $0.hasPrefix("git merge-one-file ") && $0.hasSuffix("100644 100644 100644") })
    }

    @Test func startOverWithEveryFileRunsMergeIndex() async throws {
        let (scratch, store) = try await conflicted()
        defer { scratch.remove() }
        let original = try scratch.file(Self.lane)
        try Data("edited\n".utf8).write(to: scratch.repository.appending(path: Self.lane))
        try Data("edited\n".utf8).write(to: scratch.repository.appending(path: Self.cell))
        let paths = try await store.startOverEveryFile()
        #expect(Set(paths) == [Self.lane, Self.cell])
        #expect(try scratch.file(Self.lane) == original)
        #expect(ConflictLabels.parse(try scratch.file(Self.cell)) == Self.mergeLabels)
        #expect(scratch.log.commands.contains { $0.hasPrefix("git merge-index -o -q git-merge-one-file -- ") })
        #expect(try await scratch.git(["ls-files", "-u"]).split(separator: "\n").count == 6)
    }

    @Test func startOverRefusesAPathWithoutBothSides() async throws {
        let (scratch, store) = try await conflicted()
        defer { scratch.remove() }
        await #expect(throws: GitError.self) { try await store.startOver(path: "README.md") }
    }

    @Test func rerereReplaysShowInTheConflictView() async throws {
        let (scratch, store) = try await conflicted()
        defer { scratch.remove() }
        #expect(await store.rerereActive())
        #expect(await store.replayedResolutions().isEmpty)
        try await scratch.git(["checkout", "--ours", "--", Self.lane, Self.cell])
        try await scratch.git(["add", "--", Self.lane, Self.cell])
        try await scratch.git(["commit", "-q", "--no-edit"])
        try await scratch.git(["reset", "-q", "--hard", "HEAD~1"])
        let merge = try await scratch.result(["merge", "--no-edit", "refs/heads/mira/spike/metal-graph"])
        #expect(merge.exitCode == 1)
        #expect((merge.output + merge.errorOutput).contains("using previous resolution"))
        try await store.refresh()
        #expect(store.snapshot?.conflicts.count == 2)
        #expect(await store.replayedResolutions() == [Self.lane, Self.cell])
        #expect(scratch.log.commands.contains("git rerere remaining"))
        try await scratch.git(["config", "rerere.enabled", "false"])
        #expect(!(await store.rerereActive()))
        #expect(await store.replayedResolutions().isEmpty)
    }

    @Test func compareWithBeforeRebaseRunsRangeDiffInTheConsole() async throws {
        let fixture = try await ConsoleFixture.make()
        defer { fixture.remove() }
        _ = try await fixture.copy.git(["reset", "-q", "--hard"])
        _ = try await fixture.copy.git(["clean", "-q", "-fd"])
        try await fixture.store.refresh()
        #expect(try await fixture.store.compareWithBeforeRebase(branch: "feature/graph-renderer") == nil)
        #expect(try await fixture.store.rebase(onto: "origin/main") == .rebased(commits: 3))
        let result = try #require(try await fixture.store.compareWithBeforeRebase(branch: "feature/graph-renderer"))
        #expect(result.command.display == "git range-diff refs/heads/feature/graph-renderer@{1}...refs/heads/feature/graph-renderer")
        #expect(result.output.contains("Graph: assign lane colors from branch tips"))
        let entry = try #require(fixture.console.entry(for: result))
        #expect(fixture.console.isExpanded(entry.id))
        #expect(try await fixture.store.compareWithBeforeRebase(branch: "main") == nil)
    }

    @Test func annotateRunsInTheConsole() async throws {
        let fixture = try await ConsoleFixture.make()
        defer { fixture.remove() }
        let result = try await fixture.store.annotate(path: "README.md", at: "HEAD")
        #expect(result.command.display == "git annotate HEAD -- README.md")
        #expect(result.output.contains("\t("))
        let entry = try #require(fixture.console.entry(for: result))
        #expect(fixture.console.isExpanded(entry.id))
    }

    @Test func packLooseObjectsAndFindRedundantPacks() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        let store = try scratch.store()
        try await store.refresh()
        #expect(try await store.redundantPacks().isEmpty)
        let summary = try await store.packLooseObjects()
        #expect(summary.packed > 0)
        #expect(summary.packsAfter == summary.packsBefore + 1)
        #expect(scratch.log.commands.contains { $0.hasPrefix("git pack-objects --revs --all") })
        #expect(scratch.log.commands.contains("git prune-packed"))
        #expect(try await store.redundantPacks().isEmpty)
        try await scratch.git(["repack", "-a", "-q"])
        #expect(try await store.redundantPacks().count == 1)
        #expect(scratch.log.commands.contains("git pack-redundant --i-still-use-this --all"))
        let again = try await store.packLooseObjects()
        #expect(again.packed == 0)
        #expect(again.packsAfter == again.packsBefore)
    }

    @Test func recoverObjectsFromAPackFile() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        let head = try await scratch.oid("HEAD")
        let base = scratch.root.appending(path: "export").path(percentEncoded: false)
        let hash = try await scratch.git(["pack-objects", "--revs", "--all", "-q", base], stdin: Data())
        let pack = scratch.root.appending(path: "export-\(hash).pack")
        let empty = scratch.root.appending(path: "empty", directoryHint: .isDirectory)
        try await scratch.git(["init", "-q", empty.path(percentEncoded: false)])
        let git = try Sandbox.git(at: empty)
        #expect(try await git.runAllowingFailure(.read(["cat-file", "-e", head.rawValue])).exitCode != 0)
        let store = RepositoryStore(git: git)
        let added = try await store.recoverObjects(fromPack: pack)
        #expect(added > 0)
        #expect(try await git.runAllowingFailure(.read(["cat-file", "-e", head.rawValue])).exitCode == 0)
        #expect(try await store.recoverObjects(fromPack: pack) == 0)
    }

    @Test func mergeMessageCleanupAndTrailers() async throws {
        let store = RepositoryStore(git: try Sandbox.git("everyday/vrai"))
        try await store.refresh()
        #expect(await store.mergeHead(for: "feature/line-staging")?.kind == .branch)
        #expect(await store.mergeHead(for: "origin/main")?.kind == .remoteBranch)
        #expect(await store.mergeHead(for: "v0.9.1")?.kind == .tag)
        #expect(await store.mergeHead(for: "no-such-branch") == nil)
        #expect(await store.defaultMergeMessage(source: "feature/line-staging") == "Merge branch 'feature/line-staging' into feature/graph-renderer")
        #expect(await store.defaultMergeMessage(source: "origin/main") == "Merge remote-tracking branch 'origin/main' into feature/graph-renderer")
        #expect(await store.defaultMergeMessage(source: "no-such-branch") == nil)

        #expect(await store.cleanMessage("Merge branch 'x' into y\n\n# Conflicts:\n#\tREADME.md\n\n\n\nWhy   \n") == "Merge branch 'x' into y\n\nWhy\n")

        let mira = Trailer.coAuthor(name: "Mira Okafor", email: "mira@vrai.app")
        let once = try await store.addTrailers([mira], to: CommitMessage(subject: "Graph: snap nodes", body: "Keeps lanes aligned."))
        #expect(once == CommitMessage(subject: "Graph: snap nodes", body: "Keeps lanes aligned.\n\nCo-authored-by: Mira Okafor <mira@vrai.app>"))
        #expect(try await store.addTrailers([mira], to: once) == once)
        #expect(try await store.addTrailers([mira], to: CommitMessage(subject: "", body: "")) == CommitMessage(subject: "", body: "Co-authored-by: Mira Okafor <mira@vrai.app>"))
        #expect(try await store.addTrailers([], to: once) == once)
    }

    @Test func maintenanceRunsInEveryRegisteredRepository() async throws {
        let sandbox = try await SettingsSandbox.make(["everyday", "detached"])
        defer { sandbox.remove() }
        let store = try await sandbox.store("everyday")
        #expect(try await store.runMaintenanceEverywhere() == MaintenanceEverywhere(repositories: 0, unreachable: []))
        let other = sandbox.repository("detached")
        let gone = sandbox.root.appending(path: "gone/vrai").path(percentEncoded: false)
        let config = try sandbox.app.configProcess()
        for path in [sandbox.repository("everyday").path(percentEncoded: false), gone, other.path(percentEncoded: false)] {
            try await config.run(ConfigCommands.add(ConfigKeys.maintenanceRepo, path, scope: .global))
        }
        #expect(await store.registeredRepositories().count == 3)
        let loose = try await looseCount(other)
        #expect(loose > 0)
        let summary = try await store.runMaintenanceEverywhere()
        #expect(summary.repositories == 3)
        #expect(summary.unreachable == [gone])
        #expect(summary.ran == 2)
        #expect(try await looseCount(other) < loose)
    }

    @Test func savedPasswordsAreErasedWithCredentialStore() async throws {
        let sandbox = try await SettingsSandbox.make([])
        defer { sandbox.remove() }
        let settings = try sandbox.app.makeGitSettings()
        let helpers = await settings.credentialHelpers()
        #expect(helpers.map(\.kind) == [.store])
        #expect(helpers.first?.file?.hasSuffix("/git-credentials") == true)
        #expect(helpers.first?.file?.contains(sandbox.root.lastPathComponent) == true)
        try await sandbox.app.credentials().approve(url: "https://example.com/mira/vrai.git", username: "avery", password: "token-1")
        try await sandbox.app.credentials().approve(url: "http://intranet.example/vrai.git", username: "avery", password: "token-2")
        let before = try String(contentsOf: sandbox.credentials, encoding: .utf8)
        #expect(before.contains("example.com") && before.contains("intranet.example"))
        #expect(try await settings.deleteSavedPasswords() == 1)
        let after = try String(contentsOf: sandbox.credentials, encoding: .utf8)
        #expect(!after.contains("example.com") && !after.contains("intranet.example"))
    }

    @Test func choosingAHelperAndForgettingCachedPasswords() async throws {
        let sandbox = try await SettingsSandbox.make([])
        defer { sandbox.remove() }
        let settings = try sandbox.app.makeGitSettings()
        let git = try sandbox.app.configProcess()
        try await settings.setCredentialHelper(.cache)
        let written = try await git.run(.read(["config", "--global", "-z", "--get-all", "credential.helper"])).stdout
        #expect(ConfigCommands.values(written) == ["", "cache"])
        #expect(await settings.credentialHelpers().map(\.kind) == [.cache])
        #expect(try await settings.forgetCachedPasswords() == 1)

        try await git.run(.write(["config", "--global", "--replace-all", "credential.helper", "cache --timeout=60"]))
        let cache = CredentialStore(git: git)
        do {
            try await cache.approve(url: "https://example.com/vrai.git", username: "avery", password: "secret")
            #expect(try await cache.fill(url: "https://example.com/vrai.git")?.password == "secret")
        } catch {
            _ = try? await settings.forgetCachedPasswords()
            throw error
        }
        #expect(try await settings.forgetCachedPasswords() == 1)
        #expect(try await cache.fill(url: "https://example.com/vrai.git") == nil)

        try await settings.setCredentialHelper(.keychain)
        #expect(await settings.credentialHelpers().map(\.kind) == [.keychain])
    }
}
