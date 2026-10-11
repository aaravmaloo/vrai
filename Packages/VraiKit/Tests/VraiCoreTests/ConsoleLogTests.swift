import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
struct ConsoleLogTests {
    static func entry(_ command: String, source: ConsoleEntry.Source = .vrai, exit: Int32? = 0, background: Bool = false, stdout: String = "", stderr: String = "", accepted: Set<Int32> = [0]) -> ConsoleEntry {
        ConsoleEntry(source: source, command: command, cwd: "/repo", startedAt: Date(), duration: .milliseconds(12), exitCode: exit, stdout: Data(stdout.utf8), stderr: Data(stderr.utf8), background: background, acceptedExitCodes: accepted)
    }

    @Test func observerDeliversEntriesInOrder() async {
        let log = ConsoleLog()
        let observer = log.observer
        for index in 0..<50 { observer(Self.entry("git status \(index)")) }
        log.flush()
        #expect(log.entries.map(\.command) == (0..<50).map { "git status \($0)" })
        observer(Self.entry("git log"))
        for _ in 0..<5 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))
        #expect(log.entries.last?.command == "git log")
    }

    @Test func boundedDropsBackgroundEntriesFirst() {
        let log = ConsoleLog(limit: 5)
        log.append(Self.entry("git push", background: false))
        for index in 0..<10 { log.append(Self.entry("git status \(index)", background: true)) }
        log.append(Self.entry("git commit", background: false))
        #expect(log.entries.count == 5)
        #expect(log.entries.first?.command == "git push")
        #expect(log.entries.last?.command == "git commit")
        for index in 0..<10 { log.append(Self.entry("git tag v\(index)")) }
        #expect(log.entries.count == 5)
        #expect(log.entries.map(\.command) == (5..<10).map { "git tag v\($0)" })
    }

    @Test func failedForegroundEntriesOpenAndCount() {
        let log = ConsoleLog()
        log.append(Self.entry("git push", exit: 1))
        log.append(Self.entry("git fetch", exit: 128, background: true))
        log.append(Self.entry("git diff --no-index -- /dev/null a", exit: 1, accepted: [0, 1]))
        log.append(Self.entry("git status"))
        #expect(log.failures == 1)
        #expect(log.lastFailure == log.entries[0].id)
        #expect(log.isExpanded(log.entries[0].id))
        #expect(!log.isExpanded(log.entries[1].id))
        #expect(log.entries[1].failed)
        #expect(!log.entries[2].failed)
        #expect(!log.isExpanded(log.entries[3].id))
        log.toggle(log.entries[3].id)
        #expect(log.isExpanded(log.entries[3].id))
    }

    @Test func backgroundOutputIsCapped() {
        let log = ConsoleLog()
        let big = String(repeating: "a", count: ConsoleLog.backgroundOutputCap * 2)
        log.append(Self.entry("git status", background: true, stdout: big))
        log.append(Self.entry("git log", background: false, stdout: big))
        #expect(log.entries[0].stdout.utf8.count == ConsoleLog.backgroundOutputCap)
        #expect(log.entries[0].stdoutTruncated)
        #expect(log.entries[1].stdout.utf8.count == big.utf8.count)
        #expect(!log.entries[1].stdoutTruncated)
    }

    @Test func credentialsInURLsAreRedacted() {
        let log = ConsoleLog()
        log.append(Self.entry("git remote add fork https://avery:ghp_secret123@github.com/avery/vrai.git", stderr: "fatal: unable to access 'https://x-access-token:tok3n@github.com/vrai-app/vrai.git/'"))
        #expect(log.entries[0].command == "git remote add fork https://avery:***@github.com/avery/vrai.git")
        #expect(log.entries[0].stderr == "fatal: unable to access 'https://x-access-token:***@github.com/vrai-app/vrai.git/'")
        #expect(ConsoleRedaction.redact("git fetch https://github.com/a/b.git") == "git fetch https://github.com/a/b.git")
        #expect(ConsoleRedaction.redact("git@github.com:a/b.git") == "git@github.com:a/b.git")
    }

    @Test func historyKeepsTypedCommandsWithoutRepeats() {
        let log = ConsoleLog()
        log.remember("git status")
        log.remember("git status")
        log.remember(" git log --oneline ")
        log.remember("")
        #expect(log.history == ["git status", "git log --oneline"])
    }

    @Test func runningCommandsAndClear() {
        let log = ConsoleLog()
        let id = log.begin("git fetch https://a:b@host/x.git")
        #expect(log.running.map(\.command) == ["git fetch https://a:***@host/x.git"])
        log.end(id)
        #expect(log.running.isEmpty)
        log.append(Self.entry("git status", exit: 1))
        log.clear()
        #expect(log.entries.isEmpty)
        #expect(log.expanded.isEmpty)
        #expect(log.failures == 1)
    }

    @Test func outputJoinsStdoutAndStderr() {
        let log = ConsoleLog()
        let entry = Self.entry("git push", stdout: "out\n", stderr: "err\n")
        #expect(log.output(of: entry) == "out\nerr")
        #expect(log.output(of: Self.entry("git push", stderr: "only\n")) == "only")
    }

    @Test func typedCommandsClassifyReadsAndRisk() throws {
        let status = try #require(TypedCommand("status"))
        #expect(status.display == "git status")
        #expect(!status.changesRepository)
        #expect(status.command.access == .read)
        let branchList = try #require(TypedCommand("git branch -a -vv"))
        #expect(!branchList.changesRepository)
        let branchMake = try #require(TypedCommand("git branch topic"))
        #expect(branchMake.changesRepository)
        #expect(TypedCommand("git reset --hard HEAD~1")?.risk == .destructive)
        #expect(TypedCommand("git push --force-with-lease")?.risk == .rewrites)
        #expect(TypedCommand("git rebase -i main")?.interactiveRebaseTarget == "main")
        #expect(TypedCommand("git commit")?.opensEditor == true)
        #expect(TypedCommand("git commit -m \"x\"")?.opensEditor == false)
        #expect(TypedCommand("git commit --amend --no-edit")?.opensEditor == false)
        #expect(TypedCommand("git stash list")?.changesRepository == false)
        #expect(TypedCommand("git stash")?.changesRepository == true)
        #expect(TypedCommand("git config --get user.name")?.changesRepository == false)
        #expect(TypedCommand("git config user.name Avery")?.changesRepository == true)
        let quoted = try #require(TypedCommand("commit -m \"two words\""))
        #expect(quoted.command.arguments == ["commit", "-m", "two words"])
        #expect(quoted.display == "git commit -m \"two words\"")
    }

    @Test func grepParsesNulSeparatedMatches() {
        let data = Data("Sources/A.swift\u{0}12\u{0}let lane = 1\nREADME.md\u{0}3\u{0}Lane colors\n".utf8)
        let matches = GrepMatch.parse(data)
        #expect(matches == [GrepMatch(path: "Sources/A.swift", line: 12, text: "let lane = 1"), GrepMatch(path: "README.md", line: 3, text: "Lane colors")])
        let atRevision = GrepMatch.parse(Data("main:README.md\u{0}3\u{0}Lane\n".utf8), revision: "main")
        #expect(atRevision.first?.path == "README.md")
        #expect(GrepMatch.parse(data, limit: 1).count == 1)
    }
}
