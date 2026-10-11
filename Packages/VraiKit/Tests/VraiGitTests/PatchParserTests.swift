import Foundation
import Testing
@testable import VraiGit

struct PatchParserTests {
    @Test func everydayStagedDiffIncludesTheRename() throws {
        let files = PatchParser.parse(try Recorded.data("everyday", "diff-cached"))
        let byPath = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0) })
        let rename = try #require(byPath["Sources/VraiUI/History/LaneColors.swift"])
        #expect(rename.status == .renamed)
        #expect(rename.oldPath == "Sources/VraiUI/History/Palette.swift")
        #expect(rename.similarity == 64)
        let cell = try #require(byPath["Sources/VraiUI/History/GraphCell.swift"])
        #expect(cell.hunks.count == 2)
        #expect(cell.hunks[0].oldStart == 24)
        #expect(cell.hunks[0].title == "struct GraphCell: View {")
        #expect(cell.additions == 13)
        #expect(cell.deletions == 2)
        let lane = try #require(byPath["Sources/VraiGit/Graph/LaneLayout.swift"])
        #expect(lane.hunks.count == 1)
        #expect(lane.hunks[0].lines.first { $0.kind == .add }?.text == "    var haloSize: CGFloat = 16")
    }

    @Test func lineNumbersFollowTheHunkHeader() throws {
        let files = PatchParser.parse(try Recorded.data("everyday", "diff-worktree"))
        let lane = try #require(files.first { $0.path == "Sources/VraiGit/Graph/LaneLayout.swift" })
        let hunk = try #require(lane.hunks.first)
        #expect(hunk.oldStart == 65)
        var old = hunk.oldStart
        var new = hunk.newStart
        for line in hunk.lines {
            switch line.kind {
            case .context:
                #expect(line.oldNumber == old && line.newNumber == new)
                old += 1
                new += 1
            case .add:
                #expect(line.newNumber == new && line.oldNumber == nil)
                new += 1
            case .del:
                #expect(line.oldNumber == old && line.newNumber == nil)
                old += 1
            case .noNewline:
                break
            }
        }
        #expect(old - hunk.oldStart == hunk.oldCount)
        #expect(new - hunk.newStart == hunk.newCount)
        #expect(files.contains { $0.path == "Vendor/libgit2" && $0.isSubmodule })
        #expect(files.contains { $0.path == "Resources/Graph.xcassets/Contents.json" && $0.status == .deleted })
    }

    @Test func edgeWorktreeDiffHandlesEveryOddity() throws {
        let files = PatchParser.parse(try Recorded.data("edge", "diff-worktree"))
        let byPath = Dictionary(files.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        #expect(byPath["conflict.txt"]?.status == .conflicted)
        #expect(byPath["both-added.txt"]?.status == .conflicted)
        #expect(byPath["Résumé.md"]?.hunks.first?.lines.contains { $0.kind == .add && $0.text == "Naïve café notes, edited." } == true)
        let spaced = try #require(byPath["c d.txt"])
        #expect(spaced.hunks.first?.lines.last?.text == "seven")
        #expect(byPath["image.png"]?.isBinary == true)
        #expect(byPath["script.sh"]?.oldMode == "100644")
        #expect(byPath["script.sh"]?.newMode == "100755")
        #expect(byPath["link-target.txt"]?.status == .typeChanged)
        #expect(byPath["staged new.txt"]?.hunks.first?.lines.contains { $0.kind == .add && $0.text == "then changed" } == true)
    }

    @Test func quotedPathsAndNoNewlineMarkers() {
        let patch = """
        diff --git "a/quote\\"d.txt" "b/quote\\"d.txt"
        index 1111111..2222222 100644
        --- "a/quote\\"d.txt"
        +++ "b/quote\\"d.txt"
        @@ -1 +1 @@
        -quoted name
        \\ No newline at end of file
        +quoted name, changed
        \\ No newline at end of file
        diff --git "a/caf\\303\\251.txt" "b/caf\\303\\251.txt"
        new file mode 100644
        index 0000000..3333333
        --- /dev/null
        +++ "b/caf\\303\\251.txt"
        @@ -0,0 +1,2 @@
        +one
        +two

        """
        let files = PatchParser.parse(patch)
        #expect(files.map(\.path) == ["quote\"d.txt", "café.txt"])
        #expect(files[0].hunks[0].lines.map(\.kind) == [.del, .noNewline, .add, .noNewline])
        #expect(files[1].status == .added)
        #expect(files[1].hunks[0].newCount == 2)
        #expect(files[1].hunks[0].oldCount == 0)
    }

    @Test func wordRangesMarkOnlyWhatChanged() {
        let (old, new) = WordDiff.ranges("        CGFloat(lane) * laneWidth + laneWidth / 2", "        CGFloat(lane) * laneWidth + laneWidth / 2 + inset")
        #expect(old.isEmpty)
        #expect(new == [49..<57])
        let swap = WordDiff.ranges("    var height: CGFloat = 28", "    var height: CGFloat = Vrai.Size.row")
        #expect(swap.0 == [26..<28])
        #expect(swap.1 == [26..<39])
        let unrelated = WordDiff.ranges("import SwiftUI", "let x = 42 // completely different")
        #expect(unrelated.0.isEmpty && unrelated.1.isEmpty)
    }

    @Test func annotatedHunksPairDeletionsWithAdditions() throws {
        let files = PatchParser.parse(try Recorded.data("everyday", "diff-cached"))
        let cell = try #require(files.first { $0.path == "Sources/VraiUI/History/GraphCell.swift" })
        let first = cell.hunks[0].lines
        let del = try #require(first.first { $0.kind == .del })
        #expect(!del.wordRanges.isEmpty)
    }
}

