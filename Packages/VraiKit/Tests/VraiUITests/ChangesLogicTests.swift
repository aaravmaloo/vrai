import Foundation
import Testing
import VraiGit
@testable import VraiUI

struct ChangesLogicTests {
    static let working: [WorkingFile] = [
        WorkingFile(path: "Resources/Graph.xcassets/Contents.json", status: .deleted, staged: .none, worktreeStatus: .deleted),
        WorkingFile(path: "Sources/VraiGit/Graph/LaneLayout.swift", status: .modified, staged: .partial, indexStatus: .modified, worktreeStatus: .modified),
        WorkingFile(path: "Sources/VraiUI/History/GraphCell.swift", status: .modified, staged: .full, indexStatus: .modified),
        WorkingFile(path: "Sources/VraiUI/History/LaneColors.swift", oldPath: "Sources/VraiUI/History/Palette.swift", status: .renamed, staged: .full, indexStatus: .renamed),
        WorkingFile(path: "Notes/graph-perf.md", status: .untracked, staged: .none, worktreeStatus: .untracked),
        WorkingFile(path: "Sources/VraiGit/Merge.swift", status: .conflicted, staged: .none)
    ]

    @Test func filesFallIntoStagedUnstagedUntrackedAndConflictGroups() {
        let groups = ChangeGroups(Self.working)
        #expect(groups.conflicts.map(\.path) == ["Sources/VraiGit/Merge.swift"])
        #expect(groups.staged.map(\.path) == ["Sources/VraiGit/Graph/LaneLayout.swift", "Sources/VraiUI/History/GraphCell.swift", "Sources/VraiUI/History/LaneColors.swift"])
        #expect(groups.unstaged.map(\.path) == ["Resources/Graph.xcassets/Contents.json", "Sources/VraiGit/Graph/LaneLayout.swift"])
        #expect(groups.untracked.map(\.path) == ["Notes/graph-perf.md"])
        #expect(groups.changedFiles == 5)
        #expect(groups.picks.first == ChangesPick(path: "Sources/VraiGit/Merge.swift", side: .unstaged, conflict: true))
        #expect(groups.picks.count == 7)
    }

    @Test func aPickFollowsItsFileAcrossGroups() {
        let partial = ChangesPick(path: "Sources/VraiGit/Graph/LaneLayout.swift", side: .unstaged)
        #expect(ChangeGroups.resolve(partial, in: Self.working) == partial)
        let fullyStaged = ChangesPick(path: "Sources/VraiUI/History/GraphCell.swift", side: .unstaged)
        #expect(ChangeGroups.resolve(fullyStaged, in: Self.working) == ChangesPick(path: "Sources/VraiUI/History/GraphCell.swift", side: .staged))
        let unstagedOnly = ChangesPick(path: "Resources/Graph.xcassets/Contents.json", side: .staged)
        #expect(ChangeGroups.resolve(unstagedOnly, in: Self.working) == ChangesPick(path: "Resources/Graph.xcassets/Contents.json", side: .unstaged))
        let gone = ChangesPick(path: "Gone.swift", side: .unstaged)
        #expect(ChangeGroups.resolve(gone, in: Self.working)?.conflict == true)
        #expect(ChangeGroups.resolve(nil, in: []) == nil)
    }

    @Test func statusLettersDependOnTheSide() {
        let partial = Self.working[1]
        #expect(ChangeGroups.statusLetter(partial, side: .staged) == .modified)
        let renamed = Self.working[3]
        #expect(ChangeGroups.statusLetter(renamed, side: .staged) == .renamed)
        let added = WorkingFile(path: "New.swift", status: .added, staged: .partial, indexStatus: .added, worktreeStatus: .modified)
        #expect(ChangeGroups.statusLetter(added, side: .staged) == .added)
        #expect(ChangeGroups.statusLetter(added, side: .unstaged) == .modified)
    }

    @Test func discardCopyMatchesThePrototype() {
        #expect(ChangesCopy.discardTitle(["Sources/VraiUI/History/GraphCell.swift"]) == "Discard changes to GraphCell.swift?")
        #expect(ChangesCopy.discardTitle(["a", "b", "c"]) == "Discard changes to 3 files?")
        #expect(ChangesCopy.discardMessage(tracked: 1, lines: 15, untracked: 0) == "15 changed lines go back to the last commit. A copy stays in Undo history for 14 days.")
        #expect(ChangesCopy.discardMessage(tracked: 1, lines: 1, untracked: 0) == "1 changed line goes back to the last commit. A copy stays in Undo history for 14 days.")
        #expect(ChangesCopy.discardMessage(tracked: 2, lines: 0, untracked: 0) == "They go back to the last commit. A copy stays in Undo history for 14 days.")
        #expect(ChangesCopy.discardMessage(tracked: 0, lines: 0, untracked: 1) == "It's untracked, so the file is deleted. A copy stays in Undo history for 14 days.")
        #expect(ChangesCopy.discardMessage(tracked: 2, lines: 4, untracked: 1) == "4 changed lines go back to the last commit, and 1 untracked file is deleted. A copy stays in Undo history for 14 days.")
        #expect(ChangesCopy.discardMessage(tracked: 0, lines: 0, untracked: 3) == "3 untracked files are deleted. A copy stays in Undo history for 14 days.")
        #expect(ChangesCopy.cleanTitle(["Notes/graph-perf.md"]) == "Delete graph-perf.md?")
        #expect(ChangesCopy.cleanTitle(["a", "b"]) == "Delete 2 untracked files?")
        #expect(ChangesCopy.cleanMessage(2) == "Git doesn't track them, so no commit has a copy. Undo history keeps one for 14 days.")
        #expect(ChangesCopy.pathList(["a/1", "a/2", "a/3", "a/4", "a/5", "a/6"]) == "1\n2\n3\n4\nand 2 more files")
    }

