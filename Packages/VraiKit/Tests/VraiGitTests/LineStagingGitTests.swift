import Foundation
import Testing
@testable import VraiGit

struct ModelLine: Equatable {
    var text: String
    var newline: Bool
}

enum LineModel {
    static func lines(_ data: Data?) -> [ModelLine] {
        guard let data, !data.isEmpty else { return [] }
        var parts = data.split(separator: 0x0A, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        let terminated = data.last == 0x0A
        if terminated { parts.removeLast() }
        return parts.enumerated().map { ModelLine(text: $0.element, newline: terminated || $0.offset < parts.count - 1) }
    }

    static func data(_ lines: [ModelLine]) -> Data {
        var text = ""
        for (index, line) in lines.enumerated() {
            text += line.text
            if index < lines.count - 1 || line.newline { text += "\n" }
        }
        return Data(text.utf8)
    }

    static func apply(_ file: FileDiff, base: [ModelLine], selected: Set<LineID>, reverse: Bool) -> [ModelLine] {
        var out: [ModelLine] = []
        var cursor = 0
        for (index, hunk) in file.hunks.enumerated() {
            let count = reverse ? hunk.newCount : hunk.oldCount
            let start = reverse ? hunk.newStart : hunk.oldStart
            let first = count == 0 ? start : start - 1
            out += base[cursor..<first]
            cursor = first
            for (position, line) in hunk.lines.enumerated() {
                let noNewline = position + 1 < hunk.lines.count && hunk.lines[position + 1].kind == .noNewline
                let picked = selected.contains(LineID(hunk: index, line: position))
                let removes: DiffLine.Kind = reverse ? .add : .del
                let inserts: DiffLine.Kind = reverse ? .del : .add
                switch line.kind {
                case .context:
                    out.append(base[cursor])
                    cursor += 1
                case removes:
                    if !picked { out.append(base[cursor]) }
                    cursor += 1
                case inserts:
                    if picked { out.append(ModelLine(text: line.text, newline: !noNewline)) }
                default:
                    break
                }
            }
        }
        out += base[cursor...]
        return out
    }
}

@Suite(.enabled(if: TestSandbox.available, "run Scripts/make-fixtures.sh first"))
struct LineStagingGitTests {
    struct Scenario: Sendable, CustomTestStringConvertible {
        var name: String
        var path: String
        var old: String?
        var new: String?
        var testDescription: String { name }
    }

    static let thirty = (1...30).map { "line \($0)\n" }.joined()
    static let thirtyChanged: String = {
        var lines = (1...30).map { "line \($0)" }
        lines[1] = "line two"
        lines.insert(contentsOf: ["inserted a", "inserted b"], at: 15)
        lines.remove(at: 29)
        return lines.joined(separator: "\n") + "\n"
    }()

    static let scenarios: [Scenario] = [
        Scenario(name: "mixed", path: "f.txt", old: "one\ntwo\nthree\nfour\n", new: "one\nTWO\nTHREE\nfour\nfive\n"),
        Scenario(name: "added only", path: "f.txt", old: "a\nb\nc\n", new: "a\nb\nX\nY\nc\n"),
        Scenario(name: "deleted only", path: "f.txt", old: "a\nb\nc\nd\ne\n", new: "a\ne\n"),
        Scenario(name: "several hunks", path: "long.txt", old: thirty, new: thirtyChanged),
        Scenario(name: "old has no newline", path: "f.txt", old: "a\nb", new: "a\nb\nc\n"),
        Scenario(name: "new has no newline", path: "f.txt", old: "a\nb\n", new: "a\nB"),
        Scenario(name: "neither has a newline", path: "f.txt", old: "a\nb", new: "a\nc"),
        Scenario(name: "untracked file", path: "fresh.txt", old: nil, new: "x\ny\nz"),
        Scenario(name: "deleted file", path: "gone.txt", old: "x\ny\nz\n", new: nil),
        Scenario(name: "crlf", path: "win.txt", old: "a\r\nb\r\n", new: "a\r\nB\r\nc\r\n"),
        Scenario(name: "spaces and unicode", path: "dir with space/na\u{ef}ve \"q\" file.txt", old: "k\nl\nm\n", new: "k\nL\nm\nn\n")
    ]

