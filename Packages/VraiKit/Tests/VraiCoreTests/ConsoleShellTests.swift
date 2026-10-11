import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct ConsoleShellTests {
    @Test func typedSemicolonIsAnArgumentNotAShellSeparator() async throws {
        let fixture = try await ConsoleFixture.make()
        defer { fixture.remove() }
        let victim = fixture.repository.appending(path: "x", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: victim, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: victim.appending(path: "keep.txt"))
        try fixture.recorder.reset()

        let run = try await fixture.store.run(typed: "git log; rm -rf x")

        let calls = try fixture.recorder.calls()
        let typed = calls.filter { $0.contains("log;") }
        #expect(typed == [GitProcess.implicitArguments + ["log;", "rm", "-rf", "x"]])
        #expect(!calls.contains { $0.first == "rm" || $0.contains("rm -rf x") })
        #expect(FileManager.default.fileExists(atPath: victim.appending(path: "keep.txt").path(percentEncoded: false)))
        #expect(run.result.exitCode != 0)
        #expect(run.result.errorOutput.contains("'log;' is not a git command"))
        #expect(run.result.command.arguments == ["log;", "rm", "-rf", "x"])
        let entryID = try #require(run.entryID)
        let entry = try #require(fixture.console.entry(id: entryID))
        #expect(entry.command == "git log; rm -rf x")
        #expect(entry.source == .you)
        #expect(entry.failed)
        #expect(fixture.console.isExpanded(entry.id))
    }

    @Test func otherShellSyntaxStaysLiteral() async throws {
        let fixture = try await ConsoleFixture.make()
        defer { fixture.remove() }
        let marker = fixture.repository.appending(path: "pwned")
        try fixture.recorder.reset()
        let texts = [
            "log -1 --format=%s && touch pwned",
            "log -1 --format=%s | touch pwned",
            "log -1 --format=%s `touch pwned`",
            "log -1 --format=%s $(touch pwned)",
            "log -1 --format=%s > pwned",
            "log -1 \"--format=%s; touch pwned\""
        ]
        for text in texts {
            _ = try await fixture.store.run(typed: text)
        }
        #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
        let calls = try fixture.recorder.commandCalls().filter { $0.first == "log" }
        #expect(calls.contains(["log", "-1", "--format=%s", "&&", "touch", "pwned"]))
        #expect(calls.contains(["log", "-1", "--format=%s", "|", "touch", "pwned"]))
        #expect(calls.contains(["log", "-1", "--format=%s", "`touch", "pwned`"]))
        #expect(calls.contains(["log", "-1", "--format=%s", "$(touch", "pwned)"]))
        #expect(calls.contains(["log", "-1", "--format=%s", ">", "pwned"]))
        #expect(calls.contains(["log", "-1", "--format=%s; touch pwned"]))
    }

    @Test func leadingGlobalOptionsAreRefused() async throws {
        #expect(TypedCommand.problem("git -c core.fsmonitor=touch status") == .globalOptions)
        #expect(TypedCommand.problem("-C / clean -fdx") == .globalOptions)
        #expect(TypedCommand.problem("git --git-dir=/tmp log") == .globalOptions)
        #expect(TypedCommand.problem("   ") == .empty)
        #expect(TypedCommand.problem("git --version") == nil)
        #expect(TypedCommand("git -c a=b status") == nil)
        let fixture = try await ConsoleFixture.make()
        defer { fixture.remove() }
        try fixture.recorder.reset()
        await #expect(throws: GitError.self) { _ = try await fixture.store.run(typed: "-c core.fsmonitor=touch status") }
        #expect(try fixture.recorder.calls().isEmpty)
    }
}