    @Test func undoMenuTitleNamesTheLatestEntry() {
        #expect(ChangesCopy.undoMenuTitle(nil) == "Undo")
        let entry = UndoEntry(kind: .discardFile, label: "Discarded changes to README.md")
        #expect(ChangesCopy.undoMenuTitle(entry) == "Undo discarded changes to README.md")
        #expect(ChangesCopy.restoredDetail(short: "c3e7a1f", inChanges: false, lines: 0) == "It matches c3e7a1f again.")
        #expect(ChangesCopy.restoredDetail(short: "c3e7a1f", inChanges: true, lines: 12) == "12 changed lines in Changes, ready to review.")
        #expect(ChangesCopy.restoredDetail(short: "c3e7a1f", inChanges: true, lines: 0) == "It's in Changes, ready to review.")
    }

    @Test func errorCopyCoversEveryChangesCode() {
        let codes: [GitErrorCode] = [.nothingToCommit, .emptyMessage, .hookFailed(name: "pre-commit", output: "lint failed"), .signingFailed(detail: "error: Load key failed\nmore"), .patchDoesNotApply, .lockFileExists(path: ".git/index.lock"), .undoNoLongerApplies]
        for code in codes {
            let copy = ErrorCopy.changes(GitError(code))
            #expect(copy != nil, "no copy for \(code.name)")
            #expect(copy?.title.isEmpty == false)
            #expect(copy?.message.contains("\u{2014}") == false)
            #expect(copy?.message.contains("\u{2013}") == false)
        }
        #expect(ErrorCopy.changes(GitError(.refExists)) == nil)
        let hook = ErrorCopy(GitError(.hookFailed(name: "pre-commit", output: "swift-format lint --strict: 2 problems")))
        #expect(hook.title == "The pre-commit hook stopped this")
        #expect(hook.message.hasPrefix("swift-format lint --strict: 2 problems"))
        let signing = ErrorCopy(GitError(.signingFailed(detail: "error: Load key failed\nmore")))
        #expect(signing.message.hasPrefix("error: Load key failed\n\n"))
        let long = (1...30).map { "line \($0)" }.joined(separator: "\n")
        #expect(ErrorCopy.hookTail("\n\n" + long).split(separator: "\n").count == ErrorCopy.hookOutputLines)
        #expect(ErrorCopy.hookTail(long).hasSuffix("line 30"))
    }

    @Test func splitRowsKeepTheirLineIndices() {
        let hunk = Hunk(header: "@@ -1,3 +1,3 @@", oldStart: 1, oldCount: 3, newStart: 1, newCount: 3, title: "", lines: [
            DiffLine(kind: .context, text: "a", oldNumber: 1, newNumber: 1),
            DiffLine(kind: .del, text: "b", oldNumber: 2),
            DiffLine(kind: .del, text: "c", oldNumber: 3),
            DiffLine(kind: .add, text: "B", newNumber: 2),
            DiffLine(kind: .noNewline, text: "\\ No newline at end of file"),
            DiffLine(kind: .add, text: "D", newNumber: 3)
        ])
        let rows = IndexedSplitRow.rows(hunk)
        #expect(rows.count == 3)
        #expect(rows[0].context && rows[0].old?.index == 0)
        #expect(rows[1].old?.index == 1 && rows[1].new?.index == 3)
        #expect(rows[2].old?.index == 2 && rows[2].new?.index == 5)
    }

    @MainActor
    @Test func lineClicksFollowThePrototypeSelectionRules() {
        let diff = FileDiff(path: "Lines.swift", status: .modified, hunks: [
            Hunk(header: "@@ -1,4 +1,4 @@", oldStart: 1, oldCount: 4, newStart: 1, newCount: 4, title: "", lines: [
                DiffLine(kind: .context, text: "a", oldNumber: 1, newNumber: 1),
                DiffLine(kind: .del, text: "b", oldNumber: 2),
                DiffLine(kind: .add, text: "B", newNumber: 2),
                DiffLine(kind: .add, text: "C", newNumber: 3),
                DiffLine(kind: .context, text: "d", oldNumber: 3, newNumber: 4)
            ])
        ])
        let model = ChangesModel()
        model.present(diff, for: ChangesPick(path: "Lines.swift", side: .unstaged))
        #expect(model.isLineLevel)
        model.click(LineID(hunk: 0, line: 1), extending: false, toggling: false)
        #expect(model.lines?.sorted == [LineID(hunk: 0, line: 1)])
        model.click(LineID(hunk: 0, line: 3), extending: true, toggling: false)
        #expect(model.lines?.sorted == [LineID(hunk: 0, line: 1), LineID(hunk: 0, line: 2), LineID(hunk: 0, line: 3)])
        model.click(LineID(hunk: 0, line: 2), extending: false, toggling: true)
        #expect(model.lines?.sorted == [LineID(hunk: 0, line: 1), LineID(hunk: 0, line: 3)])
        model.click(LineID(hunk: 0, line: 0), extending: false, toggling: false)
        #expect(model.lines?.count == 2)
        model.click(LineID(hunk: 0, line: 3), extending: false, toggling: false)
        model.click(LineID(hunk: 0, line: 3), extending: false, toggling: false)
        #expect(model.lines?.isEmpty ?? true)
    }
}
