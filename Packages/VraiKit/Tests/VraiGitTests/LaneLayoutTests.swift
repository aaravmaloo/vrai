import Foundation
import Testing
@testable import VraiGit

struct LaneLayoutGoldenTests {
    struct Golden {
        var name: String
        var keepMissing: Bool
        var commits: [LayoutCommit]
        var lanes: Int
        var rows: [[String: Any]]
    }

    static let names = [
        "everyday-all", "everyday-current", "push-rejected-all", "conflict-all", "rebase-all", "detached-all", "bisect-all", "auth-all",
        "offline-all", "empty-all", "edge-all", "welcome-collections", "welcome-dotfiles", "large-first-2000"
    ]

    static func load(_ name: String) throws -> Golden {
        let json = try #require(try Fixture.json("graph/\(name).json") as? [String: Any])
        let commits = (json["commits"] as? [[String: Any]] ?? []).compactMap { raw -> LayoutCommit? in
            guard let id = (raw["id"] as? String).flatMap(OID.init) else { return nil }
            let parents = (raw["parents"] as? [String] ?? []).compactMap(OID.init)
            return LayoutCommit(id: id, parents: parents, color: raw["color"] as? Int)
        }
        return Golden(name: name, keepMissing: json["keepMissing"] as? Bool ?? false, commits: commits, lanes: json["lanes"] as? Int ?? 0, rows: json["rows"] as? [[String: Any]] ?? [])
    }

    static func segments(_ raw: Any?) -> [GraphRow.Segment] {
        (raw as? [[String: Any]] ?? []).map {
            GraphRow.Segment(from: $0["from"] as? Int ?? -1, to: $0["to"] as? Int ?? -1, color: $0["color"] as? Int ?? -1, kind: GraphRow.Segment.Kind(rawValue: $0["kind"] as? String ?? "") ?? .pass)
        }
    }

    static func compare(_ rows: [GraphRow], with golden: Golden) -> [String] {
        var problems: [String] = []
        if rows.count != golden.rows.count { problems.append("row count \(rows.count) != \(golden.rows.count)") }
        for (index, (row, expected)) in zip(rows, golden.rows).enumerated() {
            let lane = expected["lane"] as? Int
            let color = expected["color"] as? Int
            let width = expected["width"] as? Int
            let merge = expected["merge"] as? Bool
            if row.id.rawValue != expected["id"] as? String || row.lane != lane || row.color != color || row.width != width || row.isMerge != merge
                || row.top != segments(expected["top"]) || row.bottom != segments(expected["bottom"]) {
                problems.append("\(golden.name) row \(index) differs")
                if problems.count > 5 { break }
            }
        }
        return problems
    }

    @Test(arguments: names)
    func matchesTheJavaScriptReference(name: String) throws {
        let golden = try Self.load(name)
        let result = LaneLayout.layout(golden.commits, keepMissing: golden.keepMissing)
        #expect(Self.compare(result.rows, with: golden).isEmpty, "\(Self.compare(result.rows, with: golden))")
        #expect(result.lanes == golden.lanes)
    }

    @Test(arguments: [(name: "everyday-all", page: 7), (name: "rebase-all", page: 5), (name: "large-first-2000", page: 500), (name: "large-first-2000", page: 333)])
    func pagedLayoutEqualsOneShot(name: String, page: Int) throws {
        let golden = try Self.load(name)
        var colors: [OID: Int] = [:]
        for commit in golden.commits { if let color = commit.color { colors[commit.id] = color } }
        let known = Set(golden.commits.map(\.id))
        var layout = LaneLayout(keepMissing: true)
        var rows: [GraphRow] = []
        var start = 0
        while start < golden.commits.count {
            let slice = Array(golden.commits[start..<min(start + page, golden.commits.count)])
            rows += layout.append(slice, isKnown: { known.contains($0) }, colorOf: { colors[$0] })
            start += page
        }
        #expect(Self.compare(rows, with: golden).isEmpty)
        #expect(layout.maxWidth == golden.lanes)
    }

    @Test func headIsMarked() throws {
        let golden = try Self.load("everyday-all")
        let head = golden.commits[0].id
        let rows = LaneLayout.layout(golden.commits, head: head).rows
        #expect(rows.filter(\.isHead).map(\.id) == [head])
    }
}

struct BranchColorsTests {
    @Test func mainLinesGetLaneOneAndOthersCycle() {
        var colors = BranchColors()
        #expect(colors.assign("feature/a") == 1)
        #expect(colors.assign("main") == 0)
        #expect(colors.assign("master") == 0)
        let rest = (2...9).map { colors.assign("topic/\($0)") }
        #expect(rest == [2, 3, 4, 5, 6, 7, 1, 2])
        #expect(colors.assign("feature/a") == 1)
    }

    @Test func survivesEncoding() throws {
        var colors = BranchColors()
        colors.assign("main")
        colors.assign("feature/graph-renderer")
        let decoded = try JSONDecoder().decode(BranchColors.self, from: JSONEncoder().encode(colors))
        #expect(decoded == colors)
    }

    @Test func remoteBranchesShareTheLocalColor() throws {
        let tip = try #require(OID(String(repeating: "a", count: 40)))
        let remoteTip = try #require(OID(String(repeating: "b", count: 40)))
        var colors = BranchColors()
        let branches = [Branch(name: "feature/x", tip: tip, isCurrent: true), Branch(name: "main", tip: tip)]
        let remotes = [RemoteBranch(remote: "origin", name: "feature/x", tip: remoteTip)]
        colors.assign(branches: branches, remoteBranches: remotes, current: "feature/x")
        #expect(colors.color(for: "main") == 0)
        #expect(colors.color(for: "feature/x") == 1)
        let tips = colors.tipColors(branches: branches, remoteBranches: remotes, current: "feature/x")
        #expect(tips[tip] == 1)
        #expect(tips[remoteTip] == 1)
    }
}