    static func subsets(_ ids: [LineID]) -> [Set<LineID>] {
        if ids.count <= 5 {
            return (1..<(1 << ids.count)).map { mask in Set(ids.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)) }
        }
        var out: [Set<LineID>] = ids.map { [$0] }
        out += ids.map { Set(ids).subtracting([$0]) }
        out.append(Set(ids))
        out.append(Set(ids.prefix(ids.count / 2)))
        out.append(Set(ids.suffix(ids.count / 2)))
        return out
    }

    func diff(_ repo: ScratchRepository, _ path: String, staged: Bool, untracked: Bool) async throws -> FileDiff {
        let command = StagingService.diffCommand(path: path, oldPath: nil, staged: staged, untracked: untracked)
        let output = try await repo.git.run(command).stdout
        return try #require(PatchParser.parse(output).first)
    }

    func expected(_ file: FileDiff, base: Data?, selected: Set<LineID>, reverse: Bool) -> Data? {
        let changed = LineSelection.all(in: file, side: .staged).lines
        if !reverse, file.status == .deleted, selected == changed { return nil }
        if reverse, file.status == .added, selected == changed { return nil }
        return LineModel.data(LineModel.apply(file, base: LineModel.lines(base), selected: selected, reverse: reverse))
    }

    func apply(_ repo: ScratchRepository, _ patch: String, cached: Bool, reverse: Bool) async throws {
        let command = StagingService.applyCommand(Data(patch.utf8), cached: cached, reverse: reverse)
        let result = try await repo.git.runAllowingFailure(command)
        #expect(result.succeeded, "git apply failed: \(result.errorOutput)\n\(patch)")
    }

    @Test(arguments: scenarios)
    func selectedLinesLandExactlyAsThePrototypeModelSays(_ scenario: Scenario) async throws {
        let repo = try await ScratchRepository.make()
        try repo.write("base.txt", "base\n")
        try repo.write(scenario.path, scenario.old.map { Data($0.utf8) })
        try await repo.commitAll("base")
        let oldData = scenario.old.map { Data($0.utf8) }
        let newData = scenario.new.map { Data($0.utf8) }
        try repo.write(scenario.path, newData)

        let unstaged = try await diff(repo, scenario.path, staged: false, untracked: scenario.old == nil)
        let unstagedIDs = LineSelection.all(in: unstaged, side: .unstaged).sorted
        #expect(!unstagedIDs.isEmpty)
        for subset in Self.subsets(unstagedIDs) {
            try await repo.run(["reset", "-q", "--", scenario.path])
            let forward = try #require(PatchBuilder.patch(file: unstaged, lines: subset, reverse: false))
            try await apply(repo, forward, cached: true, reverse: false)
            let index = try await repo.indexContent(scenario.path)
            #expect(index == expected(unstaged, base: oldData, selected: subset, reverse: false), "stage \(subset.sorted()) in \(scenario.name)\n\(forward)")

            try await repo.run(["reset", "-q", "--", scenario.path])
            let discard = try #require(PatchBuilder.patch(file: unstaged, lines: subset, reverse: true))
            try await apply(repo, discard, cached: false, reverse: true)
            #expect(repo.read(scenario.path) == expected(unstaged, base: newData, selected: subset, reverse: true), "discard \(subset.sorted()) in \(scenario.name)\n\(discard)")
            try repo.write(scenario.path, newData)
        }

        try await repo.run(["add", "-A"])
        let staged = try await diff(repo, scenario.path, staged: true, untracked: false)
        let stagedIDs = LineSelection.all(in: staged, side: .staged).sorted
        for subset in Self.subsets(stagedIDs) {
            try await repo.run(["add", "-A"])
            let reverse = try #require(PatchBuilder.patch(file: staged, lines: subset, reverse: true))
            try await apply(repo, reverse, cached: true, reverse: true)
            let index = try await repo.indexContent(scenario.path)
            #expect(index == expected(staged, base: newData, selected: subset, reverse: true), "unstage \(subset.sorted()) in \(scenario.name)\n\(reverse)")
        }
    }
}
