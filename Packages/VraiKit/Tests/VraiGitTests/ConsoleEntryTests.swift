import Foundation
import Testing
@testable import VraiGit

struct ConsoleEntryTests {
    @Test func acceptedExitCodesAreNotFailures() async throws {
        let dir = try GitProcessTests.scratchRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = EntryLog()
        let git = try GitProcessTests.process(at: dir, log: log)
        try Data("a\n".utf8).write(to: dir.appending(path: "a.txt"))
        try Data("b\n".utf8).write(to: dir.appending(path: "b.txt"))
        let accepted = try await git.run(.read(["diff", "--no-index", "--", "a.txt", "b.txt"], acceptedExitCodes: [0, 1]))
        #expect(accepted.exitCode == 1)
        let strict = try await git.runAllowingFailure(.read(["diff", "--no-index", "--", "a.txt", "b.txt"]))
        #expect(strict.exitCode == 1)
        let entries = log.all
        #expect(entries.count == 2)
        #expect(entries[0].acceptedExitCodes == [0, 1])
        #expect(!entries[0].failed)
        #expect(entries[1].failed)
        #expect(entries[0].command == "git diff --no-index -- a.txt b.txt")
    }

    @Test func streamedEntriesCarryAcceptedExitCodes() async throws {
        let dir = try GitProcessTests.scratchRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = EntryLog()
        let git = try GitProcessTests.process(at: dir, log: log)
        try Data("a\n".utf8).write(to: dir.appending(path: "a.txt"))
        try Data("b\n".utf8).write(to: dir.appending(path: "b.txt"))
        var received = Data()
        for try await chunk in git.stream(.read(["diff", "--no-index", "--", "a.txt", "b.txt"], acceptedExitCodes: [0, 1])) { received.append(chunk) }
        #expect(!received.isEmpty)
        #expect(log.all.first?.failed == false)
        #expect(log.all.first?.background == true)
    }
}
