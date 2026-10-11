import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct PlacesStoreTests {
    static let lane = "Sources/VraiGit/Graph/LaneLayout.swift"

    func open() async throws -> (Scratch, RepositoryStore) {
        let scratch = try await Scratch.copy("everyday")
        try await scratch.git(["submodule", "sync", "--recursive"])
        let store = try scratch.store()
        try await store.refresh()
        return (scratch, store)
    }

    func worktrees(_ scratch: Scratch) async throws -> [Worktree] {
        WorktreeParser.parse(try await scratch.process.run(WorktreeParser.command).stdout)
    }

    func sibling(_ scratch: Scratch, _ name: String) -> String {
        scratch.root.appending(path: name).path(percentEncoded: false)
    }

    @Test func reflogListsEveryMoveOfHeadWithItsTime() async throws {
        let (scratch, store) = try await open()
        defer { scratch.remove() }
        try await scratch.git(["commit", "--allow-empty", "--no-gpg-sign", "-m", "Reflog probe"])
        let entries = try await store.reflog()
        let raw = try await scratch.git(["reflog", "--format=%H %gs", "-n", "3"]).split(separator: "\n").map(String.init)
        #expect(entries.count >= 3)
        #expect(entries.prefix(3).map { ($0.id.rawValue + " " + $0.message).trimmingCharacters(in: .whitespaces) } == raw)
        #expect(entries.prefix(3).map(\.selector) == ["HEAD@{0}", "HEAD@{1}", "HEAD@{2}"])
        #expect(entries[0].message == "commit: Reflog probe")
        #expect(abs(entries[0].date.timeIntervalSinceNow) < 120)
        let branch = try await store.reflog(ref: "feature/graph-renderer")
        #expect(branch.first?.selector == "feature/graph-renderer@{0}")
        #expect(branch.first?.id == entries[0].id)
    }

    @Test func restoringAReflogEntryIsRecordedInUndo() async throws {
        let (scratch, store) = try await open()
        defer { scratch.remove() }
        try await scratch.clean()
        let before = try await scratch.oid("HEAD")
        try await scratch.git(["commit", "--allow-empty", "--no-gpg-sign", "-m", "Moves HEAD"])
        let moved = try await scratch.oid("HEAD")
        let entries = try await store.reflog()
        let target = try #require(entries.first { $0.id == before })
        #expect(PlacesCommands.restoreReflog(target.selector).display == "git reset --keep \(target.selector)")
        try await store.reset(to: target.selector, mode: .keep)
        #expect(try await scratch.oid("HEAD") == before)
        let recorded = await store.recorded
        #expect(recorded.first?.kind == .reset)
        #expect(recorded.first?.refsBefore["refs/heads/feature/graph-renderer"] == moved)
        try await store.undoLast()
        #expect(try await scratch.oid("HEAD") == moved)
    }

    @Test func refsListEveryNamespaceIncludingReplacements() async throws {
        let (scratch, store) = try await open()
        defer { scratch.remove() }
        let main = try await scratch.oid("main")
        let release = try await scratch.oid("release/0.9")
        try await scratch.git(["replace", main.rawValue, release.rawValue])
        try await scratch.git(["notes", "add", "-m", "A note", "main"])
        try await scratch.git(["update-ref", "ORIG_HEAD", release.rawValue])
        let refs = try await store.allRefs()
        let byName = Dictionary(refs.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        #expect(refs.first?.name == "HEAD")
        #expect(byName["HEAD"]?.kind == .symbolic)
        #expect(byName["HEAD"]?.symbolicTarget == "refs/heads/feature/graph-renderer")
        #expect(byName["ORIG_HEAD"]?.kind == .pseudo)
        #expect(byName["ORIG_HEAD"]?.target == release)
        #expect(byName["refs/heads/main"]?.kind == .branch)
        #expect(byName["refs/heads/main"]?.namespace == "refs/heads")
        #expect(byName["refs/remotes/origin/HEAD"]?.kind == .symbolic)
        #expect(byName["refs/remotes/origin/HEAD"]?.symbolicTarget == "refs/remotes/origin/main")
        #expect(byName["refs/tags/v0.9.1"]?.kind == .annotatedTag)
        #expect(byName["refs/stash"]?.kind == .stash)
        #expect(byName["refs/notes/commits"]?.kind == .notes)
        let replacement = try #require(byName["refs/replace/" + main.rawValue])
        #expect(replacement.kind == .replace)
        #expect(replacement.target == release)
        #expect(replacement.replacedObject == main.rawValue)
        let listed = try await scratch.git(["for-each-ref", "--format=%(refname)"]).split(separator: "\n").map(String.init)
        #expect(Set(listed).isSubset(of: Set(refs.map(\.name))))
    }

    @Test func removingAReplacementCanBeUndone() async throws {
        let (scratch, store) = try await open()
        defer { scratch.remove() }
        let main = try await scratch.oid("main")
        let release = try await scratch.oid("release/0.9")
        try await scratch.git(["replace", main.rawValue, release.rawValue])
        let summary = try await store.removeReplacement(object: main.rawValue)
        #expect(summary.message == "Removed the replacement for \(main.short)")
        #expect(scratch.log.commands.contains("git replace -d \(main.rawValue)"))
        #expect(try await scratch.git(["for-each-ref", "refs/replace/"]).isEmpty)
        let recorded = await store.recorded
        #expect(recorded.first?.kind == .refDelete)
        try await store.undoLast()
        #expect(try await scratch.git(["rev-parse", "refs/replace/" + main.rawValue]) == release.rawValue)
    }

    @Test func blameMatchesGitAndStepsBackBeforeAChange() async throws {
        let (scratch, store) = try await open()
        defer { scratch.remove() }
        let lines = try await store.blame(path: Self.lane)
        let content = try await scratch.git(["show", "HEAD:" + Self.lane])
        #expect(lines.map(\.text) == content.components(separatedBy: "\n"))
        #expect(lines.map(\.number) == Array(1...lines.count))
        let porcelain = try await scratch.git(["blame", "--line-porcelain", "HEAD", "--", Self.lane]).split(separator: "\n").filter { $0.count >= 40 && OID(String($0.prefix(40))) != nil }.map { String($0.prefix(40)) }
        #expect(lines.map(\.commit.rawValue) == porcelain)
        let changed = try #require(lines.first { $0.previous != nil })
        let previous = try #require(changed.previous)
        let earlier = try await store.blame(path: changed.previousPath ?? Self.lane, at: previous.rawValue)
        #expect(!earlier.isEmpty)
        #expect(!earlier.contains { $0.commit == changed.commit })
        let failed = await #expect(throws: GitError.self) { try await store.blame(path: "Nope/missing.swift") }
        #expect(failed != nil)
    }

    @Test func fileHistoryFollowsRenames() async throws {
        let (scratch, store) = try await open()
        defer { scratch.remove() }
        let expected = try await scratch.git(["log", "--follow", "--format=%H", "--", Self.lane]).split(separator: "\n").map(String.init)
        let history = try await store.fileHistory(path: Self.lane)
        #expect(history.map(\.commit.id.rawValue) == expected)
        #expect(history.allSatisfy { $0.file.path == Self.lane })
        #expect(history.last?.file.status == .added)
        #expect(history.first.map { $0.file.additions + $0.file.deletions > 0 } == true)

        try await scratch.clean()
        let moved = "Sources/VraiGit/Graph/Lanes.swift"
        try await scratch.git(["mv", Self.lane, moved])
        try await scratch.git(["commit", "--no-gpg-sign", "--no-verify", "-m", "Rename the lane layout"])
        let renamed = try await store.fileHistory(path: moved)
        #expect(renamed.count == expected.count + 1)
        #expect(renamed.first?.file.status == .renamed)
        #expect(renamed.first?.file.oldPath == Self.lane)
        #expect(renamed.dropFirst().allSatisfy { $0.file.path == Self.lane })
        let diff = try await store.diff(for: renamed[1].file.path, in: renamed[1].commit.id, oldPath: renamed[1].file.oldPath)
        #expect(diff?.hunks.isEmpty == false)
    }

    @Test func fileContentsAtACommitOpenAsAReadOnlyCopy() async throws {
        let (scratch, store) = try await open()
        defer { scratch.remove() }
        let first = try #require(try await store.fileHistory(path: Self.lane).last)
        let data = try await store.fileContents(path: Self.lane, at: first.commit.id.rawValue)
        let expected = try await scratch.git(["show", first.commit.id.rawValue + ":" + Self.lane])
        #expect(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines) == expected)
        let folder = scratch.root.appending(path: "exported", directoryHint: .isDirectory)
        let url = try await store.exportFile(path: Self.lane, at: first.commit.id, to: folder)
        #expect(url.lastPathComponent == "LaneLayout.swift")
        #expect(url.deletingLastPathComponent().lastPathComponent == first.commit.id.short)
        #expect(try Data(contentsOf: url) == data)
        #expect(!FileManager.default.isWritableFile(atPath: url.path(percentEncoded: false)))
        let again = try await store.exportFile(path: Self.lane, at: first.commit.id, to: folder)
        #expect(again == url)
        try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o644)], ofItemAtPath: url.path(percentEncoded: false))
    }

    @Test func addWorktreeOnANewOrExistingBranch() async throws {
        let (scratch, store) = try await open()
        defer { scratch.remove() }
        let fresh = sibling(scratch, "vrai-sync-fix")
        #expect(store.addWorktreeCommand(path: fresh, branch: "fix/sync", createBranch: true).display == "git worktree add -b fix/sync -- \(fresh)")
        let summary = try await store.addWorktree(path: fresh, branch: "fix/sync", createBranch: true)
        #expect(summary.message == "Added worktree vrai-sync-fix")
        #expect(summary.detail == "On fix/sync.")
        var listed = try await worktrees(scratch)
        let added = try #require(listed.first { $0.path.hasSuffix("/vrai-sync-fix") })
        #expect(added.branch == "fix/sync")
        #expect(added.head == (try await scratch.oid("HEAD")))
        #expect(store.snapshot?.worktrees.contains { $0.path.hasSuffix("/vrai-sync-fix") } == true)

        let existing = sibling(scratch, "vrai-banner")
        try await store.addWorktree(path: existing, branch: "fix/rebase-banner", createBranch: false)
        #expect(scratch.log.commands.contains("git worktree add -- \(existing) fix/rebase-banner"))
        listed = try await worktrees(scratch)
        #expect(listed.first { $0.path.hasSuffix("/vrai-banner") }?.branch == "fix/rebase-banner")

        let started = sibling(scratch, "vrai-from-main")
        try await store.addWorktree(path: started, branch: "spike/from-main", createBranch: true, startPoint: "main")
        #expect(try await scratch.oid("spike/from-main") == (try await scratch.oid("main")))

        let busy = await #expect(throws: GitError.self) { try await store.addWorktree(path: sibling(scratch, "vrai-again"), branch: "feature/graph-renderer", createBranch: false) }
        if case .branchCheckedOutElsewhere = busy?.code {} else { Issue.record("expected branchCheckedOutElsewhere, got \(String(describing: busy))") }
        let taken = await #expect(throws: GitError.self) { try await store.addWorktree(path: fresh, branch: "fix/other", createBranch: true) }
        #expect(taken?.code == .pathExists)
    }

    @Test func lockAndUnlockAWorktree() async throws {
        let (scratch, store) = try await open()
        defer { scratch.remove() }
        let release = sibling(scratch, "vrai-release")
        let locked = try await store.setWorktreeLocked(path: release, locked: true, reason: "On a USB drive")
        #expect(locked.message == "Locked vrai-release")
        var entry = try #require(try await worktrees(scratch).first { $0.path.hasSuffix("/vrai-release") })
        #expect(entry.locked)
        #expect(entry.lockReason == "On a USB drive")
        #expect(store.snapshot?.worktrees.first { $0.path.hasSuffix("/vrai-release") }?.locked == true)
        try await store.setWorktreeLocked(path: release, locked: false)
        entry = try #require(try await worktrees(scratch).first { $0.path.hasSuffix("/vrai-release") })
        #expect(!entry.locked)
        #expect(scratch.log.commands.contains("git worktree lock --reason \"On a USB drive\" -- \(release)"))
        #expect(scratch.log.commands.contains("git worktree unlock -- \(release)"))
    }

    @Test func removeACleanAndALockedWorktree() async throws {
        let (scratch, store) = try await open()
        defer { scratch.remove() }
        let release = sibling(scratch, "vrai-release")
        let summary = try await store.removeWorktree(path: release)
        #expect(summary.message == "Removed worktree vrai-release")
        #expect(summary.detail == "Its branch stays.")
        #expect(!FileManager.default.fileExists(atPath: release))
        #expect(try await scratch.oid("release/0.9").rawValue.count == 40)

        let review = sibling(scratch, "vrai-review")
        let detached = try await store.removeWorktree(path: review)
        #expect(detached.detail == "Its commits stay in the repository.")
        #expect(scratch.log.commands.contains { $0.hasPrefix("git worktree unlock -- /") && $0.hasSuffix("/vrai-review") })
        #expect(try await worktrees(scratch).count == 1)
        #expect(store.snapshot?.worktrees.count == 1)
        #expect(await store.recorded.isEmpty)
    }

    @Test func removingADirtyWorktreeKeepsItsChangesInUndo() async throws {
        let (scratch, store) = try await open()
        defer { scratch.remove() }
        let release = sibling(scratch, "vrai-release")
        let folder = URL(filePath: release, directoryHint: .isDirectory)
        try Data("edited in the worktree\n".utf8).write(to: folder.appending(path: "README.md"))
        try Data("brand new\n".utf8).write(to: folder.appending(path: "scratch notes.txt"))
        try await store.refresh()
        #expect(store.snapshot?.worktrees.first { $0.path.hasSuffix("/vrai-release") }?.changes == 2)

        let refused = await #expect(throws: GitError.self) { try await store.removeWorktree(path: release) }
        #expect(refused?.code == .worktreeDirty)
        #expect(FileManager.default.fileExists(atPath: release))

        #expect(store.removeWorktreeCommand(path: release, force: true).risk == .destructive)
        let summary = try await store.removeWorktree(path: release, force: true)
        #expect(summary.detail == "Its 2 uncommitted changes stay in Undo history for 14 days.")
        #expect(!FileManager.default.fileExists(atPath: release))
        #expect(scratch.log.commands.contains { $0.hasPrefix("git worktree remove --force -- /") && $0.hasSuffix("/vrai-release") })
        let recorded = await store.recorded
        let entry = try #require(recorded.first)
        #expect(entry.kind == .worktreeRemove)
        #expect(entry.label == "Removed worktree vrai-release")
        let stash = try #require(entry.stashCommit)
        #expect(!(try await scratch.git(["for-each-ref", "--format=%(refname)", "refs/vrai/undo/"])).isEmpty)

        let stashes = try await scratch.git(["stash", "list", "--format=%H"]).split(separator: "\n").count
        try await store.undoLast()
        #expect(try await scratch.git(["stash", "list", "--format=%H"]).split(separator: "\n").first.map(String.init) == stash.rawValue)
        #expect(try await scratch.git(["stash", "list", "--format=%H"]).split(separator: "\n").count == stashes + 1)
        #expect(try await scratch.git(["stash", "list", "-n", "1", "--format=%gs"]) == "On release/0.9: changes from worktree vrai-release")
        #expect(try await scratch.git(["show", "stash@{0}:README.md"]) == "edited in the worktree")
        #expect(try await scratch.git(["show", "stash@{0}^3:scratch notes.txt"]) == "brand new")
        #expect(try await scratch.oid("stash@{0}^1") == (try await scratch.oid("release/0.9")))
    }

    @Test func removingAWorktreeWithOnlyUntrackedFilesStillKeepsThem() async throws {
        let (scratch, store) = try await open()
        defer { scratch.remove() }
        let release = sibling(scratch, "vrai-release")
        try Data("only untracked\n".utf8).write(to: URL(filePath: release).appending(path: "draft.md"))
        try await store.removeWorktree(path: release, force: true)
        let entry = try #require(await store.recorded.first)
        let stash = try #require(entry.stashCommit)
        #expect(try await scratch.git(["show", stash.rawValue + "^3:draft.md"]) == "only untracked")
        #expect(try await scratch.git(["rev-list", "--parents", "-n", "1", stash.rawValue]).split(separator: " ").count == 4)
    }

    @Test func pruneRemovesWorktreesWhoseFolderIsGone() async throws {
        let (scratch, store) = try await open()
        defer { scratch.remove() }
        let nothing = try await store.pruneWorktrees()
        #expect(nothing.message == "No stale worktrees")
        try FileManager.default.removeItem(atPath: sibling(scratch, "vrai-release"))
        try await store.refresh()
        #expect(store.snapshot?.worktrees.first { $0.path.hasSuffix("/vrai-release") }?.prunable != nil)
        let summary = try await store.pruneWorktrees()
        #expect(summary.message == "Pruned 1 stale worktree")
        #expect(scratch.log.commands.contains("git worktree prune --verbose"))
        #expect(try await worktrees(scratch).map { URL(filePath: $0.path).lastPathComponent } == ["vrai", "vrai-review"])
        #expect(store.snapshot?.worktrees.count == 2)
    }
}
