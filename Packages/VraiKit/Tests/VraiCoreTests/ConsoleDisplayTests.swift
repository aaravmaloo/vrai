import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct ConsoleDisplayTests {
    @Test func everyEntryMatchesTheDisplayOfTheCommandThatRan() async throws {
        let fixture = try await ConsoleFixture.make()
        defer { fixture.remove() }
        let store = fixture.store
        await store.open(watch: false)
        try Data("Notes from the console test\n".utf8).write(to: fixture.repository.appending(path: "Console notes.md"))
        try await store.stage(paths: ["Console notes.md"])
        try await store.unstage(paths: ["Console notes.md"])
        try await store.stage(paths: ["Console notes.md"])
        let commit = try await store.commit(subject: "Console: log \"every\" command", body: "Two words\nand a second line")
        _ = try await store.createBranch(name: "console/check", switchTo: false)
        _ = try await store.createTag(name: "console-tag", target: commit.rawValue, message: "A tag with spaces")
        _ = try await store.deleteBranch(name: "console/check")
        try Data("A changed readme\n".utf8).write(to: fixture.repository.appending(path: "README.md"))
        try await store.stash(message: "keep it 'safe'", includeUntracked: true)
        try await store.applyStash(index: 0, pop: true)
        _ = try await store.fetch(remote: "origin")
        _ = try await store.showObject(id: commit)
        try await store.addNote(id: commit, message: "Reviewed in the console")
        _ = try await store.trackedFiles()
        _ = try await store.grep(text: "lane")
        _ = try await store.searchCommits("graph")
        _ = await store.recentBranches()
        _ = try await store.run(typed: "log --oneline -3")
        _ = try await store.run(typed: "git commit --allow-empty -m \"typed message\" --no-gpg-sign")
        _ = try await store.run(typed: "show 'HEAD' --stat")
        try await store.refresh()
        await fixture.settle()

        let entries = fixture.console.entries
        let calls = try fixture.recorder.commandCalls()
        #expect(entries.count == calls.count, "\(ConsoleFixture.difference(entries: entries, calls: calls))")
        #expect(entries.count > 40)

        var expected: [String: Int] = [:]
        for call in calls { expected[ConsoleFixture.rendered(call), default: 0] += 1 }
        var logged: [String: Int] = [:]
        for entry in entries {
            switch entry.source {
            case .vrai:
                logged[entry.command, default: 0] += 1
            case .you:
                let parsed = try #require(CommandParser.parse(entry.command))
                logged[ConsoleFixture.rendered(parsed.arguments), default: 0] += 1
            }
        }
        #expect(logged == expected, "\(ConsoleFixture.difference(entries: entries, calls: calls))")

        let typed = entries.filter { $0.source == .you }.map(\.command)
        #expect(typed == ["git log --oneline -3", "git commit --allow-empty -m \"typed message\" --no-gpg-sign", "git show 'HEAD' --stat"])
        #expect(entries.contains { $0.command == "git commit -F - --no-gpg-sign" || $0.command.hasPrefix("git commit -F -") })
        #expect(entries.contains { $0.command == "git stash push -m \"keep it 'safe'\" -u" || $0.command.hasPrefix("git stash push") })
        #expect(entries.contains { $0.command == "git notes add -m \"Reviewed in the console\" \(commit.rawValue)" })
        #expect(entries.contains { $0.command == "git cat-file -p \(commit.rawValue)" })
    }

    @Test func aButtonThatRunsSeveralCommandsShowsEachOne() async throws {
        let fixture = try await ConsoleFixture.make()
        defer { fixture.remove() }
        _ = try await fixture.store.createBranch(name: "console/published", from: "main", switchTo: false, publish: true)
        await fixture.settle()
        try fixture.recorder.reset()
        let before = fixture.console.entries.count
        _ = try await fixture.store.deleteBranch(name: "console/published", alsoOnRemote: true)
        await fixture.settle()
        let fresh = Array(fixture.console.entries.dropFirst(before))
        let calls = try fixture.recorder.commandCalls()
        #expect(fresh.count == calls.count, "\(ConsoleFixture.difference(entries: fresh, calls: calls))")
        let foreground = fresh.filter { !$0.background }.map(\.command)
        #expect(foreground.contains("git branch -d console/published"))
        #expect(foreground.contains { $0.hasPrefix("git push") && $0.contains("--delete") && $0.contains("console/published") })
        #expect(foreground.count >= 2)
    }
}
