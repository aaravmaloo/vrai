import Foundation
import Testing
@testable import VraiGit

struct PatchBuilderTests {
    static func file(_ diff: String) -> FileDiff {
        PatchParser.parse(diff).first!
    }

    static let mixed = file("""
    diff --git a/f.txt b/f.txt
    index 1111111..2222222 100644
    --- a/f.txt
    +++ b/f.txt
    @@ -1,4 +1,4 @@
     one
    -two
    -three
    +TWO
    +THREE
     four

    """)

    @Test func stagingOneAddedLineDropsTheOtherAdditionsAndKeepsDeletionsAsContext() {
        let patch = PatchBuilder.patch(file: Self.mixed, lines: [LineID(hunk: 0, line: 3)], reverse: false)
        #expect(patch == """
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -1,4 +1,5 @@
         one
         two
         three
        +TWO
         four

        """)
    }

    @Test func stagingOneDeletedLine() {
        let patch = PatchBuilder.patch(file: Self.mixed, lines: [LineID(hunk: 0, line: 2)], reverse: false)
        #expect(patch == """
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -1,4 +1,3 @@
         one
         two
        -three
         four

        """)
    }

    @Test func reversePatchesTurnUnselectedAdditionsIntoContextAndDropUnselectedDeletions() {
        let patch = PatchBuilder.patch(file: Self.mixed, lines: [LineID(hunk: 0, line: 4)], reverse: true)
        #expect(patch == """
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -1,3 +1,4 @@
         one
         TWO
        +THREE
         four

        """)
    }

    @Test func nothingSelectedBuildsNothing() {
        #expect(PatchBuilder.patch(file: Self.mixed, lines: [], reverse: false) == nil)
        #expect(PatchBuilder.patch(file: Self.mixed, lines: [LineID(hunk: 0, line: 0)], reverse: false) == nil)
    }

    @Test func laterHunksAreShiftedByEarlierPartialHunks() {
        let file = Self.file("""
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -1,2 +1,4 @@
         a
        +b
        +c
         d
        @@ -20,2 +22,3 @@
         t
        +u
         v

        """)
        let patch = PatchBuilder.patch(file: file, lines: [LineID(hunk: 0, line: 1), LineID(hunk: 1, line: 1)], reverse: false)
        #expect(patch?.contains("@@ -1,2 +1,3 @@\n a\n+b\n d\n") == true)
        #expect(patch?.contains("@@ -20,2 +21,3 @@\n t\n+u\n v\n") == true)
    }

    @Test func addingAfterALastLineWithoutNewlineGivesThatLineANewline() {
        let file = Self.file("""
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -1,2 +1,3 @@
         a
        -b
        \\ No newline at end of file
        +b
        +c
        \\ No newline at end of file

        """)
        let patch = PatchBuilder.patch(file: file, lines: [LineID(hunk: 0, line: 4)], reverse: false)
        #expect(patch == """
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -1,2 +1,3 @@
         a
        -b
        \\ No newline at end of file
        +b
        +c
        \\ No newline at end of file

        """)
        let onlyDeletion = PatchBuilder.patch(file: file, lines: [LineID(hunk: 0, line: 1)], reverse: false)
        #expect(onlyDeletion == """
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -1,2 +1,1 @@
         a
        -b
        \\ No newline at end of file

        """)
    }

    @Test func newFilesKeepTheCreationHeaderWhenStagedAndBecomeEditsWhenPartlyUnstaged() {
        let file = Self.file("""
        diff --git a/new file.txt b/new file.txt
        new file mode 100755
        index 0000000..3333333
        --- /dev/null
        +++ b/new file.txt
        @@ -0,0 +1,3 @@
        +x
        +y
        +z

        """)
        #expect(file.status == .added)
        let staged = PatchBuilder.patch(file: file, lines: [LineID(hunk: 0, line: 1)], reverse: false)
        #expect(staged == "diff --git a/new file.txt b/new file.txt\nnew file mode 100755\n--- /dev/null\n+++ b/new file.txt\t\n@@ -0,0 +1,1 @@\n+y\n")
        let partly = PatchBuilder.patch(file: file, lines: [LineID(hunk: 0, line: 0)], reverse: true)
        #expect(partly == "diff --git a/new file.txt b/new file.txt\n--- a/new file.txt\t\n+++ b/new file.txt\t\n@@ -1,2 +1,3 @@\n+x\n y\n z\n")
        let whole = PatchBuilder.patch(file: file, lines: Set(LineSelection.all(in: file, side: .staged).lines), reverse: true)
        #expect(whole?.hasPrefix("diff --git a/new file.txt b/new file.txt\nnew file mode 100755\n--- /dev/null\n") == true)
    }

    @Test func deletedFilesBecomeEditsUntilEveryLineIsStaged() {
        let file = Self.file("""
        diff --git a/gone.txt b/gone.txt
        deleted file mode 100644
        index 3333333..0000000
        --- a/gone.txt
        +++ /dev/null
        @@ -1,2 +0,0 @@
        -x
        -y

        """)
        #expect(file.status == .deleted)
        let partly = PatchBuilder.patch(file: file, lines: [LineID(hunk: 0, line: 0)], reverse: false)
        #expect(partly == "diff --git a/gone.txt b/gone.txt\n--- a/gone.txt\n+++ b/gone.txt\n@@ -1,2 +1,1 @@\n-x\n y\n")
        let whole = PatchBuilder.patch(file: file, lines: [LineID(hunk: 0, line: 0), LineID(hunk: 0, line: 1)], reverse: false)
        #expect(whole == "diff --git a/gone.txt b/gone.txt\ndeleted file mode 100644\n--- a/gone.txt\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-x\n-y\n")
        let unstage = PatchBuilder.patch(file: file, lines: [LineID(hunk: 0, line: 1)], reverse: true)
        #expect(unstage == "diff --git a/gone.txt b/gone.txt\ndeleted file mode 100644\n--- a/gone.txt\n+++ /dev/null\n@@ -1,1 +0,0 @@\n-y\n")
    }

    @Test func crlfLinesKeepTheirCarriageReturns() {
        let file = Self.file("diff --git a/w.txt b/w.txt\n--- a/w.txt\n+++ b/w.txt\n@@ -1,2 +1,2 @@\n a\r\n-b\r\n+B\r\n")
        #expect(file.hunks.first?.lines.map(\.text) == ["a\r", "b\r", "B\r"])
        let patch = PatchBuilder.patch(file: file, lines: [LineID(hunk: 0, line: 2)], reverse: false)
        #expect(patch?.hasSuffix("@@ -1,2 +1,3 @@\n a\r\n b\r\n+B\r\n") == true)
    }

    @Test func binaryFilesAreRefused() {
        let file = Self.file("diff --git a/a.png b/a.png\nindex 1..2 100644\nBinary files a/a.png and b/a.png differ\n")
        #expect(file.isBinary)
        #expect(PatchBuilder.patch(file: file, lines: [], reverse: false) == nil)
        #expect(!PatchBuilder.canBuild(for: file))
    }

    @Test func pathsThatNeedQuotingAreQuoted() {
        #expect(PatchBuilder.quoted("a/plain name.txt") == "a/plain name.txt")
        #expect(PatchBuilder.quoted("a/tab\there") == "\"a/tab\\there\"")
        #expect(PatchBuilder.quoted("a/quote\"d") == "\"a/quote\\\"d\"")
        #expect(PatchBuilder.quoted("a/caf\u{e9}") == "a/caf\u{e9}")
        #expect(PatchBuilder.label("b/with space") == "b/with space\t")
    }
}

struct LineSelectionTests {
    @Test func clickingPortsThePrototypeGutterBehaviour() {
        var selection = LineSelection(file: PatchBuilderTests.mixed, side: .unstaged)
        selection.click(LineID(hunk: 0, line: 0))
        #expect(selection.isEmpty)
        selection.click(LineID(hunk: 0, line: 1))
        #expect(selection.sorted == [LineID(hunk: 0, line: 1)])
        selection.click(LineID(hunk: 0, line: 1))
        #expect(selection.isEmpty)
        selection.click(LineID(hunk: 0, line: 1))
        selection.click(LineID(hunk: 0, line: 4), extending: true)
        #expect(selection.sorted == [1, 2, 3, 4].map { LineID(hunk: 0, line: $0) })
        selection.click(LineID(hunk: 0, line: 3), toggling: true)
        #expect(selection.sorted == [1, 2, 4].map { LineID(hunk: 0, line: $0) })
        selection.click(LineID(hunk: 0, line: 2))
        #expect(selection.sorted == [LineID(hunk: 0, line: 2)])
        #expect(selection.deletions == 1 && selection.additions == 0)
    }

    static let twoHunks = PatchBuilderTests.file("""
    diff --git a/f.txt b/f.txt
    index 1111111..2222222 100644
    --- a/f.txt
    +++ b/f.txt
    @@ -1,3 +1,3 @@
     one
    -two
    +TWO
    @@ -10,3 +10,4 @@
     ten
    -eleven
    +ELEVEN
    +twelve

    """)

    @Test func shiftClickExtendsAcrossHunks() {
        var selection = LineSelection(file: Self.twoHunks, side: .unstaged)
        selection.click(LineID(hunk: 0, line: 2))
        selection.click(LineID(hunk: 1, line: 2), extending: true)
        #expect(selection.sorted == [LineID(hunk: 0, line: 2), LineID(hunk: 1, line: 1), LineID(hunk: 1, line: 2)])
    }

    @Test func draggingSelectsEveryChangedLineInRangeInEitherDirection() {
        var selection = LineSelection(file: Self.twoHunks, side: .unstaged)
        selection.drag(from: LineID(hunk: 1, line: 3), to: LineID(hunk: 0, line: 0))
        #expect(selection.sorted == [LineID(hunk: 0, line: 1), LineID(hunk: 0, line: 2), LineID(hunk: 1, line: 1), LineID(hunk: 1, line: 2), LineID(hunk: 1, line: 3)])
        #expect(selection.anchor == LineID(hunk: 1, line: 3))
        selection.drag(from: LineID(hunk: 1, line: 3), to: LineID(hunk: 1, line: 2))
        #expect(selection.sorted == [LineID(hunk: 1, line: 2), LineID(hunk: 1, line: 3)])
        selection.drag(from: LineID(hunk: 0, line: 0), to: LineID(hunk: 0, line: 1), keeping: [LineID(hunk: 1, line: 3), LineID(hunk: 1, line: 0)])
        #expect(selection.sorted == [LineID(hunk: 0, line: 1), LineID(hunk: 1, line: 3)])
    }

    @Test func hunkAndFileSelectionsPickEveryChangedLine() {
        let hunk = LineSelection.hunk(0, in: PatchBuilderTests.mixed, side: .unstaged)
        #expect(hunk.count == 4)
        #expect(hunk.limited(toHunk: 1).isEmpty)
        #expect(LineSelection.all(in: PatchBuilderTests.mixed, side: .staged).lines == hunk.lines)
        let filtered = LineSelection(file: PatchBuilderTests.mixed, side: .unstaged, lines: [LineID(hunk: 0, line: 0), LineID(hunk: 3, line: 1)])
        #expect(filtered.isEmpty)
    }
}
