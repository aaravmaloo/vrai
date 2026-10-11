import Foundation
import Testing
@testable import VraiGit

struct ConflictResolverTests {
    static func recorded(_ fixture: String, _ name: String) throws -> String {
        try String(contentsOf: Recorded.directory.appending(path: "\(fixture)/conflict-\(name).txt"), encoding: .utf8)
    }

    static let lane = "Sources_VraiGit_Graph_LaneLayout.swift"

    @Test func resolvesOneBlockAndKeepsTheOthersByteForByte() throws {
        let text = try Self.recorded("conflict", Self.lane)
        let blocks = ConflictResolver.conflicts(in: text)
        #expect(blocks.count == 2)
        let ours = try ConflictResolver.resolve(text, block: 1, with: .ours)
        #expect(ConflictResolver.conflicts(in: ours).count == 1)
        #expect(ours.contains("    var haloSize: CGFloat = 16\n\n    func x(for lane: Int) -> CGFloat {\n        CGFloat(lane) * laneWidth + laneWidth / 2 + inset\n    }"))
        #expect(!ours.contains("instanceBuffer"))
        let second = text.components(separatedBy: "\n")[blocks[1].range].joined(separator: "\n")
        #expect(ours.contains(second))
        #expect(ours.hasSuffix("}\n"))

        let theirs = try ConflictResolver.resolve(ours, block: 1, with: .theirs)
        #expect(!ConflictResolver.hasMarkers(theirs))
        #expect(theirs.contains("    func node(at lane: Int, in rect: CGRect, merge: Bool = false, instanced: Bool = false) -> Path {\n        let size"))
        #expect(!theirs.contains("func halo(at lane"))
    }

    @Test func bothKeepsCurrentThenIncoming() throws {
        let text = try Self.recorded("conflict", Self.lane)
        let both = try ConflictResolver.resolve(text, block: 2, with: .both)
        let lines = both.components(separatedBy: "\n")
        let halo = try #require(lines.firstIndex { $0.contains("func halo(at lane") })
        let instanced = try #require(lines.firstIndex { $0.contains("instanced: Bool = false") })
        #expect(halo < instanced)
        #expect(ConflictResolver.conflicts(in: both).count == 1)
    }

    @Test func wholeFileChoiceResolvesEveryBlock() throws {
        let text = try Self.recorded("conflict", Self.lane)
        let theirs = try ConflictResolver.resolve(text, block: nil, with: .theirs)
        #expect(!ConflictResolver.hasMarkers(theirs))
        #expect(theirs.contains("instanceBuffer"))
        #expect(!theirs.contains("haloSize"))
    }

    @Test func baseComesFromDiff3Sections() throws {
        let text = try Self.recorded("edge", "conflict.txt")
        let blocks = ConflictResolver.conflicts(in: text)
        #expect(blocks.map(\.base) == [["line 2"], ["line 8"]])
        let base = try ConflictResolver.resolve(text, block: 2, with: .base)
        #expect(base.hasSuffix("line 7\nline 8\nline 9\n"))
        #expect(ConflictResolver.conflicts(in: base).count == 1)
        let all = try ConflictResolver.resolve(text, block: nil, with: .base)
        #expect(all == (1...9).map { "line \($0)" }.joined(separator: "\n") + "\n")
        let bothAdded = try ConflictResolver.resolve(try Self.recorded("edge", "both-added.txt"), block: 1, with: .base)
        #expect(bothAdded == "")
    }

    @Test func baseIsLookedUpInADiff3Rendering() throws {
        let plain = "a\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> other\nz\n"
        #expect(ConflictResolver.needsBase(plain, block: 1))
        #expect(throws: ConflictResolver.Failure.noBase(1)) { try ConflictResolver.resolve(plain, block: 1, with: .base) }
        let rendering = "a\n<<<<<<< 1111111\nours\n||||||| 2222222\nbase line\n=======\ntheirs\n>>>>>>> 3333333\nz\n"
        #expect(try ConflictResolver.resolve(plain, block: 1, with: .base, diff3: rendering) == "a\nbase line\nz\n")
        let wider = "a\n<<<<<<< 1\nkept\nours\n||||||| 2\nkept\nold\n=======\nkept\ntheirs\n>>>>>>> 3\nz\n"
        #expect(try ConflictResolver.resolve(plain, block: 1, with: .base, diff3: wider) == "a\nkept\nold\nz\n")
    }

    @Test func baseSpansNeighbouringDiff3Regions() throws {
        let joined = "a\n<<<<<<< HEAD\nhalo\n\nfunc x\nmine\n=======\nmetal\n\nfunc x\nyours\n>>>>>>> other\nz\n"
        let split = "a\n<<<<<<< 1\nhalo\n||||||| 2\n=======\nmetal\n>>>>>>> 3\n\nfunc x\n<<<<<<< 1\nmine\n||||||| 2\nold\n=======\nyours\n>>>>>>> 3\nz\n"
        #expect(try ConflictResolver.resolve(joined, block: 1, with: .base, diff3: split) == "a\n\nfunc x\nold\nz\n")
        let alternatives = ConflictResolver.alternatives(in: split)
        #expect(alternatives.count == 3)
        #expect(alternatives.last?.base == ["", "func x", "old"])
        #expect(ConflictResolver.alternatives(in: split, longestRun: 1).count == 2)
        let lone = "a\n<<<<<<< HEAD\nmine\n=======\nyours\n>>>>>>> other\nz\n"
        #expect(try ConflictResolver.resolve(lone, block: 1, with: .base, diff3: split) == "a\nold\nz\n")
    }

    @Test func lineEndingsAndMissingFinalNewlineSurvive() throws {
        let crlf = "one\r\n<<<<<<< HEAD\r\nmine\r\n=======\r\nyours\r\n>>>>>>> other\r\ntwo"
        #expect(ConflictResolver.conflicts(in: crlf).count == 1)
        #expect(try ConflictResolver.resolve(crlf, block: 1, with: .theirs) == "one\r\nyours\r\ntwo")
        #expect(try ConflictResolver.resolve(crlf, block: 1, with: .both) == "one\r\nmine\r\nyours\r\ntwo")
        let rendering = "one\n<<<<<<< 1\nmine\n||||||| 2\nold\n=======\nyours\n>>>>>>> 3\ntwo"
        #expect(try ConflictResolver.resolve(crlf, block: 1, with: .base, diff3: rendering) == "one\r\nold\r\ntwo")
    }

    @Test func missingBlockThrows() throws {
        let text = try Self.recorded("edge", "conflict.txt")
        #expect(throws: ConflictResolver.Failure.blockNotFound(3)) { try ConflictResolver.resolve(text, block: 3, with: .ours) }
        #expect(!ConflictResolver.hasMarkers("no markers here\n"))
    }
}
