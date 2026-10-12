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

    @Test func rangeCoversEveryRowBetweenTheEndsInListOrder() {
        let order = Self.order
        #expect(order.map(\.path) == ["c.swift", "a.swift", "b.swift", "d.md"])
        #expect(FilePicks.range(from: Self.pick("c.swift", .staged), to: Self.pick("b.swift"), in: order).map(\.path) == ["c.swift", "a.swift", "b.swift"])
        #expect(FilePicks.range(from: Self.pick("d.md"), to: Self.pick("a.swift"), in: order).map(\.path) == ["a.swift", "b.swift", "d.md"])
        #expect(FilePicks.range(from: Self.pick("gone.swift"), to: Self.pick("a.swift"), in: order) == [Self.pick("a.swift")])
    }

    @Test func commandClickAddsAndRemovesButNeverEmptiesTheSelection() {
        let a = Self.pick("a.swift")
        let b = Self.pick("b.swift")
        let both = FilePicks.toggled(b, in: [a])
        #expect(both == [a, b])
        #expect(FilePicks.toggled(a, in: both) == [b])
        #expect(FilePicks.toggled(a, in: [a]) == [a])
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
        let picked: Set = [Self.pick("d.md"), Self.pick("a.swift")]
        #expect(FilePicks.ordered(picked, in: Self.order).map(\.path) == ["a.swift", "d.md"])
    }

    @Test func pathsAreDedupedWhenAFileIsPickedOnBothSides() {
        #expect(ChangesSelectionPaths.unique(["a.swift", "b.swift", "a.swift"]) == ["a.swift", "b.swift"])
    }
}
