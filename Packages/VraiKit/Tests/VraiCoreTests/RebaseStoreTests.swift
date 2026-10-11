import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct RebaseStoreTests {
    static let branch = "refs/heads/feature/graph-renderer"
    static let subjects = [
        "Graph: draw merge curves with cubic béziers",
        "Graph: keep the HEAD halo above merge rings",
        "Graph: assign lane colors from branch tips"
    ]

    func subjects(_ scratch: Scratch, _ range: String) async throws -> [String] {
        try await scratch.git(["log", "--format=%s", range]).split(separator: "\n").map(String.init)
    }

    func commit(_ scratch: Scratch, file: String, contents: String, subject: String) async throws {
        try Data(contents.utf8).write(to: scratch.repository.appending(path: file))
        try await scratch.git(["add", "--", file])
        try await scratch.git(["commit", "-q", "-m", subject])
    }

    func rebaseStopReason(_ store: RepositoryStore) -> RepoState.StopReason? {
        if case .rebasing(_, _, _, let reason, _, _) = store.snapshot?.state { return reason }
        return nil
    }

    @Test func rebaseReplaysAndMovesStackedBranches() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        try await scratch.clean()
        try await scratch.git(["branch", "stack", "HEAD~1"])
        let tip = try await scratch.oid("HEAD")
        let stack = try await scratch.oid("stack")
        let store = try scratch.store()
        let outcome = try await store.rebase(onto: "origin/main", updateRefs: true)
        #expect(outcome == .rebased(commits: 3))
        #expect(try await scratch.oid("HEAD~3") == (try await scratch.oid("origin/main")))
        #expect(try await subjects(scratch, "origin/main..HEAD") == Self.subjects)
        #expect(try await scratch.oid("stack") == (try await scratch.oid("HEAD~1")))
        #expect(scratch.log.commands.contains("git rebase --update-refs origin/main"))
        let entry = try #require(await store.recorded.first)
        #expect(entry.kind == .rebase)
        #expect(entry.head == Self.branch)
        #expect(entry.refsBefore == [Self.branch: tip, "refs/heads/stack": stack])
        #expect(entry.label == "Rebased feature/graph-renderer onto origin/main")

        #expect(try await store.rebase(onto: "origin/main") == .upToDate)
        #expect(await store.recorded.count == 1)
    }

    @Test func rebaseCarriesUncommittedChangesWithAutostash() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        let tip = try await scratch.oid("HEAD")
        let store = try scratch.store()
        let refused = await #expect(throws: GitError.self) { try await store.rebase(onto: "origin/main") }
        #expect(refused?.code.name == "localChangesWouldBeOverwritten")
        #expect(try await scratch.oid("HEAD") == tip)
        try await store.rebase(onto: "origin/main", autostash: true)
        #expect(try await scratch.oid("HEAD~3") == (try await scratch.oid("origin/main")))
        let status = try await scratch.git(["status", "--porcelain"])
        #expect(status.contains("Sources/VraiGit/Graph/LaneLayout.swift"))
        #expect(status.contains("Notes/"))
        #expect(await store.recorded.first?.refsBefore == [Self.branch: tip])
    }

    @Test func backgroundRebaseUsesReplayAndLeavesTheWorkingTreeAlone() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        try await scratch.git(["branch", "stack", "HEAD~1"])
        let tip = try await scratch.oid("HEAD")
        let stack = try await scratch.oid("stack")
        let status = try await scratch.git(["status", "--porcelain"])
        let store = try scratch.store()
        let outcome = try await store.rebase(onto: "origin/main", updateRefs: true, inBackground: true)
        #expect(outcome == .rebased(commits: 3))
        #expect(try await scratch.oid("HEAD~3") == (try await scratch.oid("origin/main")))
        #expect(try await subjects(scratch, "origin/main..HEAD") == Self.subjects)
        #expect(try await scratch.oid("stack") == (try await scratch.oid("HEAD~1")))
        #expect(try await scratch.git(["status", "--porcelain"]) == status)
        #expect(try await scratch.git(["symbolic-ref", "HEAD"]) == Self.branch)
        let commands = scratch.log.commands
        #expect(commands.contains("git replay --contained --ref-action=print --onto origin/main origin/main..feature/graph-renderer"))
        #expect(commands.contains("git update-ref -m \"rebase (replay): onto origin/main\" --stdin"))
        #expect(!commands.contains { $0.hasPrefix("git rebase") })
        let entry = try #require(await store.recorded.first)
        #expect(entry.kind == .rebase)
        #expect(entry.refsBefore == [Self.branch: tip, "refs/heads/stack": stack])
    }

    @Test func backgroundRebaseStopsOnConflictsWithoutChangingAnything() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        try await scratch.clean()
        try await scratch.git(["switch", "-q", "-c", "clash", "main"])
        try await commit(scratch, file: "Sources/VraiGit/Graph/LaneLayout.swift", contents: "struct LaneLayout {}\n", subject: "Clash with the lane layout")
        try await scratch.git(["switch", "-q", "feature/graph-renderer"])
        let tip = try await scratch.oid("HEAD")
        let store = try scratch.store()
        let error = await #expect(throws: GitError.self) { try await store.rebase(onto: "clash", inBackground: true) }
        #expect(error?.code.name == "conflicts")
        #expect(try await scratch.oid("HEAD") == tip)
        #expect(OperationInProgress.current(gitDir: try await scratch.gitDir()) == nil)
        #expect(await store.recorded.isEmpty)

        let stopped = await #expect(throws: GitError.self) { try await store.rebase(onto: "clash") }
        #expect(stopped?.code == .conflicts(paths: ["Sources/VraiGit/Graph/LaneLayout.swift"]))
        #expect(rebaseStopReason(store) == .conflict)
        let early = await #expect(throws: GitError.self) { try await store.continueOperation() }
        #expect(early?.code == .unresolvedConflicts)
        try await store.abort()
        #expect(try await scratch.oid("HEAD") == tip)
        #expect(try await scratch.git(["symbolic-ref", "HEAD"]) == Self.branch)
        #expect(OperationInProgress.current(gitDir: try await scratch.gitDir()) == nil)
        #expect(await store.recorded.isEmpty)
    }

    @Test func interactiveRebaseReordersRewordsSquashesAndDropsInOnePlan() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        try await scratch.clean()
        try await commit(scratch, file: "scratch.txt", contents: "throwaway\n", subject: "Scratch: try a throwaway idea")
        try await commit(scratch, file: "NOTES.md", contents: "# Notes\n", subject: "Docs: add notes")
        let a = try await scratch.oid("HEAD~4")
        let b = try await scratch.oid("HEAD~3")
        let c = try await scratch.oid("HEAD~2")
        let d = try await scratch.oid("HEAD~1")
        let e = try await scratch.oid("HEAD")
        let store = try scratch.store()
        let planned = try await store.rebasePlan(onto: "main")
        #expect(planned.map(\.commit) == [a, b, c, d, e])
        var folded = planned
        folded[0].action = .fixup
        let refused = await #expect(throws: GitError.self) { try await store.interactiveRebase(onto: "main", plan: folded) }
        #expect(refused?.code.name == "unknown")
        #expect(OperationInProgress.current(gitDir: try await scratch.gitDir()) == nil)
        #expect(try await scratch.oid("HEAD") == e)
        #expect(planned.map(\.subject) == Self.subjects.reversed() + ["Scratch: try a throwaway idea", "Docs: add notes"])

        let reworded = "Docs: write down the notes\n\nMoved first during the interactive rebase."
        let plan = [
            RebaseStep(commit: e, action: .reword, subject: planned[4].subject, message: reworded),
            planned[0],
            planned[1],
            RebaseStep(commit: c, action: .squash, subject: planned[2].subject, message: "Graph: halo above the rings, cubic curves"),
            RebaseStep(commit: d, action: .drop, subject: planned[3].subject)
        ]
        let outcome = try await store.interactiveRebase(onto: "main", plan: plan)
        #expect(outcome == .rebased(commits: 4))
        #expect(try await subjects(scratch, "main..HEAD") == [
            "Graph: halo above the rings, cubic curves",
            "Graph: assign lane colors from branch tips",
            "Docs: write down the notes"
        ])
        #expect(try await scratch.git(["log", "-1", "--format=%B", "HEAD~2"]) == reworded)
        #expect(try await scratch.git(["diff", "--name-only", c.rawValue, "HEAD"]) == "NOTES.md")
        #expect(!scratch.exists("scratch.txt"))
        #expect(scratch.log.commands.contains("git rebase -i main"))
        #expect(!FileManager.default.fileExists(atPath: InteractivePlan.Files(gitDir: try await scratch.gitDir()).directory.path(percentEncoded: false)))
        let entry = try #require(await store.recorded.first)
        #expect(entry.kind == .rebase)
        #expect(entry.head == Self.branch)
        #expect(entry.refsBefore == [Self.branch: e])
        #expect(entry.label == "Rebased feature/graph-renderer interactively")
    }

    @Test func interactiveRebaseStopsForEditAndKeepsItsMessagesForContinue() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        try await scratch.clean()
        let tip = try await scratch.oid("HEAD")
        let store = try scratch.store()
        var plan = try await store.rebasePlan(onto: "main")
        plan[0].action = .edit
        plan[1].action = .reword
        plan[1].message = "Graph: the halo stays above the rings"
        let error = await #expect(throws: GitError.self) { try await store.interactiveRebase(onto: "main", plan: plan) }
        #expect(error?.code == .stoppedForEdit)
        #expect(rebaseStopReason(store) == .edit)
        let files = InteractivePlan.Files(gitDir: try await scratch.gitDir())
        #expect(files.hasMessages)
        #expect(await store.recorded.isEmpty)

        try await store.continueOperation()
        #expect(try await subjects(scratch, "main..HEAD") == [
            "Graph: draw merge curves with cubic béziers",
            "Graph: the halo stays above the rings",
            "Graph: assign lane colors from branch tips"
        ])
        #expect(!files.hasMessages)
        #expect(store.snapshot?.state == .clean)
        let entry = try #require(await store.recorded.first)
        #expect(entry.kind == .rebase)
        #expect(entry.head == Self.branch)
        #expect(entry.refsBefore == [Self.branch: tip])
    }

    @Test func rebaseFixtureContinuesFromTheEditStop() async throws {
        let scratch = try await Scratch.copy("rebase")
        defer { scratch.remove() }
        let gitDir = try await scratch.gitDir()
        let origHead = try #require(OID(try String(contentsOf: gitDir.appending(path: "rebase-merge/orig-head"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        let store = try scratch.store()
        try await store.refresh()
        #expect(rebaseStopReason(store) == .edit)
        try await store.continueOperation()
        #expect(OperationInProgress.current(gitDir: gitDir) == nil)
        #expect(store.snapshot?.state == .clean)
        #expect(try await scratch.git(["symbolic-ref", "HEAD"]) == Self.branch)
        #expect(try await scratch.oid("HEAD~3") == (try await scratch.oid("origin/main")))
        #expect(try await subjects(scratch, "origin/main..HEAD") == Self.subjects)
        #expect(try await scratch.git(["status", "--porcelain"]).contains("Sources/VraiGit/Graph/LaneLayout.swift"))
        #expect(scratch.log.commands.contains("git rebase --continue"))
        let entry = try #require(await store.recorded.first)
        #expect(entry.kind == .rebase)
        #expect(entry.head == Self.branch)
        #expect(entry.refsBefore == [Self.branch: origHead])
    }

    @Test func rebaseFixtureSkipsTheEditStop() async throws {
        let scratch = try await Scratch.copy("rebase")
        defer { scratch.remove() }
        let gitDir = try await scratch.gitDir()
        let origHead = try #require(OID(try String(contentsOf: gitDir.appending(path: "rebase-merge/orig-head"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        let store = try scratch.store()
        try await store.skipStep()
        #expect(OperationInProgress.current(gitDir: gitDir) == nil)
        #expect(try await scratch.git(["symbolic-ref", "HEAD"]) == Self.branch)
        #expect(try await scratch.oid("HEAD~3") == (try await scratch.oid("origin/main")))
        #expect(scratch.log.commands.contains("git rebase --skip"))
        let entry = try #require(await store.recorded.first)
        #expect(entry.kind == .rebase)
        #expect(entry.refsBefore == [Self.branch: origHead])
    }

    @Test func rebaseFixtureAborts() async throws {
        let scratch = try await Scratch.copy("rebase")
        defer { scratch.remove() }
        let gitDir = try await scratch.gitDir()
        let origHead = try #require(OID(try String(contentsOf: gitDir.appending(path: "rebase-merge/orig-head"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        let store = try scratch.store()
        try await store.abort()
        #expect(OperationInProgress.current(gitDir: gitDir) == nil)
        #expect(try await scratch.oid("HEAD") == origHead)
        #expect(scratch.log.commands.contains("git rebase --abort"))
        #expect(await store.recorded.isEmpty)
    }
}
