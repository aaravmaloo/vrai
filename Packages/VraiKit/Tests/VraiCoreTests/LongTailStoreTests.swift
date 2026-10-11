import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct LongTailStoreTests {
    static let branch = "refs/heads/feature/graph-renderer"

    func prepared() async throws -> (Scratch, RepositoryStore) {
        let scratch = try await Scratch.copy("everyday")
        try await scratch.clean()
        let store = try scratch.store()
        try await store.refresh()
        return (scratch, store)
    }

    func message(_ scratch: Scratch, _ revision: String) async throws -> String {
        try await scratch.git(["log", "-1", "--format=%B", revision])
    }

    func subjects(_ scratch: Scratch, _ range: String) async throws -> [String] {
        try await scratch.git(["log", "--format=%s", range]).split(separator: "\n").map(String.init)
    }

    func files(_ scratch: Scratch, _ revision: String) async throws -> [String] {
        try await scratch.git(["diff-tree", "--no-commit-id", "-r", "--name-only", revision]).split(separator: "\n").map(String.init).sorted()
    }

    @Test func fixupCommitTargetsTheCommitAndUndoes() async throws {
        let (scratch, store) = try await prepared()
        defer { scratch.remove() }
        let target = try await scratch.oid("HEAD~1")
        let before = try await scratch.oid("HEAD")
        await expectGitError("nothingToCommit") { try await store.fixupCommit(for: target) }
        try Data("// fix\n".utf8).write(to: scratch.repository.appending(path: "Sources/VraiUI/History/GraphCell.swift"), options: .atomic)
        try await scratch.git(["add", "--", "Sources/VraiUI/History/GraphCell.swift"])
        #expect(await store.hasStagedChanges())
        let tip = try await store.fixupCommit(for: target)
        #expect(try await scratch.oid("HEAD") == tip)
        #expect(try await message(scratch, "HEAD") == "fixup! Graph: keep the HEAD halo above merge rings")
        #expect(store.fixupCommitCommand(for: target).display == "git commit --fixup=" + target.rawValue)
        let entry = try #require(await store.recorded.first)
        #expect(entry.kind == .fixup)
        #expect(entry.label == "Created fixup commit for \(target.short)")
        try await store.undoLast()
        #expect(try await scratch.oid("HEAD") == before)
    }

    @Test func rewordWithHistoryKeepsLaterCommits() async throws {
        let (scratch, store) = try await prepared()
        defer { scratch.remove() }
        let target = try await scratch.oid("HEAD~1")
        let tipBefore = try await scratch.oid("HEAD")
        #expect(await store.usesHistory(for: target))
        #expect(store.rewordCommand(id: target).display == "git history reword " + target.rawValue)
        #expect(store.rewordCommand(id: target).risk == .rewrites)
        try await store.reword(id: target, message: CommitMessage(subject: "Graph: keep the halo on top", body: "Rings stay below it."))
        #expect(try await message(scratch, "HEAD~1") == "Graph: keep the halo on top\n\nRings stay below it.")
        #expect(try await subjects(scratch, "-3") == ["Graph: draw merge curves with cubic béziers", "Graph: keep the halo on top", "Graph: assign lane colors from branch tips"])
        #expect(try await scratch.oid("HEAD") != tipBefore)
        let entry = try #require(await store.recorded.first)
        #expect(entry.kind == .reword)
        try await store.undoLast()
        #expect(try await scratch.oid("HEAD") == tipBefore)
    }

    @Test func rewordFallsBackToARebasePlan() async throws {
        let (scratch, store) = try await prepared()
        defer { scratch.remove() }
        let target = try await scratch.oid("HEAD~2")
        let tipBefore = try await scratch.oid("HEAD")
        try await store.reword(id: target, message: CommitMessage(subject: "Graph: colors follow branch tips"), useHistory: false)
        #expect(try await subjects(scratch, "-3") == ["Graph: draw merge curves with cubic béziers", "Graph: keep the HEAD halo above merge rings", "Graph: colors follow branch tips"])
        #expect(store.snapshot?.state == .clean)
        try await store.undoLast()
        #expect(try await scratch.oid("HEAD") == tipBefore)
    }

    @Test func splitWithHistoryMovesPickedFilesIntoASecondCommit() async throws {
        let (scratch, store) = try await prepared()
        defer { scratch.remove() }
        let target = try await scratch.oid("HEAD~2")
        let tipBefore = try await scratch.oid("HEAD")
        let listed = try await store.commitFiles(id: target)
        #expect(listed.map(\.path).sorted() == ["Sources/VraiGit/Graph/LaneLayout.swift", "Sources/VraiUI/History/Palette.swift"])
        try await store.split(id: target, moving: ["Sources/VraiUI/History/Palette.swift"], secondSubject: "Graph: add the palette file")
        #expect(try await subjects(scratch, "-4") == ["Graph: draw merge curves with cubic béziers", "Graph: keep the HEAD halo above merge rings", "Graph: add the palette file", "Graph: assign lane colors from branch tips"])
        #expect(try await files(scratch, "HEAD~2") == ["Sources/VraiUI/History/Palette.swift"])
        #expect(try await files(scratch, "HEAD~3") == ["Sources/VraiGit/Graph/LaneLayout.swift"])
        #expect(try await scratch.git(["diff", tipBefore.rawValue, "HEAD", "--stat"]).isEmpty)
        let entry = try #require(await store.recorded.first)
        #expect(entry.kind == .split)
        try await store.undoLast()
        #expect(try await scratch.oid("HEAD") == tipBefore)
    }

    @Test func splitFallsBackToAnEditStop() async throws {
        let (scratch, store) = try await prepared()
        defer { scratch.remove() }
        let target = try await scratch.oid("HEAD~2")
        let tipBefore = try await scratch.oid("HEAD")
        try await store.split(id: target, moving: ["Sources/VraiUI/History/Palette.swift"], secondSubject: "Graph: add the palette file", useHistory: false)
        #expect(store.snapshot?.state == .clean)
        #expect(try await subjects(scratch, "-4") == ["Graph: draw merge curves with cubic béziers", "Graph: keep the HEAD halo above merge rings", "Graph: add the palette file", "Graph: assign lane colors from branch tips"])
        #expect(try await files(scratch, "HEAD~2") == ["Sources/VraiUI/History/Palette.swift"])
        #expect(try await scratch.git(["log", "-1", "--format=%an", "HEAD~2"]) == (try await scratch.git(["log", "-1", "--format=%an", target.rawValue])))
        #expect(try await scratch.git(["diff", tipBefore.rawValue, "HEAD", "--stat"]).isEmpty)
    }

    @Test func splitNeedsAProperSubset() async throws {
        let (scratch, store) = try await prepared()
        defer { scratch.remove() }
        let target = try await scratch.oid("HEAD~2")
        await expectGitError("unknown") { try await store.split(id: target, moving: [], secondSubject: "x") }
        await expectGitError("emptyMessage") { try await store.split(id: target, moving: ["Sources/VraiUI/History/Palette.swift"], secondSubject: " ") }
    }

    @Test func savePatchesArchivesAndBundles() async throws {
        let (scratch, store) = try await prepared()
        defer { scratch.remove() }
        let out = scratch.root.appending(path: "out", directoryHint: .isDirectory)
        let ids = [try await scratch.oid("HEAD~1"), try await scratch.oid("HEAD")]
        let patches = try await store.savePatches(ids: ids, to: out.appending(path: "patches", directoryHint: .isDirectory))
        #expect(patches.count == 2)
        #expect(patches[0].lastPathComponent.hasPrefix("0001-Graph-keep-the-HEAD-halo"))
        #expect(patches[1].lastPathComponent.hasPrefix("0002-Graph-draw-merge-curves"))
        #expect(patches.allSatisfy { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) })
        #expect(store.sendEmailCommand(files: patches).subcommand == "send-email")
        #expect(store.imapSendCommand().display == "git imap-send")
        let zip = try await store.exportArchive(ref: "v0.9.1", format: .zip, prefix: "vrai-0.9.1/", to: out.appending(path: "vrai-0.9.1.zip"))
        #expect(FileManager.default.fileExists(atPath: zip.path(percentEncoded: false)))
        let tar = try await store.exportArchive(ref: "HEAD", format: .tar, prefix: "vrai/", paths: ["Sources"], to: out.appending(path: "vrai.tar"))
        #expect(await store.archiveCommitID(tar) == (try await scratch.git(["rev-parse", "HEAD"])))
        let tgz = try await store.exportArchive(ref: "main", format: .tarGz, prefix: "", to: out.appending(path: "main.tar.gz"))
        #expect(((try? tgz.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0)
        let bundle = try await store.createBundle(refs: [], to: out.appending(path: "vrai.bundle"))
        #expect(try await scratch.git(["bundle", "verify", "--quiet", bundle.path(percentEncoded: false)]).isEmpty)
        #expect(store.bundleCommand(refs: [], to: bundle).arguments.contains("--all"))
    }

    @Test func applyPatchesFromAnotherBranchAndUndo() async throws {
        let (scratch, store) = try await prepared()
        defer { scratch.remove() }
        let out = scratch.root.appending(path: "mail", directoryHint: .isDirectory)
        try await scratch.git(["format-patch", "-q", "-o", out.path(percentEncoded: false), "6fc67b3..feature/line-staging"])
        let files = try FileManager.default.contentsOfDirectory(at: out, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(files.count == 2)
        let summaries = await store.patchSummaries(files: files)
        #expect(summaries.map(\.subject) == ["Diff: track selected line ranges per hunk", "Diff: stage individual lines from the gutter"])
        #expect(summaries.allSatisfy { !$0.author.isEmpty && !$0.email.isEmpty })
        #expect(await store.appliedPatchFiles(files).isEmpty)
        let before = try await scratch.oid("HEAD")
        let applied = try await store.applyPatches(files: files, threeWay: true, signoff: true)
        #expect(applied == 2)
        #expect(try await subjects(scratch, "-2") == ["Diff: stage individual lines from the gutter", "Diff: track selected line ranges per hunk"])
        #expect(try await message(scratch, "HEAD").contains("Signed-off-by: Avery Chen <avery@vrai.app>"))
        #expect(await store.appliedPatchFiles(files) == Set(files))
        let entry = try #require(await store.recorded.first)
        #expect(entry.kind == .applyPatches)
        try await store.undoLast()
        #expect(try await scratch.oid("HEAD") == before)
    }

    @Test func applyPatchesThatConflictStopLikeARebase() async throws {
        let (scratch, store) = try await prepared()
        defer { scratch.remove() }
        let out = scratch.root.appending(path: "mail", directoryHint: .isDirectory)
        try await scratch.git(["format-patch", "-q", "-o", out.path(percentEncoded: false), "-1", "HEAD"])
        try await scratch.git(["reset", "-q", "--hard", "HEAD~1"])
        try Data("changed\n".utf8).write(to: scratch.repository.appending(path: "Sources/VraiGit/Graph/LaneLayout.swift"))
        try await scratch.git(["commit", "-q", "-am", "Change the layout"])
        let files = try FileManager.default.contentsOfDirectory(at: out, includingPropertiesForKeys: nil)
        do {
            try await store.applyPatches(files: files, threeWay: false, signoff: false)
            Issue.record("expected the patch to stop")
        } catch is GitError {}
        guard case .applyingPatches = store.snapshot?.state else {
            Issue.record("expected the am state, got \(String(describing: store.snapshot?.state))")
            return
        }
        try await store.abort()
        #expect(store.snapshot?.state == .clean)
    }

    @Test func sparseCheckoutSetsAndDisables() async throws {
        let (scratch, store) = try await prepared()
        defer { scratch.remove() }
        var state = await store.sparseState()
        #expect(!state.enabled)
        #expect(state.available.contains("Sources"))
        #expect(store.sparseCommand(folders: ["Sources"]).display == "git sparse-checkout set --cone Sources")
        let changed = await store.lastModified(paths: ["Sources", "Docs"])
        let sources = try #require(changed["Sources"])
        #expect(sources.id == (try await scratch.oid("HEAD")))
        #expect(sources.subject == "Graph: draw merge curves with cubic béziers")
        #expect(changed["Docs"] != nil)
        #expect(LongTailCommands.lastModified(["Sources"]).display == "git last-modified -z HEAD -- Sources")
        try await store.setSparseCheckout(dirs: ["Sources"])
        state = await store.sparseState()
        #expect(state.enabled)
        #expect(state.folders == ["Sources"])
        #expect(!scratch.exists("Vrai/Info.plist"))
        #expect(scratch.exists("Sources/VraiUI/History/GraphCell.swift"))
        let info = try await store.repositoryInfo()
        #expect(info.sparse)
        try await store.disableSparseCheckout()
        #expect(!(await store.sparseState().enabled))
        #expect(scratch.exists("Vrai/Info.plist"))
    }

    @Test func textFilesIgnoreAndMailmap() async throws {
        let (scratch, store) = try await prepared()
        defer { scratch.remove() }
        #expect(try await store.readTextFile(.gitignore) == "")
        try await store.writeTextFile(.gitattributes, contents: "*.png binary")
        #expect(try await store.readTextFile(.gitattributes) == "*.png binary\n")
        let attributes = await store.attributes(for: ["logo.png"])
        #expect(attributes["logo.png"]?["binary"] == "set")
        let result = try await store.ignore(pattern: RepositoryStore.ignorePattern(forExtension: "log"))
        #expect(result.added)
        #expect(result.rule?.hasPrefix(".gitignore:1:*.log") == true)
        let again = try await store.ignore(pattern: "*.log")
        #expect(!again.added)
        #expect(RepositoryStore.ignorePattern(forPath: "Notes/todo [draft].md") == "/Notes/todo \\[draft\\].md")
        try await store.ignore(pattern: RepositoryStore.ignorePattern(forPath: "Notes/scratch.txt"))
        #expect(try await store.readTextFile(.gitignore) == "*.log\n/Notes/scratch.txt\n")
        let people = await store.contributors()
        #expect(people.count >= 3)
        let first = try #require(people.first)
        let preview = await store.mailmapPreview(contents: "Someone Else <else@vrai.app> \(first.name) <\(first.email)>\n")
        #expect(preview.count == 1)
        #expect(preview.first?.to == "Someone Else <else@vrai.app>")
    }

    @Test func indexFlagsAndIntentToAdd() async throws {
        let (scratch, store) = try await prepared()
        defer { scratch.remove() }
        let path = "Sources/VraiUI/History/GraphCell.swift"
        try Data("// edited\n".utf8).write(to: scratch.repository.appending(path: path))
        try await store.setAssumeUnchanged(paths: [path], on: true)
        #expect(!(try await scratch.git(["status", "--porcelain"])).contains(path))
        try await store.setAssumeUnchanged(paths: [path], on: false)
        #expect(try await scratch.git(["status", "--porcelain"]).contains(path))
        try await store.setSkipWorktree(paths: [path], on: true)
        #expect(try await scratch.git(["ls-files", "-v", "--", path]).hasPrefix("S "))
        try await store.setSkipWorktree(paths: [path], on: false)
        try Data("new\n".utf8).write(to: scratch.repository.appending(path: "Draft.md"))
        try await store.intentToAdd(paths: ["Draft.md"])
        #expect(try await scratch.git(["diff", "--name-only"]).contains("Draft.md"))
        #expect(try await scratch.git(["ls-files", "--", "Draft.md"]) == "Draft.md")
    }

    @Test func cleanListsFirstThenRemovesWithUndo() async throws {
        let (scratch, store) = try await prepared()
        defer { scratch.remove() }
        try await store.writeTextFile(.gitignore, contents: "build/\n")
        try await scratch.git(["add", ".gitignore"])
        try await scratch.git(["commit", "-q", "-m", "Ignore build"])
        try Data("a\n".utf8).write(to: scratch.repository.appending(path: "loose.txt"))
        try FileManager.default.createDirectory(at: scratch.repository.appending(path: "build/out"), withIntermediateDirectories: true)
        try Data("bin\n".utf8).write(to: scratch.repository.appending(path: "build/out/app.o"))
        let plain = try await store.cleanPlan(ignored: false)
        #expect(plain.paths == ["loose.txt"])
        let all = try await store.cleanPlan(ignored: true)
        #expect(all.paths.sorted() == ["build/", "loose.txt"])
        #expect(all.files.sorted() == ["build/out/app.o", "loose.txt"])
        #expect(all.keepsCopy)
        #expect(store.cleanCommand(ignored: true).display == "git clean -f -d -x --")
        #expect(store.cleanCommand(ignored: true).risk == .destructive)
        try await store.clean(all)
        #expect(!scratch.exists("loose.txt"))
        #expect(!scratch.exists("build/out/app.o"))
        let entry = try #require(await store.recorded.first)
        #expect(entry.kind == .clean)
        try await store.undoLast()
        #expect(scratch.exists("loose.txt"))
        #expect(try scratch.file("build/out/app.o") == "bin\n")
    }

    @Test func moveAndRemoveFiles() async throws {
        let (scratch, store) = try await prepared()
        defer { scratch.remove() }
        try await store.moveFile(from: "CHANGELOG.md", to: "HISTORY.md")
        #expect(try await scratch.git(["status", "--porcelain", "--", "CHANGELOG.md", "HISTORY.md"]).hasPrefix("R  CHANGELOG.md -> HISTORY.md"))
        try await store.removeFile(path: "HISTORY.md", keepFile: true)
        #expect(scratch.exists("HISTORY.md"))
        try await store.removeFile(path: "Vrai/Info.plist", keepFile: false)
        #expect(!scratch.exists("Vrai/Info.plist"))
        try await store.undoLast()
        #expect(scratch.exists("Vrai/Info.plist"))
    }

    @Test func bugReportCollectsBothFiles() async throws {
        let (scratch, store) = try await prepared()
        defer { scratch.remove() }
        let folder = scratch.root.appending(path: "report", directoryHint: .isDirectory)
        let files = try await store.bugReport(to: folder, diagnostics: true, note: "Push hung")
        #expect(files.contains { $0.lastPathComponent.hasPrefix("git-bugreport-") })
        #expect(files.contains { $0.lastPathComponent.hasPrefix("git-diagnostics-") })
        #expect(files.contains { $0.lastPathComponent == "what-happened.txt" })
        #expect(store.bugReportCommands(to: folder, diagnostics: false).count == 1)
    }

    @Test func compareTheCurrentBranchWithMain() async throws {
        let (scratch, store) = try await prepared()
        defer { scratch.remove() }
        let comparison = try await store.compare(base: "feature/graph-renderer", head: "main")
        #expect(comparison.baseCount == 3)
        #expect(comparison.headCount == 0)
        #expect(comparison.onlyInBase.map(\.subject).first == "Graph: draw merge curves with cubic béziers")
        #expect(comparison.onlyInHead.isEmpty)
    }

    @Test func compareBranchesAndPullRequestSummary() async throws {
        let (scratch, store) = try await prepared()
        defer { scratch.remove() }
        try await scratch.git(["cherry-pick", "--no-gpg-sign", "feature/line-staging~1"])
        let comparison = try await store.compare(base: "feature/line-staging", head: "feature/graph-renderer")
        let counts = try await scratch.git(["rev-list", "--left-right", "--count", "feature/line-staging...feature/graph-renderer"]).split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        #expect([comparison.baseCount, comparison.headCount] == counts)
        #expect(comparison.onlyInBase.count == comparison.baseCount)
        #expect(comparison.onlyInBase.contains { $0.equivalent && $0.subject == "Diff: track selected line ranges per hunk" })
        #expect(comparison.onlyInHead.contains { $0.equivalent })
        #expect(comparison.mergeBase != nil)
        #expect(!comparison.files.isEmpty)
        #expect(comparison.command.display.hasPrefix("git log --left-right -z"))
        let draft = try await store.pullRequestSummary(branch: "feature/line-staging")
        #expect(draft.text.contains("are available in the Git repository at:"))
        #expect(draft.text.contains("Diff: stage individual lines from the gutter"))
        #expect(!draft.published)
        try await scratch.git(["push", "-q", "-f", "origin", "feature/line-staging"])
        let summary = try await store.pullRequestSummary(branch: "feature/line-staging")
        #expect(summary.published)
        #expect(summary.url.hasPrefix("file://"))
        #expect(store.pullRequestCommand(branch: "feature/line-staging").subcommand == "request-pull")
        let unpublished = try await store.pullRequestSummary(branch: "fix/rebase-banner")
        #expect(!unpublished.published)
    }

    @Test func maintenanceVerifyAndInfo() async throws {
        let (scratch, store) = try await prepared()
        defer { scratch.remove() }
        let before = try await store.repositoryInfo()
        #expect(before.commits == Int(try await scratch.git(["rev-list", "--count", "--all"])))
        #expect(before.branches == 6)
        #expect(before.contributors >= 3)
        #expect(before.firstSubject != nil)
        #expect(before.objectFormat == "sha1")
        #expect(before.structure["objects.commits.count"] != nil)
        #expect(before.structure["layout.bare"] == "false")
        #expect(before.remotes.contains("origin"))
        #expect(before.partialFilter == nil)
        #expect(!(await store.isPartialClone()))
        for task in [MaintenanceTask.packRefs, .repack, .commitGraph, .multiPackIndex, .prunePacked, .prune, .gc] {
            let result = try await store.maintenance(task)
            #expect(result.task == task)
        }
        let info = try await store.repositoryInfo()
        #expect(info.packs.count >= 1)
        #expect(info.packs.allSatisfy { $0.objects > 0 && $0.bytes > 0 })
        #expect(info.looseObjects == 0)
        let report = try await store.verifyIntegrity(packs: true)
        #expect(report.isHealthy)
        #expect(report.packsChecked == info.packs.count)
        let pack = try #require(info.packs.first)
        try await store.repairPackIndex(pack.name)
        #expect(try await store.verifyIntegrity(packs: true).isHealthy)
        #expect(MaintenanceTask.gcAggressive.command.display == "git gc --aggressive")
        #expect(MaintenanceTask.gcPruneNow.command.display == "git gc --prune=now")
        #expect(MaintenanceTask.fsck.command.display == "git fsck --no-progress")
    }

    @Test func verifyIntegrityReportsDanglingCommits() async throws {
        let (scratch, store) = try await prepared()
        defer { scratch.remove() }
        let tree = try await scratch.git(["write-tree"])
        try await scratch.git(["commit-tree", "-m", "dangling", tree])
        let report = try await store.verifyIntegrity()
        #expect(report.fsck.dangling.contains { $0.type == "commit" })
        #expect(report.isHealthy)
    }

    @Test func backfillRunsOnAPartialClone() async throws {
        let lab = try CloneLab.make()
        defer { lab.remove() }
        _ = try await lab.git(["config", "uploadpack.allowFilter", "true"], in: lab.copy.remote("origin"))
        let target = lab.destination("partial")
        _ = try await lab.app.startClone(CloneRequest(url: lab.originURL, destination: target, history: .blobless, recurseSubmodules: false)).value
        let store = RepositoryStore(git: try lab.copy.process(at: target))
        try await store.refresh()
        #expect(await store.isPartialClone())
        #expect(store.hasPromisorPacks)
        #expect(await store.partialCloneFilter() == "blob:none")
        let result = try await store.maintenance(.backfill)
        #expect(result.task == .backfill)
        #expect(try await store.repositoryInfo().partialFilter == "blob:none")
    }

    @Test func signaturesNameTheSigner() async throws {
        let (scratch, store) = try await prepared()
        defer { scratch.remove() }
        let head = try await scratch.oid("HEAD")
        let commit = await store.verifySignature(commit: head)
        #expect(commit.good)
        #expect(commit.signer == "avery@vrai.app")
        #expect(commit.keyType == "ED25519")
        #expect(commit.fingerprint?.hasPrefix("SHA256:") == true)
        let tag = await store.verifySignature(tag: "v0.9.0")
        #expect(tag.good)
        #expect(tag.signer == "priya@vrai.app")
        let lightweight = await store.verifySignature(tag: "v0.8.0")
        #expect(!lightweight.good)
        #expect(lightweight.message.contains("non-tag"))
        try await scratch.git(["-c", "commit.gpgsign=false", "commit", "--allow-empty", "-m", "Unsigned"])
        let unsigned = await store.verifySignature(commit: try await scratch.oid("HEAD"))
        #expect(!unsigned.good)
        #expect(unsigned.signer == nil)
        #expect(SharedCommands.verifyCommit(head.rawValue).display == "git verify-commit " + head.rawValue)
        #expect(SharedCommands.verifyTag("v0.9.0").display == "git verify-tag v0.9.0")
    }

    @Test func sharedCommandsKeepTheirArguments() {
        #expect(SharedCommands.describe("abc").arguments == ["describe", "--tags", "--always", "abc"])
        #expect(SharedCommands.nearestTag("abc").arguments == ["describe", "--tags", "--abbrev=0", "abc"])
        #expect(SharedCommands.mergeTree("a", "b").arguments == ["merge-tree", "--write-tree", "-z", "--name-only", "--no-messages", "a", "b"])
        #expect(SharedCommands.mergeTree("a", "b").acceptedExitCodes == [0, 1])
        #expect(SharedCommands.mergeTool(path: "x").arguments == ["mergetool", "--tool=opendiff", "--no-prompt", "--", "x"])
        #expect(SharedCommands.mergeTool(path: "x").access == .write)
        #expect(SharedCommands.blob("abc").arguments == ["cat-file", "blob", "abc"])
        let gpg = LongTailParsers.signature("gpg: Signature made Mon\ngpg:                using RSA key 0123ABCD\ngpg: Good signature from \"Mira Okafor <mira@vrai.app>\" [ultimate]\n", exitCode: 0)
        #expect(gpg.good)
        #expect(gpg.signer == "Mira Okafor <mira@vrai.app>")
        #expect(gpg.keyType == "GPG")
        #expect(gpg.fingerprint == "0123ABCD")
    }

    @Test func parsersHandleGitOutput() {
        let heads = LongTailParsers.remoteHeads("ref: refs/heads/trunk\tHEAD\nabc\tHEAD\nabc\trefs/heads/trunk\ndef\trefs/heads/a\n")
        #expect(heads.defaultBranch == "trunk")
        #expect(heads.branches == ["trunk", "a"])
        let listed = LongTailParsers.remoteHeads("abc refs/heads/main\ndef refs/heads/dev\nabc HEAD\n")
        #expect(listed.defaultBranch == "main")
        let people = LongTailParsers.contributors("     7\tPriya Raman <priya@vrai.app>\n     5\tAvery Chen <avery@vrai.app>\n")
        #expect(people.map(\.commits) == [7, 5])
        #expect(people.first?.email == "priya@vrai.app")
        let report = LongTailParsers.fsck(stdout: "dangling commit 1234\nmissing blob 5678\n", stderr: "error: bad object\n")
        #expect(report.dangling.count == 1)
        #expect(report.missing.count == 1)
        #expect(report.problems == ["error: bad object"])
        #expect(LongTailParsers.cleanPreview("Would remove a.txt\nWould remove build/\n") == ["a.txt", "build/"])
        let page = LongTailParsers.manual(Data("N\u{8}NA\u{8}AM\u{8}ME\u{8}E\n   _\u{8}g_\u{8}i_\u{8}t bisect\n".utf8))
        #expect(page[0] == [ManualSpan(text: "NAME", style: .bold)])
        #expect(page[1] == [ManualSpan(text: "   ", style: .plain), ManualSpan(text: "git", style: .underline), ManualSpan(text: " bisect", style: .plain)])
        let stats = LongTailParsers.numstat(Data("1\t2\ta.txt\u{0}-\t-\tlogo.png\u{0}".utf8))
        #expect(stats == [FileStat(path: "a.txt", additions: 1, deletions: 2), FileStat(path: "logo.png", additions: nil, deletions: nil)])
        let renamed = LongTailParsers.changedPaths(Data("M\u{0}a.txt\u{0}R100\u{0}old.txt\u{0}new.txt\u{0}".utf8))
        #expect(renamed == [ChangedPath(status: "M", path: "a.txt", oldPath: nil), ChangedPath(status: "R", path: "new.txt", oldPath: "old.txt")])
    }
}
