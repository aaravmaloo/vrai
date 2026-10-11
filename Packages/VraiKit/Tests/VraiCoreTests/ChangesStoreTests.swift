import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct ChangesStoreTests {
    static let original = (1...40).map { "line \($0)" }.joined(separator: "\n") + "\n"
    static let edited: String = {
        var lines = (1...40).map { "line \($0)" }
        lines.insert(contentsOf: ["added A", "added B"], at: 5)
        lines.removeSubrange(21...22)
        lines[33] = "changed 34"
        lines.insert("inserted after 34", at: 34)
        return lines.joined(separator: "\n") + "\n"
    }()

    func hunkIndex(_ file: FileDiff, where predicate: (Hunk) -> Bool) throws -> Int {
        let index = file.hunks.firstIndex(where: predicate)
        return try #require(index)
    }

    func lineID(_ file: FileDiff, hunk: Int, _ kind: DiffLine.Kind, _ text: String) throws -> LineID {
        let line = try #require(file.hunks[hunk].lines.firstIndex { $0.kind == kind && $0.text == text })
        return LineID(hunk: hunk, line: line)
    }

    @Test func stageAndUnstageSingleLinesInAddedDeletedAndMixedHunks() async throws {
        let fixture = try await PrivateFixture.everyday()
        let path = "Sources/VraiGit/Staging/Lines.txt"
        try fixture.write(path, Self.original)
        try await fixture.store.stage(paths: [path])
        try await fixture.store.commit(subject: "Add lines")
        try fixture.write(path, Self.edited)
        let worktreeHash = try await fixture.hash(path)

        let unstaged = try #require(try await fixture.store.workingDiff(path: path, staged: false))
        #expect(unstaged.hunks.count == 3)
        let added = try hunkIndex(unstaged) { $0.deletions == 0 }
        let deleted = try hunkIndex(unstaged) { $0.additions == 0 }
        let mixed = try hunkIndex(unstaged) { $0.additions > 0 && $0.deletions > 0 }

        try await fixture.store.stage(lines: LineSelection(file: unstaged, side: .unstaged, lines: [try lineID(unstaged, hunk: added, .add, "added B")]))
        #expect(try await fixture.stagedDiff(path) == ["+added B"])

        try await fixture.store.stage(lines: LineSelection(file: unstaged, side: .unstaged, lines: [try lineID(unstaged, hunk: deleted, .del, "line 21")]))
        #expect(try await fixture.stagedDiff(path) == ["+added B", "-line 21"])

        let second = try #require(try await fixture.store.workingDiff(path: path, staged: false))
        let mixedNow = try hunkIndex(second) { $0.additions > 0 && $0.deletions > 0 }
        try await fixture.store.stage(lines: LineSelection(file: second, side: .unstaged, lines: [try lineID(second, hunk: mixedNow, .add, "inserted after 34")]))
        #expect(try await fixture.stagedDiff(path) == ["+added B", "-line 21", "+inserted after 34"])
        #expect(mixed == 2)

        let third = try #require(try await fixture.store.workingDiff(path: path, staged: false))
        let mixedLast = try hunkIndex(third) { $0.lines.contains { $0.text == "changed 34" } }
        try await fixture.store.stage(lines: LineSelection(file: third, side: .unstaged, lines: [try lineID(third, hunk: mixedLast, .del, "line 34")]))
        #expect(try await fixture.stagedDiff(path) == ["+added B", "-line 21", "-line 34", "+inserted after 34"])

        let staged = try #require(try await fixture.store.workingDiff(path: path, staged: true))
        let stagedAdded = try hunkIndex(staged) { $0.lines.contains { $0.text == "added B" } }
        try await fixture.store.unstage(lines: LineSelection(file: staged, side: .staged, lines: [try lineID(staged, hunk: stagedAdded, .add, "added B")]))
        #expect(try await fixture.stagedDiff(path) == ["-line 21", "-line 34", "+inserted after 34"])

        let stagedAgain = try #require(try await fixture.store.workingDiff(path: path, staged: true))
        let stagedMixed = try hunkIndex(stagedAgain) { $0.lines.contains { $0.text == "line 34" } }
        try await fixture.store.unstage(lines: LineSelection(file: stagedAgain, side: .staged, lines: [try lineID(stagedAgain, hunk: stagedMixed, .del, "line 34")]))
        #expect(try await fixture.stagedDiff(path) == ["-line 21", "+inserted after 34"])

        #expect(try await fixture.hash(path) == worktreeHash)
        let row = fixture.store.snapshot?.working.first { $0.path == path }
        #expect(row?.staged == .partial)
    }

    @Test func linesOfANewFileCanBeStagedAndUnstaged() async throws {
        let fixture = try await PrivateFixture.everyday()
        let path = "Notes/new lines.txt"
        try fixture.write(path, "one\ntwo\nthree")
        try await fixture.store.refresh()
        let diff = try #require(try await fixture.store.workingDiff(path: path, staged: false))
        #expect(diff.status == .added)
        try await fixture.store.stage(lines: LineSelection(file: diff, side: .unstaged, lines: [try lineID(diff, hunk: 0, .add, "two")]))
        #expect(try await fixture.output(["cat-file", "blob", ":" + path]) == "two")
        let staged = try #require(try await fixture.store.workingDiff(path: path, staged: true))
        try await fixture.store.unstage(lines: LineSelection.all(in: staged, side: .staged))
        #expect(try await fixture.output(["ls-files", "--", path]).isEmpty)
        #expect(fixture.read(path) == Data("one\ntwo\nthree".utf8))
    }

    @Test func wholeFilesStageUnstageAndStageAll() async throws {
        let fixture = try await PrivateFixture.everyday()
        try await fixture.store.stage(paths: ["Sources/VraiUI/History/HeadHalo.swift", "Resources/Graph.xcassets/Contents.json"])
        var status = try await fixture.status()
        #expect(status.contains("A  Sources/VraiUI/History/HeadHalo.swift"))
        #expect(status.contains("D  Resources/Graph.xcassets/Contents.json"))
        try await fixture.store.unstage(paths: ["Sources/VraiUI/History/HeadHalo.swift"])
        status = try await fixture.status()
        #expect(status.contains("?? Sources/VraiUI/History/HeadHalo.swift"))
        try await fixture.store.unstageAll()
        #expect(try await fixture.output(["diff", "--cached", "--name-only"]).isEmpty)
        try await fixture.store.stageAll(includeUntracked: false)
        status = try await fixture.status()
        #expect(status.contains("?? Notes/graph-perf.md"))
        #expect(status.contains("M  Sources/VraiGit/Graph/LaneLayout.swift"))
        try await fixture.store.stageAll(includeUntracked: true)
        status = try await fixture.status()
        #expect(status.contains("A  Notes/graph-perf.md"))
        #expect(fixture.store.busy.isEmpty)
    }

    @Test func renamedFilesUnstageAsAPairAndStageBackAsARename() async throws {
        let fixture = try await PrivateFixture.everyday()
        let new = "Sources/VraiUI/History/LaneColors.swift"
        let old = "Sources/VraiUI/History/Palette.swift"
        let diff = try #require(try await fixture.store.workingDiff(path: new, staged: true))
        #expect(diff.status == .renamed)
        #expect(diff.oldPath == old)
        try await fixture.store.unstage(paths: [new])
        var status = try await fixture.status()
        #expect(status.contains(" D " + old))
        #expect(status.contains("?? " + new))
        try await fixture.store.stage(paths: [old, new])
        status = try await fixture.status()
        #expect(status.contains("R  " + old + " -> " + new))
    }

    @Test func binaryFilesStageWholeAndRefuseLineStaging() async throws {
        let fixture = try await PrivateFixture.everyday()
        let path = "Resources/halo.png"
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0xFF, 0x00, 0x10])
        try fixture.write(path, bytes)
        try await fixture.store.stage(paths: [path])
        try await fixture.store.commit(subject: "Add the halo image")
        var changed = bytes
        changed.append(contentsOf: [0x00, 0x01, 0x02])
        try fixture.write(path, changed)
        let diff = try #require(try await fixture.store.workingDiff(path: path, staged: false))
        #expect(diff.isBinary)
        await expectGitError("patchDoesNotApply") {
            try await fixture.store.stage(lines: LineSelection.all(in: diff, side: .unstaged))
        }
        try await fixture.store.stage(paths: [path])
        #expect(try await fixture.output(["diff", "--cached", "--numstat", "--", path]) == "-\t-\t" + path)
    }

    @Test func discardingFilesThenUndoingRestoresTheExactBytes() async throws {
        let fixture = try await PrivateFixture.everyday()
        let script = "Scripts/run.sh"
        try fixture.write(script, "#!/bin/sh\necho one\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.url(script).path(percentEncoded: false))
        try await fixture.store.stage(paths: [script])
        try await fixture.store.commit(subject: "Add a script")

        let edits: [String: Data] = [
            script: Data("#!/bin/sh\necho two\r\necho three".utf8),
            "Sources/VraiGit/Graph/LaneLayout.swift": Data([0xEF, 0xBB, 0xBF] + Array("// changed\r\n".utf8) + [0xFF, 0xFE, 0x00, 0x41]),
            "Notes/graph-perf.md": Data("untracked notes\nwithout newline".utf8)
        ]
        for (path, data) in edits { try fixture.write(path, data) }
        let deleted = "Resources/Graph.xcassets/Contents.json"
        #expect(!fixture.exists(deleted))
        var before: [String: String] = [:]
        for path in edits.keys { before[path] = try await fixture.hash(path) }
        let stagedBefore = try await fixture.output(["diff", "--cached", "--name-status"])

        let paths = edits.keys.sorted() + [deleted]
        try await fixture.store.discard(paths: paths)
        #expect(!fixture.exists("Notes/graph-perf.md"))
        #expect(fixture.exists(deleted))
        #expect(try await fixture.output(["diff", "--name-only", "--", script, deleted]).isEmpty)

        let history = try await fixture.store.undoHistory()
        #expect(history.first?.kind == .discardFile)
        #expect(history.first?.label == "Discarded changes to 4 files")

        let undone = try await fixture.store.undoLast()
        #expect(undone?.kind == .discardFile)
        for (path, data) in edits {
            #expect(fixture.read(path) == data, "\(path)")
            #expect(try await fixture.hash(path) == before[path], "\(path)")
        }
        #expect(!fixture.exists(deleted))
        #expect(FileManager.default.isExecutableFile(atPath: fixture.url(script).path(percentEncoded: false)))
        #expect(try await fixture.output(["diff", "--cached", "--name-status"]) == stagedBefore)
        #expect(try await fixture.store.undoHistory().first?.id != undone?.id)
    }

    @Test func discardingLinesThenUndoingRestoresTheExactBytes() async throws {
        let fixture = try await PrivateFixture.everyday()
        let path = "Sources/VraiGit/Staging/Lines.txt"
        try fixture.write(path, Self.original)
        try await fixture.store.stage(paths: [path])
        try await fixture.store.commit(subject: "Add lines")
        let edited = Self.edited.replacingOccurrences(of: "line 40\n", with: "line 40\nlast without newline")
        try fixture.write(path, edited)
        let originalHash = try await fixture.hash(path)

        let diff = try #require(try await fixture.store.workingDiff(path: path, staged: false))
        let added = try hunkIndex(diff) { $0.deletions == 0 && $0.lines.contains { $0.text == "added A" } }
        let last = try #require(diff.hunks.indices.last)
        var selection = LineSelection(file: diff, side: .unstaged)
        selection.select([try lineID(diff, hunk: added, .add, "added A")])
        selection.select(LineSelection.hunk(last, in: diff, side: .unstaged).lines)
        try await fixture.store.discard(lines: selection)
        let after = String(decoding: fixture.read(path) ?? Data(), as: UTF8.self)
        #expect(!after.contains("added A"))
        #expect(after.contains("added B"))
        #expect(!after.contains("last without newline"))
        #expect(try await fixture.store.undoHistory().first?.label.hasPrefix("Discarded ") == true)

        try await fixture.store.undoLast()
        #expect(fixture.read(path) == Data(edited.utf8))
        #expect(try await fixture.hash(path) == originalHash)
    }

    @Test func hookFailureSurfacesTheOutputAndKeepsTheMessage() async throws {
        let fixture = try await PrivateFixture.everyday()
        let gitDir = try await fixture.output(["rev-parse", "--absolute-git-dir"])
        try Data().write(to: URL(filePath: gitDir).appending(path: "vrai-fail-pre-commit"))
        let head = try await fixture.head()
        let staged = try await fixture.output(["diff", "--cached", "--name-status"])
        let history = try await fixture.store.undoHistory().count

        let error = await expectGitError("hookFailed") {
            try await fixture.store.commit(subject: "Draw a halo behind HEAD", body: "Uses the lane color.")
        }
        #expect(error?.hookName == "pre-commit")
        #expect(error?.hookOutput?.contains("swift-format lint --strict: 2 problems") == true)
        #expect(error?.hookOutput?.contains("GraphCell.swift:31:1: Line is too long") == true)
        #expect(error?.commitMessage == CommitMessage(subject: "Draw a halo behind HEAD", body: "Uses the lane color."))
        #expect(try await fixture.head() == head)
        #expect(try await fixture.output(["diff", "--cached", "--name-status"]) == staged)
        #expect(try await fixture.store.undoHistory().count == history)
        #expect(fixture.store.busy.isEmpty)

        try FileManager.default.removeItem(at: URL(filePath: gitDir).appending(path: "vrai-fail-pre-commit"))
        let long = String(repeating: "x", count: 80)
        let message = await expectGitError("hookFailed") {
            try await fixture.store.commit(subject: long)
        }
        #expect(message?.hookName == "commit-msg")
        #expect(message?.hookOutput?.contains("Keep it to 72 or fewer") == true)
        #expect(message?.commitMessage?.subject == long)
    }

    @Test func commitsAreSignedWithTheSandboxKeyAndVerify() async throws {
        let fixture = try await PrivateFixture.everyday()
        let tip = try await fixture.store.commit(subject: "Draw a halo behind HEAD")
        #expect(try await fixture.head() == tip.rawValue)
        #expect(try await fixture.output(["log", "-1", "--format=%G?"]) == "G")
        #expect(try await fixture.output(["log", "-1", "--format=%GS"]) == "avery@vrai.app")
        let verify = try await fixture.git.runAllowingFailure(.read(["verify-commit", "HEAD"]))
        #expect(verify.succeeded)
        #expect(verify.errorOutput.contains("Good \"git\" signature for avery@vrai.app"))
        #expect(try await fixture.status().contains("M  Sources/VraiUI/History/GraphCell.swift") == false)
        let history = try await fixture.store.undoHistory()
        #expect(history.first?.kind == .commit)
        #expect(history.first?.label == "Committed \u{201C}Draw a halo behind HEAD\u{201D}")
        #expect(history.first?.detail == "On feature/graph-renderer")
    }

    @Test func amendSignoffAndSkippingHooks() async throws {
        let fixture = try await PrivateFixture.everyday()
        let parent = try await fixture.output(["rev-parse", "HEAD"])
        try await fixture.store.commit(subject: "Draw a halo", body: "First pass.", signoff: true)
        let first = try await fixture.head()
        #expect(try await fixture.output(["log", "-1", "--format=%B"]).contains("Signed-off-by: Avery Chen <avery@vrai.app>"))
        #expect(try await fixture.store.lastCommitMessage()?.subject == "Draw a halo")
        #expect(try await fixture.store.lastCommitMessage()?.body.hasPrefix("First pass.") == true)

        try await fixture.store.stage(paths: ["Notes/graph-perf.md"])
        try await fixture.store.commit(subject: "Draw a halo behind HEAD", body: "Second pass.", amend: true)
        #expect(try await fixture.head() != first)
        #expect(try await fixture.output(["rev-parse", "HEAD^"]) == parent)
        #expect(try await fixture.output(["log", "-1", "--format=%s"]) == "Draw a halo behind HEAD")
        #expect(try await fixture.output(["show", "--name-only", "--format=", "HEAD"]).contains("Notes/graph-perf.md"))
        #expect(try await fixture.store.undoHistory().first?.kind == .amend)

        let gitDir = try await fixture.output(["rev-parse", "--absolute-git-dir"])
        try Data().write(to: URL(filePath: gitDir).appending(path: "vrai-fail-pre-commit"))
        try await fixture.store.stage(paths: ["Sources/VraiUI/History/HeadHalo.swift"])
        try await fixture.store.commit(subject: String(repeating: "y", count: 90), noVerify: true)
        #expect(try await fixture.output(["log", "-1", "--format=%s"]) == String(repeating: "y", count: 90))

        await expectGitError("emptyMessage") {
            try await fixture.store.commit(subject: "   ")
        }
        await expectGitError("nothingToCommit") {
            try await fixture.store.commit(subject: "Nothing staged", noVerify: true)
        }
    }

    @Test func unbornRepositoryStagingFirstCommitAndUndo() async throws {
        let fixture = try await PrivateFixture.copy("empty", "pocket-notes")
        #expect(fixture.store.snapshot?.head == .unborn("main"))
        try await fixture.store.stage(paths: ["README.md"])
        #expect(try await fixture.output(["diff", "--cached", "--name-only"]) == "README.md")
        try fixture.write("README.md", (String(decoding: fixture.read("README.md") ?? Data(), as: UTF8.self)) + "edited after staging\n")
        try await fixture.store.unstage(paths: ["README.md"])
        #expect(try await fixture.output(["diff", "--cached", "--name-only"]).isEmpty)
        #expect(try await fixture.status().contains("?? README.md"))

        let diff = try #require(try await fixture.store.workingDiff(path: "README.md", staged: false))
        #expect(diff.status == .added)
        let first = try #require(LineSelection.all(in: diff, side: .unstaged).sorted.first)
        try await fixture.store.stage(lines: LineSelection(file: diff, side: .unstaged, lines: [first]))
        #expect(try await fixture.output(["ls-files", "--", "README.md"]) == "README.md")

        try await fixture.store.unstageAll()
        #expect(try await fixture.output(["ls-files"]).isEmpty)
        try await fixture.store.stageAll(includeUntracked: true)
        let files = try await fixture.output(["ls-files"])
        #expect(files.contains("README.md") && files.contains("Package.swift"))

        let tip = try await fixture.store.commit(subject: "Start pocket notes")
        #expect(try await fixture.head() == tip.rawValue)
        #expect(fixture.store.snapshot?.head == .branch("main"))
        #expect(try await fixture.output(["rev-list", "--count", "HEAD"]) == "1")

        try await fixture.store.undoLast()
        #expect(fixture.store.snapshot?.head == .unborn("main"))
        #expect(try await fixture.output(["ls-files"]) == files)
        #expect(try await fixture.git.runAllowingFailure(.read(["rev-parse", "-q", "--verify", "HEAD"])).exitCode != 0)
    }

    @Test func undoingACommitAndAnAmendPutsTheChangesBackStaged() async throws {
        let fixture = try await PrivateFixture.everyday()
        let parent = try await fixture.head()
        let staged = try await fixture.output(["diff", "--cached", "--name-status"])
        try await fixture.store.commit(subject: "Draw a halo")
        #expect(try await fixture.output(["diff", "--cached", "--name-status"]).isEmpty)
        let undone = try await fixture.store.undoLast()
        #expect(undone?.kind == .commit)
        #expect(try await fixture.head() == parent)
        #expect(try await fixture.output(["diff", "--cached", "--name-status"]) == staged)

        try await fixture.store.commit(subject: "Draw a halo")
        let committed = try await fixture.head()
        try await fixture.store.stage(paths: ["Notes/graph-perf.md"])
        try await fixture.store.commit(subject: "Draw a halo and notes", amend: true)
        #expect(try await fixture.head() != committed)
        try await fixture.store.undoLast()
        #expect(try await fixture.head() == committed)
        #expect(try await fixture.output(["diff", "--cached", "--name-only"]) == "Notes/graph-perf.md")
        #expect(try await fixture.output(["log", "-1", "--format=%s"]) == "Draw a halo")
    }

    @Test func undoNoLongerAppliesAfterTheBranchMovedOn() async throws {
        let fixture = try await PrivateFixture.everyday()
        try await fixture.store.commit(subject: "Draw a halo")
        let entry = try #require(try await fixture.store.undoHistory().first)
        try fixture.write("Notes/terminal.md", "made in Terminal\n")
        try await fixture.run(["add", "Notes/terminal.md"])
        try await fixture.run(["commit", "-q", "-m", "Made in Terminal"])
        let head = try await fixture.head()
        await expectGitError("undoNoLongerApplies") {
            try await fixture.store.restore(entry)
        }
        #expect(try await fixture.head() == head)
    }

    @Test func restoringAFileFromACommitCanBeUndone() async throws {
        let fixture = try await PrivateFixture.everyday()
        let path = "Sources/VraiGit/Graph/LaneLayout.swift"
        let current = fixture.read(path)
        try await fixture.store.restoreFile(path: path, from: "HEAD~3")
        #expect(try await fixture.hash(path) == (try await fixture.output(["rev-parse", "HEAD~3:" + path])))
        let entry = try #require(try await fixture.store.undoHistory().first)
        #expect(entry.kind == .restoreFile)
        #expect(entry.label.hasPrefix("Restored LaneLayout.swift from "))
        try await fixture.store.restore(entry)
        #expect(fixture.read(path) == current)
    }

    @Test func signingFailuresAndLockFilesSurfaceTheirCodes() async throws {
        let fixture = try await PrivateFixture.everyday()
        let head = try await fixture.head()
        try await fixture.run(["config", "user.signingkey", fixture.repo.appending(path: "missing_ed25519").path(percentEncoded: false)])
        let signing = await expectGitError("signingFailed") {
            try await fixture.store.commit(subject: "Signed with a missing key")
        }
        #expect(signing?.commitMessage?.subject == "Signed with a missing key")
        #expect(try await fixture.head() == head)

        let gitDir = try await fixture.output(["rev-parse", "--absolute-git-dir"])
        let lock = URL(filePath: gitDir).appending(path: "index.lock")
        try Data().write(to: lock)
        let error = await expectGitError("lockFileExists") {
            try await fixture.store.stage(paths: ["Notes/graph-perf.md"])
        }
        if case .lockFileExists(let path) = error?.code {
            #expect(path?.hasSuffix("index.lock") == true)
        }
        try FileManager.default.removeItem(at: lock)
        try await fixture.store.stage(paths: ["Notes/graph-perf.md"])
        #expect(try await fixture.status().contains("A  Notes/graph-perf.md"))
    }
}
