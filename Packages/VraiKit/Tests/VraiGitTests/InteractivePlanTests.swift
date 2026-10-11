import Foundation
import Testing
@testable import VraiGit

struct InteractivePlanTests {
    static func oid(_ digit: Character) -> OID {
        OID(String(repeating: digit, count: 40))!
    }

    @Test func todoListsEveryStepOldestFirstWithExplicitDrops() {
        let plan = InteractivePlan(steps: [
            RebaseStep(commit: Self.oid("e"), action: .reword, subject: "Docs: add notes", message: "Docs: add the notes\n\nLonger body."),
            RebaseStep(commit: Self.oid("a"), subject: "Graph: assign lane colors"),
            RebaseStep(commit: Self.oid("b"), action: .squash, subject: "Graph: halo\nsecond line"),
            RebaseStep(commit: Self.oid("d"), action: .drop, subject: "Scratch")
        ])
        #expect(plan.todo == """
        reword \(Self.oid("e").rawValue) # Docs: add notes
        pick \(Self.oid("a").rawValue) # Graph: assign lane colors
        squash \(Self.oid("b").rawValue) # Graph: halo second line
        drop \(Self.oid("d").rawValue) # Scratch

        """)
        #expect(plan.problem == nil)
    }

    @Test func messagesAreKeyedByTheStepGitOpensTheEditorFor() {
        let plan = InteractivePlan(steps: [
            RebaseStep(commit: Self.oid("1"), action: .reword, subject: "one", message: "One, reworded"),
            RebaseStep(commit: Self.oid("2"), subject: "two"),
            RebaseStep(commit: Self.oid("3"), action: .squash, subject: "three", message: "Two and three"),
            RebaseStep(commit: Self.oid("4"), action: .fixup, subject: "four"),
            RebaseStep(commit: Self.oid("5"), action: .drop, subject: "five", message: "ignored"),
            RebaseStep(commit: Self.oid("6"), action: .edit, subject: "six"),
            RebaseStep(commit: Self.oid("7"), action: .fixup, subject: "seven", message: "fixups keep the first message"),
            RebaseStep(commit: Self.oid("8"), action: .reword, subject: "eight")
        ])
        #expect(plan.messages == [
            EditorMessage(commit: Self.oid("1").rawValue, message: "One, reworded"),
            EditorMessage(commit: Self.oid("4").rawValue, message: "Two and three")
        ])
    }

    @Test func problemsMatchTheSheet() {
        #expect(InteractivePlan(steps: []).problem == .empty)
        let folded = InteractivePlan(steps: [
            RebaseStep(commit: Self.oid("1"), action: .drop, subject: "one"),
            RebaseStep(commit: Self.oid("2"), action: .fixup, subject: "two")
        ])
        #expect(folded.problem == .startsWithFold)
        #expect(RebaseStep.Action(key: "S") == .squash)
        #expect(RebaseStep.Action.allCases.map(\.key) == ["p", "r", "e", "s", "f", "d"])
    }

    @Test func writesTheTodoAndMessagesFiles() throws {
        let gitDir = TestSandbox.root.appending(path: "scratch/vrai-plan-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: gitDir) }
        let files = InteractivePlan.Files(gitDir: gitDir)
        let plan = InteractivePlan(steps: [RebaseStep(commit: Self.oid("1"), action: .reword, subject: "one", message: "Uno")])
        try plan.write(to: files)
        #expect(try String(contentsOf: files.todo, encoding: .utf8) == plan.todo)
        let decoded = try JSONDecoder().decode([EditorMessage].self, from: Data(contentsOf: files.messages))
        #expect(decoded == plan.messages)
        #expect(files.hasMessages)
        try InteractivePlan(steps: [RebaseStep(commit: Self.oid("1"), subject: "one")]).write(to: files)
        #expect(!files.hasMessages)
        files.clear()
        #expect(!FileManager.default.fileExists(atPath: files.directory.path(percentEncoded: false)))
    }

    @Test func parsesTheLogListing() {
        let a = Self.oid("a").rawValue
        let b = Self.oid("b").rawValue
        let data = Data("\(a)\u{0}Graph: one\u{0}Avery Chen\u{0}\(b)\u{0}Graph: two\u{0}Mira Okafor".utf8)
        let steps = InteractivePlan.parse(data)
        #expect(steps.map(\.subject) == ["Graph: one", "Graph: two"])
        #expect(steps.map(\.author) == ["Avery Chen", "Mira Okafor"])
        #expect(steps.allSatisfy { $0.action == .pick })
        #expect(InteractivePlan.listCommand(onto: "main").display == "git log --reverse --topo-order --no-merges --right-only --cherry-pick -z --format=%H%x00%s%x00%an main...HEAD")
    }

    @Test func editorCommandsAreShellQuoted() {
        let todo = URL(filePath: "/tmp/it's here/todo")
        #expect(EditorHelper.sequenceEditor(helper: "/Apps/Vrai.app/Contents/MacOS/vrai-editor", todo: todo) == "'/Apps/Vrai.app/Contents/MacOS/vrai-editor' --todo '/tmp/it'\\''s here/todo'")
        #expect(EditorHelper.messageEditor(helper: "/x/vrai-editor", messages: URL(filePath: "/m/messages.json")) == "'/x/vrai-editor' --messages '/m/messages.json'")
        var environment = GitEnvironment(base: [EditorHelper.environmentKey: "/usr/bin/true"])
        #expect(EditorHelper.locate(environment: environment) == "/usr/bin/true")
        environment.base[EditorHelper.environmentKey] = "/no/such/helper"
        #expect(EditorHelper.locate(environment: environment) != "/no/such/helper")
    }

    @Test func readsRebaseStateFromGitsFiles() throws {
        let gitDir = TestSandbox.root.appending(path: "scratch/vrai-state-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: gitDir) }
        let folder = gitDir.appending(path: "rebase-merge", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("refs/heads/topic\n".utf8).write(to: folder.appending(path: "head-name"))
        try Data((Self.oid("a").rawValue + "\n").utf8).write(to: folder.appending(path: "orig-head"))
        try Data((Self.oid("c").rawValue + "\n").utf8).write(to: folder.appending(path: "onto"))
        let updates = "refs/heads/stack\n\(Self.oid("b").rawValue)\n\(String(repeating: "0", count: 40))\n"
        try Data(updates.utf8).write(to: folder.appending(path: "update-refs"))
        try Data().write(to: folder.appending(path: "interactive"))
        #expect(OperationInProgress.current(gitDir: gitDir) == .rebase)
        let state = try #require(RebaseState.read(gitDir: gitDir))
        #expect(state.head == "refs/heads/topic")
        #expect(state.refsBefore == ["refs/heads/topic": Self.oid("a"), "refs/heads/stack": Self.oid("b")])
        try Data("detached HEAD\n".utf8).write(to: folder.appending(path: "head-name"))
        let detached = try #require(RebaseState.read(gitDir: gitDir))
        #expect(detached.head == Self.oid("a").rawValue)
        #expect(detached.refsBefore["HEAD"] == Self.oid("a"))
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: gitDir.appending(path: "sequencer"), withIntermediateDirectories: true)
        try Data("revert \(Self.oid("d").rawValue) # Undo\n".utf8).write(to: gitDir.appending(path: "sequencer/todo"))
        #expect(OperationInProgress.current(gitDir: gitDir) == .revert)
        try Data().write(to: gitDir.appending(path: "MERGE_HEAD"))
        #expect(OperationInProgress.current(gitDir: gitDir) == .merge)
    }
}
