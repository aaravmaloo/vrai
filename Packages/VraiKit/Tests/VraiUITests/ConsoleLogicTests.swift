import Foundation
import Testing
import VraiGit
@testable import VraiUI

struct ConsoleLogicTests {
    static func entry(_ command: String, background: Bool, exit: Int32 = 0, output: String = "") -> ConsoleEntry {
        ConsoleEntry(source: background ? .vrai : .you, command: command, cwd: "/repo", startedAt: Date(timeIntervalSince1970: 1_791_720_000), duration: .milliseconds(12), exitCode: exit, stdout: Data(output.utf8), stderr: Data(), background: background)
    }

    static let entries: [ConsoleEntry] = [
        entry("git status --porcelain=v2", background: true),
        entry("git for-each-ref", background: true),
        entry("git fetch --prune origin", background: false, output: "From github.com:vrai/vrai"),
        entry("git rev-list --count main..origin/main", background: true),
        entry("git log -n 1", background: true, exit: 128),
        entry("git status --porcelain=v2", background: true),
        entry("git push origin main", background: false, exit: 1, output: "rejected")
    ]

    static func kinds(_ lines: [ConsoleLine]) -> [String] {
        lines.map { line in
            switch line {
            case .entry(let entry, let quiet): (quiet ? "quiet:" : "entry:") + entry.command
            case .group(_, let items): "group:\(items.count)"
            }
        }
    }

    @Test func consecutiveBackgroundReadsFoldIntoOneRowUnderAll() {
        let lines = ConsoleLine.build(Self.entries, filter: .all, needle: "") { $0.stdout }
        #expect(Self.kinds(lines) == [
            "group:2",
            "entry:git fetch --prune origin",
            "quiet:git rev-list --count main..origin/main",
            "quiet:git log -n 1",
            "quiet:git status --porcelain=v2",
            "entry:git push origin main"
        ])
    }

    @Test func failedAndBackgroundFiltersListEntriesOneByOne() {
        let failed = ConsoleLine.build(Self.entries, filter: .failed, needle: "") { $0.stdout }
        #expect(Self.kinds(failed) == ["quiet:git log -n 1", "entry:git push origin main"])
        let background = ConsoleLine.build(Self.entries, filter: .background, needle: "") { $0.stdout }
        #expect(background.count == 5)
        #expect(background.allSatisfy { if case .entry = $0 { true } else { false } })
    }

    @Test func theFilterMatchesCommandsAndOutput() {
        let byCommand = ConsoleLine.build(Self.entries, filter: .all, needle: "PORCELAIN") { $0.stdout }
        #expect(byCommand.count == 2)
        let byOutput = ConsoleLine.build(Self.entries, filter: .all, needle: "rejected") { $0.stdout }
        #expect(Self.kinds(byOutput) == ["entry:git push origin main"])
        let none = ConsoleLine.build(Self.entries, filter: .failed, needle: "fetch") { $0.stdout }
        #expect(none.isEmpty)
    }
}
