import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

struct CoverageRow: Sendable, Hashable {
    var section: String
    var commands: [String]
    var home: String
    var detail: String

    var text: String { home + " " + detail }
}

enum CoverageTable {
    static let skippedSections: Set<String> = ["Files and syntax"]

    static let appendixD: Set<String> = [
        "fast-export", "fast-import", "filter-branch", "gitweb", "instaweb", "show-branch",
        "archimport", "cvsexportcommit", "cvsimport", "cvsserver", "p4", "quiltimport", "svn"
    ]

    static let owners: [String: String] = [
        "annotate": "H (places: blame)",
        "replace": "H (places: refs)",
        "grep": "I (palette: search code)",
        "notes": "I (console and expert: notes)",
        "range-diff": "I (console and expert: compare with before)",
        "difftool": "K (settings: tools)",
        "rerere": "K (settings: git)",
        "version": "K (settings: git)",
        "credential-cache": "K (settings: accounts)",
        "credential-store": "K (settings: accounts)",
        "maintenance": "K (settings: background maintenance, Run now)",
        "for-each-repo": "K (settings: background maintenance)",
        "hook": "K (settings: repository hooks)",
        "refs": "H (places: refs)",
        "pack-objects": "nobody: repack runs it, nothing calls it directly",
        "fmt-merge-msg": "coordinator (merge message, M5)",
        "stripspace": "coordinator (commit message cleanup, M4)",
        "interpret-trailers": "coordinator (trailers, M4)",
        "merge-index": "coordinator (reset a conflict, M5)",
        "merge-one-file": "coordinator (reset a conflict, M5)",
        "pack-redundant": "nobody: git nominates it for removal",
        "unpack-objects": "nobody: Maintenance has no use for it"
    ]

    static func load() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "git-coverage", withExtension: "md", subdirectory: "Resources"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func rows(_ text: String) -> [CoverageRow] {
        var out: [CoverageRow] = []
        var section = ""
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                section = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard !skippedSections.contains(section), line.hasPrefix("| `") else { continue }
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 3 else { continue }
            let commands = cells[1].matches(of: /`([^`]+)`/).map { String($0.output.1) }
            out.append(CoverageRow(section: section, commands: commands, home: cells[2], detail: cells.count > 3 ? cells[3] : ""))
        }
        return out
    }

    static func isConsoleOnly(_ row: CoverageRow, command: String) -> Bool {
        if appendixD.contains(command) { return true }
        if row.home.hasPrefix("Console") { return true }
        return row.text.localizedCaseInsensitiveContains("console only")
    }

    static func isReplaced(_ row: CoverageRow) -> Bool {
        row.text.contains("replaces it") || row.text.contains("deprecates")
    }

    static func uncovered(_ rows: [CoverageRow], samples: [GitCommand]) -> [String] {
        let produced = Set(samples.compactMap(\.subcommand))
        var missing: [String] = []
        for row in rows where !isReplaced(row) {
            for command in row.commands where !isConsoleOnly(row, command: command) && !produced.contains(command) && !missing.contains(command) {
                missing.append(command)
            }
        }
        return missing
    }

    static func report(_ missing: [String]) -> String {
        missing.map { "git \($0): no GitCommand produces it; owner \(owners[$0] ?? "J (long tail)")" }.joined(separator: "\n")
    }
}

@MainActor
struct CoverageTests {
    @Test func theTableParses() throws {
        let rows = CoverageTable.rows(try CoverageTable.load())
        let commands = rows.flatMap(\.commands)
        #expect(rows.count > 90)
        #expect(commands.contains("add"))
        #expect(commands.contains("update-index"))
        #expect(commands.contains("credential-store"))
        #expect(!commands.contains(".gitignore"))
        let svn = try #require(rows.first { $0.commands.contains("svn") })
        #expect(CoverageTable.isConsoleOnly(svn, command: "svn"))
        let gitk = try #require(rows.first { $0.commands.contains("gitk") })
        #expect(CoverageTable.isReplaced(gitk))
        let server = try #require(rows.first { $0.commands.contains("daemon") })
        #expect(CoverageTable.isConsoleOnly(server, command: "daemon"))
    }

    @Test func everySampleIsAGitSubcommand() {
        let samples = CoverageSamples.all
        #expect(!samples.isEmpty)
        let unnamed = samples.filter { $0.subcommand == nil }.map(\.display)
        #expect(unnamed.isEmpty, "commands without a subcommand: \(unnamed)")
    }

    @Test func longTailRowsHaveAHome() throws {
        let rows = CoverageTable.rows(try CoverageTable.load())
        let missing = CoverageTable.uncovered(rows, samples: CoverageSamples.all).filter { CoverageTable.owners[$0] == nil }
        #expect(missing.isEmpty, Comment(rawValue: CoverageTable.report(missing)))
    }

    @Test func everyCommandHasAHome() throws {
        let rows = CoverageTable.rows(try CoverageTable.load())
        let missing = CoverageTable.uncovered(rows, samples: CoverageSamples.all)
        #expect(missing.isEmpty, Comment(rawValue: "\(missing.count) commands in git-coverage.md have no home yet:\n" + CoverageTable.report(missing)))
    }
}