struct ConflictParserTests {
    @Test func conflictFixtureBlocks() throws {
        let lane = String(decoding: try Data(contentsOf: Recorded.directory.appending(path: "conflict/conflict-Sources_VraiGit_Graph_LaneLayout.swift.txt")).prefix(1 << 20), as: UTF8.self)
        let blocks = ConflictParser.blocks(in: lane)
        let conflicts = blocks.compactMap { if case .conflict(let c) = $0 { c } else { nil } }
        #expect(conflicts.count == 2)
        #expect(conflicts[0].oursLabel == "HEAD")
        #expect(conflicts[0].theirsLabel == "mira/spike/metal-graph")
        #expect(conflicts[0].ours.contains("    var haloSize: CGFloat = 16"))
        #expect(conflicts[0].theirs.contains("    var instanceBuffer: MTLBuffer?"))
        #expect(conflicts.map(\.index) == [1, 2])
        let rebuilt = blocks.reduce(0) { total, block in
            switch block {
            case .context(let lines, _): total + lines.count
            case .conflict(let c): total + c.range.count
            }
        }
        #expect(rebuilt == lane.split(separator: "\n", omittingEmptySubsequences: false).count - 1)

        let cell = String(decoding: try Data(contentsOf: Recorded.directory.appending(path: "conflict/conflict-Sources_VraiUI_History_GraphCell.swift.txt")), as: UTF8.self)
        let cellConflicts = ConflictParser.blocks(in: cell).compactMap { if case .conflict(let c) = $0 { c } else { nil } }
        #expect(cellConflicts.count == 1)
        #expect(cellConflicts[0].theirs.first == "        MetalGraphView(row: row, lanes: lanes)")
    }

    @Test func diff3BaseSection() {
        let text = "line 1\n<<<<<<< HEAD\nline 2 from main\n||||||| 9fb36a1\nline 2\n=======\nline 2 from other\n>>>>>>> other\nline 3\n"
        let blocks = ConflictParser.blocks(in: text)
        #expect(blocks.count == 3)
        guard case .conflict(let c) = blocks[1] else {
            Issue.record("expected a conflict")
            return
        }
        #expect(c.base == ["line 2"])
        #expect(c.baseLabel == "9fb36a1")
        #expect(c.ours == ["line 2 from main"])
        #expect(c.theirs == ["line 2 from other"])
        #expect(c.range == 1..<8)
        #expect(ConflictParser.hasMarkers(text))
        #expect(!ConflictParser.hasMarkers("<<<<<<< not closed\nline\n"))
    }
}
