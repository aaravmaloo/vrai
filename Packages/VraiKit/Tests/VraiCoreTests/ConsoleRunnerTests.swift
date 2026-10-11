import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct ConsoleRunnerTests {
    @Test func readOnlyTypedCommandLogsAsYouWithoutRefreshing() async throws {
        let fixture = try await ConsoleFixture.make()
        defer { fixture.remove() }
        try fixture.recorder.reset()
        let run = try await fixture.store.run(typed: "log --oneline -2")
        #expect(run.succeeded)
        #expect(run.typed.display == "git log --oneline -2")
        let calls = try fixture.recorder.commandCalls()
        #expect(calls == [["log", "--oneline", "-2"]])
        let entryID = try #require(run.entryID)
        let entry = try #require(fixture.console.entry(id: entryID))
        #expect(entry.source == .you)
        #expect(!entry.background)
        #expect(entry.stdout.split(separator: "\n").count == 2)
        #expect(fixture.console.isExpanded(entry.id))
        #expect(fixture.console.history.last == "git log --oneline -2")
        #expect(fixture.console.running.isEmpty)
    }

    @Test func typedCommandThatChangesTheRepositoryRefreshesTheSnapshot() async throws {
        let fixture = try await ConsoleFixture.make()
        defer { fixture.remove() }
        #expect(fixture.store.snapshot?.branches.contains { $0.name == "typed/topic" } == false)
        let run = try await fixture.store.run(typed: "git branch typed/topic main")
        #expect(run.succeeded)
        #expect(try await fixture.copy.tip("refs/heads/typed/topic") == fixture.copy.tip("refs/heads/main"))
        #expect(fixture.store.snapshot?.branches.contains { $0.name == "typed/topic" } == true)
        let switched = try await fixture.store.run(typed: "switch -c typed/second")
        #expect(switched.succeeded)
        #expect(fixture.store.snapshot?.head == .branch("typed/second"))
        #expect(fixture.store.snapshot?.currentBranch?.name == "typed/second")
    }

    @Test func failingTypedCommandKeepsItsOutputAndDoesNotThrow() async throws {
        let fixture = try await ConsoleFixture.make()
        defer { fixture.remove() }
        let run = try await fixture.store.run(typed: "git switch no-such-branch")
        #expect(!run.succeeded)
        let entryID = try #require(run.entryID)
        let entry = try #require(fixture.console.entry(id: entryID))
        #expect(entry.failed)
        #expect(entry.exitCode == 128)
        #expect(entry.stderr.contains("no-such-branch"))
        #expect(fixture.console.isExpanded(entry.id))
        #expect(fixture.console.failures >= 1)
    }

    @Test func quotedArgumentsReachGitWhole() async throws {
        let fixture = try await ConsoleFixture.make()
        defer { fixture.remove() }
        let run = try await fixture.store.run(typed: "git commit --allow-empty --no-gpg-sign -m \"Typed in the console\"")
        #expect(run.succeeded)
        #expect(try await fixture.copy.git(["log", "-1", "--format=%s"]) == "Typed in the console")
        let head = try await fixture.copy.tip("HEAD")
        #expect(fixture.store.snapshot?.headOID?.rawValue == head)
    }

    @Test func largeOutputSpillsToAFile() async throws {
        let fixture = try await ConsoleFixture.make()
        defer { fixture.remove() }
        let big = String(repeating: "line of output for the console\n", count: 40_000)
        try Data(big.utf8).write(to: fixture.repository.appending(path: "big.txt"))
        let blob = try await fixture.copy.git(["hash-object", "-w", "--", "big.txt"])
        let run = try await fixture.store.run(typed: "git cat-file -p \(blob)")
        let url = try #require(run.fullOutput)
        #expect(url.path(percentEncoded: false).hasPrefix(fixture.copy.root.deletingLastPathComponent().path(percentEncoded: false)))
        let written = try Data(contentsOf: url)
        #expect(written.count > ConsoleEntry.outputCap)
        let entryID = try #require(run.entryID)
        let entry = try #require(fixture.console.entry(id: entryID))
        #expect(entry.stdoutTruncated)
        #expect(!entry.failed)
        #expect(fixture.console.spilled[entry.id] == url)
    }

    @Test func showObjectAndNotes() async throws {
        let fixture = try await ConsoleFixture.make()
        defer { fixture.remove() }
        let head = try #require(fixture.store.snapshot?.headOID)
        let shown = try await fixture.store.showObject(id: head)
        #expect(shown.output.hasPrefix("tree "))
        let entry = try #require(fixture.console.entry(for: shown))
        #expect(entry.command == "git cat-file -p \(head.rawValue)")
        #expect(entry.source == .vrai)
        #expect(fixture.console.isExpanded(entry.id))
        #expect(await fixture.store.note(id: head) == nil)
        try await fixture.store.addNote(id: head, message: "  First look  ")
        #expect(await fixture.store.note(id: head) == "First look")
        await #expect(throws: GitError.self) { try await fixture.store.addNote(id: head, message: "Second look") }
        try await fixture.store.addNote(id: head, message: "Second look", replacing: true)
        #expect(await fixture.store.note(id: head) == "Second look")
        #expect(try await fixture.copy.git(["notes", "show", head.rawValue]) == "Second look")
        try await fixture.store.removeNote(id: head)
        #expect(await fixture.store.note(id: head) == nil)
        await #expect(throws: GitError.self) { try await fixture.store.addNote(id: head, message: "   ") }
    }
}
