import Foundation
import Testing
import VraiGit
@testable import VraiUI

struct FilePicksTests {
    static let working = [
        WorkingFile(path: "a.swift", status: .modified, staged: .none, worktreeStatus: .modified),
        WorkingFile(path: "b.swift", status: .modified, staged: .none, worktreeStatus: .modified),
        WorkingFile(path: "c.swift", status: .modified, staged: .full, indexStatus: .modified),
        WorkingFile(path: "d.md", status: .untracked, staged: .none, worktreeStatus: .untracked)
    ]

    static var order: [ChangesPick] { ChangeGroups(working).picks }

    static func pick(_ path: String, _ side: LineSelection.Side = .unstaged) -> ChangesPick {
        ChangesPick(path: path, side: side)
    }

    @Test func selectionFollowsFilesWhenTheyMoveBetweenGroups() {
        let staged = [
            WorkingFile(path: "a.swift", status: .modified, staged: .full, indexStatus: .modified),
            WorkingFile(path: "b.swift", status: .modified, staged: .full, indexStatus: .modified),
            WorkingFile(path: "c.swift", status: .modified, staged: .full, indexStatus: .modified)
        ]
        let resolved = FilePicks.resolve([Self.pick("a.swift"), Self.pick("b.swift"), Self.pick("gone.swift")], in: staged)
        #expect(resolved == [Self.pick("a.swift", .staged), Self.pick("b.swift", .staged)])
    }

    @Test func orderedSelectionMatchesTheList() {
        #expect(Self.order.map(\.path) == ["c.swift", "a.swift", "b.swift", "d.md"])
        let picked: Set = [Self.pick("d.md"), Self.pick("a.swift")]
        #expect(FilePicks.ordered(picked, in: Self.order).map(\.path) == ["a.swift", "d.md"])
    }

    @Test func pathsAreDedupedWhenAFileIsPickedOnBothSides() {
        #expect(ChangesSelectionPaths.unique(["a.swift", "b.swift", "a.swift"]) == ["a.swift", "b.swift"])
    }

    @Test func leadIsTheNewlyAddedRowFarthestFromTheCurrentPick() {
        let a = Self.pick("a.swift")
        let b = Self.pick("b.swift")
        let d = Self.pick("d.md")
        #expect(FilePicks.lead(of: [a, b, d], after: [a], pick: a, in: Self.order) == d)
        #expect(FilePicks.lead(of: [a, b], after: [a, b, d], pick: a, in: Self.order) == a)
        #expect(FilePicks.lead(of: [b, d], after: [a, b, d], pick: a, in: Self.order) == b)
    }
}
