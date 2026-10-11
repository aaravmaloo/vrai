import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct RewriteReadsTests {
    static let lane = "Sources/VraiGit/Graph/LaneLayout.swift"
    static let cell = "Sources/VraiUI/History/GraphCell.swift"

    @Test func mergePreviewTellsEachKindApart() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        try await scratch.clean()
        let store = try scratch.store()
        try await store.refresh()

        let conflicts = await store.mergePreview(source: "refs/remotes/mira/spike/metal-graph")
        #expect(conflicts.kind == .conflicts)
        #expect(conflicts.conflicted == [Self.cell])
        #expect(conflicts.commitCount > 0)
        #expect(conflicts.commits.count == min(conflicts.commitCount, 50))

        #expect(await store.mergePreview(source: "HEAD~1").kind == .upToDate)
        #expect(await store.mergePreview(source: "HEAD").kind == .upToDate)
        #expect(await store.mergePreview(source: "no-such-branch").kind == .unknown)

        let tree = try await scratch.git(["rev-parse", "HEAD^{tree}"])
        let child = try await scratch.git(["commit-tree", tree, "-p", "HEAD", "-m", "Ahead by one"])
        try await scratch.git(["branch", "ahead", child])
        let forward = await store.mergePreview(source: "ahead")
        #expect(forward.kind == .fastForward)
        #expect(forward.commitCount == 1)
        #expect(forward.commits.map(\.subject) == ["Ahead by one"])
        #expect(try await scratch.git(["status", "--porcelain", "--ignore-submodules"]).isEmpty)
    }

    @Test func rebaseAndBisectPreviews() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        let store = try scratch.store()
        try await store.refresh()

        let rebase = await store.rebasePreview(onto: "origin/main")
        #expect(!rebase.upToDate)
        let expected = try await scratch.git(["rev-list", "--count", "--no-merges", "origin/main..HEAD"])
        #expect(String(rebase.commits.count) == expected)
        #expect(await store.rebasePreview(onto: "HEAD").upToDate)

        let between = await store.commitsBetween("HEAD~3", "HEAD")
        #expect(between.count == 3)
        #expect(between.commits.first?.id == (try await scratch.oid("HEAD")))

        let bisect = await store.bisectPreview(bad: "HEAD", good: "HEAD~3")
        #expect(bisect.valid)
        #expect(bisect.candidates == 3)
        #expect(bisect.steps == 2)
        #expect(!(await store.bisectPreview(bad: "HEAD~3", good: "HEAD")).valid)
        #expect(!(await store.bisectPreview(bad: "HEAD", good: "HEAD")).valid)
        #expect(BisectPreview(candidates: 1, valid: true).steps == 1)
        #expect(BisectPreview(candidates: 9, valid: true).steps == 4)
    }

    @Test func conflictTextRoundTripsAndBasesAreFound() async throws {
        let scratch = try await Scratch.copy("conflict")
        defer { scratch.remove() }
        let store = try scratch.store()
        try await store.refresh()

        let text = try #require(await store.conflictText(path: Self.lane))
        #expect(text == (try scratch.file(Self.lane)))
        #expect(ConflictResolver.conflicts(in: text).count == 2)
        let bases = await store.conflictBases(path: Self.lane)
        #expect(Set(bases.keys) == [1, 2])
        #expect(bases[2] == ["    func node(at lane: Int, in rect: CGRect, merge: Bool = false) -> Path {"])
        try await store.resolve(path: Self.lane, block: 1, with: .base)
        let based = try scratch.file(Self.lane)
        #expect(ConflictResolver.conflicts(in: based).count == 1)
        #expect(based.contains("    var nodeSize: CGFloat = 9\n\n    func x(for lane: Int) -> CGFloat {\n        CGFloat(lane) * laneWidth + laneWidth / 2\n    }\n"))
        try await store.restoreConflictText(path: Self.lane, text: text)

        let resolved = try ConflictResolver.resolve(text, block: 1, with: .theirs)
        try await store.restoreConflictText(path: Self.lane, text: resolved)
        #expect(ConflictResolver.conflicts(in: try scratch.file(Self.lane)).count == 1)
        try await store.restoreConflictText(path: Self.lane, text: text)
        #expect(try scratch.file(Self.lane) == text)
        #expect(await store.conflictText(path: "Missing/File.swift") == nil)
    }

    @Test func stashDetailListsFilesAndDiffs() async throws {
        let scratch = try await Scratch.copy("everyday")
        defer { scratch.remove() }
        let store = try scratch.store()
        try await store.refresh()
        let stashes = try #require(store.snapshot?.stashes)
        #expect(!stashes.isEmpty)

        for stash in stashes {
            let detail = try await store.stashDetail(index: stash.index)
            let tracked = try await scratch.git(["diff", "--name-only", "stash@{\(stash.index)}^1", "stash@{\(stash.index)}"]).split(separator: "\n").map(String.init)
            let paths = Set(detail.files.map(\.path))
            #expect(Set(tracked).isSubset(of: paths))
            #expect(detail.untracked.isSubset(of: paths))
            #expect(detail.files.map(\.path) == detail.files.map(\.path).sorted())
            let first = try #require(detail.files.first)
            let diff = try await store.stashDiff(index: stash.index, path: first.path, detail: detail)
            #expect(diff?.path == first.path)
        }

        try await scratch.clean()
        try Data("fresh\n".utf8).write(to: scratch.repository.appending(path: "fresh.txt"))
        try await store.stash(message: "with untracked", includeUntracked: true)
        let detail = try await store.stashDetail(index: 0)
        #expect(detail.untracked == ["fresh.txt"])
        #expect(detail.untrackedCommit != nil)
        let diff = try await store.stashDiff(index: 0, path: "fresh.txt", detail: detail)
        #expect(diff?.status == .untracked)

        let missing = await #expect(throws: GitError.self) { try await store.stashDetail(index: 99) }
        #expect(missing?.code == .refNotFound)
    }
}