struct CommandParserGoldenTests {
    static var goldens: [String: Any] {
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "VraiCoreTests/Fixtures/util-goldens.json")
        return (try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]) ?? [:]
    }

    @Test func parseCommandMatchesJavaScript() throws {
        let cases = try #require(Self.goldens["parseCommand"] as? [[String: Any]])
        #expect(cases.count == 46)
        for entry in cases {
            let input = entry["input"] as? String ?? ""
            let parsed = CommandParser.parse(input)
            guard let expected = entry["out"] as? [String: Any] else {
                #expect(parsed == nil, "\(input)")
                continue
            }
            #expect(parsed?.subcommand == expected["sub"] as? String, "\(input)")
            #expect(parsed?.rawArguments == expected["args"] as? [String], "\(input)")
            #expect(parsed?.risk.rawValue == expected["risk"] as? String, "\(input)")
            #expect(parsed?.text == expected["text"] as? String, "\(input)")
        }
    }

    @Test func tokenizeMatchesJavaScript() throws {
        let cases = try #require(Self.goldens["tokenize"] as? [[String: Any]])
        for entry in cases {
            let input = entry["input"] as? String ?? ""
            let expected = (entry["out"] as? [[String: Any]] ?? []).map { ($0["t"] as? String ?? "", $0["k"] as? String) }
            let tokens = CommandTokenizer.tokenize(input)
            #expect(tokens.map(\.text) == expected.map(\.0), "\(input)")
            #expect(tokens.map { $0.kind?.rawValue } == expected.map(\.1), "\(input)")
        }
    }

    @Test func typedCommandsNeverReachAShell() throws {
        let parsed = try #require(CommandParser.parse("git log; rm -rf x"))
        #expect(parsed.arguments == ["log;", "rm", "-rf", "x"])
        #expect(parsed.command.arguments == ["log;", "rm", "-rf", "x"])
        let quoted = try #require(CommandParser.parse("git commit -m \"Fix the thing\""))
        #expect(quoted.arguments == ["commit", "-m", "Fix the thing"])
        #expect(quoted.command.display == "git commit -m \"Fix the thing\"")
        #expect(CommandParser.parseImplied("status --short")?.arguments == ["status", "--short"])
    }

    @Test func displayQuotesLikeCommandPreview() {
        #expect(GitCommand(["push", "--force-with-lease", "origin", "main"]).display == "git push --force-with-lease origin main")
        #expect(GitCommand(["commit", "-m", "Fix the thing"]).display == "git commit -m \"Fix the thing\"")
        #expect(GitCommand(["commit", "-m", "Say \"hi\""]).display == "git commit -m 'Say \"hi\"'")
        #expect(GitCommand(["add", "--", "a b.txt", ""]).display == "git add -- \"a b.txt\" \"\"")
        let tokens = CommandTokenizer.tokenize(GitCommand(["commit", "-m", "Fix the thing"]).display)
        #expect(tokens.compactMap(\.kind) == [.git, .sub, .flag, .str])
    }
}

struct ProgressParserTests {
    @Test func cloneAndFetchLines() throws {
        let receiving = try #require(ProgressParser.parse("Receiving objects:  45% (1203/2670), 1.20 MiB | 2.30 MiB/s"))
        #expect(receiving.phase == "Receiving objects")
        #expect(receiving.percent == 45)
        #expect(receiving.current == 1203)
        #expect(receiving.total == 2670)
        #expect(receiving.detail == "1.20 MiB | 2.30 MiB/s")
        #expect(!receiving.done)
        let done = try #require(ProgressParser.parse("Resolving deltas: 100% (812/812), done."))
        #expect(done.done)
        #expect(done.fraction == 1)
        let remote = try #require(ProgressParser.parse("remote: Counting objects: 100% (12/12), done."))
        #expect(remote.phase == "Counting objects")
        let enumerate = try #require(ProgressParser.parse("remote: Enumerating objects: 2670, done."))
        #expect(enumerate.current == 2670)
        #expect(ProgressParser.parse("From file:///tmp/origin") == nil)
    }
}

struct VersionTests {
    @Test func parsesAppleAndHomebrewStrings() {
        #expect(GitVersion(parsing: "git version 2.54.0 (Apple Git-157)") == GitVersion(2, 54, 0))
        #expect(GitVersion(parsing: "git version 2.45.2") == GitVersion(2, 45, 2))
        #expect(GitVersion(parsing: "git version 2.46") == GitVersion(2, 46, 0))
        #expect(GitVersion(parsing: "nonsense") == nil)
        #expect(GitVersion(2, 44, 9) < GitVersion.minimum)
        #expect(GitVersion(2, 54, 0) > GitVersion.minimum)
    }

    @Test func discoversTheInstalledGit() throws {
        let git = try GitExecutable.discover()
        #expect(git.version >= GitVersion.minimum)
        #expect(GitExecutable.candidates.contains(git.path))
    }

    @Test func rejectsAMissingPreferredBinaryAndFallsBack() throws {
        let git = try GitExecutable.discover(preferred: "/nonexistent/git")
        #expect(git.path != "/nonexistent/git")
    }
}
