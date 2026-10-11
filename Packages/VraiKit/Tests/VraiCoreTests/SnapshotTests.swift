import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct SnapshotBuilderTests {
    @Test func everydayAgreesWithGit() async throws {
        let git = try Sandbox.git("everyday/vrai")
        let snapshot = try await SnapshotBuilder(git: git).build()
        #expect(snapshot.head == .branch("feature/graph-renderer"))
        #expect(snapshot.headOID?.rawValue == (try await Sandbox.output("everyday/vrai", ["rev-parse", "HEAD"])))
        #expect(snapshot.ahead == 2 && snapshot.behind == 1)
        #expect(snapshot.state == .clean)
        #expect(snapshot.working.count == 7)
        #expect(snapshot.conflicts.isEmpty)

        let gitBranches = try await Sandbox.output("everyday/vrai", ["for-each-ref", "--format=%(refname) %(objectname)", "refs/heads"]).split(separator: "\n").map(String.init).sorted()
        #expect(snapshot.branches.map { "refs/heads/\($0.name) \($0.tip.rawValue)" }.sorted() == gitBranches)
        #expect(snapshot.branches.first { $0.name == "main" }?.colorIndex == 0)
        #expect(snapshot.branches.first { $0.name == "feature/graph-renderer" }?.colorIndex == 1)
        #expect(Set(snapshot.branches.map(\.colorIndex)).count == snapshot.branches.count)
        #expect(snapshot.remoteBranches.first { $0.fullName == "origin/feature/graph-renderer" }?.colorIndex == 1)

        #expect(snapshot.remotes.map(\.name) == ["origin", "mira"])
        #expect(snapshot.remotes.first?.headBranch == "main")
        #expect(snapshot.tags.map(\.name).sorted() == ["v0.8.0", "v0.9.0", "v0.9.1"])
        #expect(snapshot.stashes.count == 3)
        #expect(snapshot.worktrees.count == 3)
        #expect(snapshot.worktrees.first?.changes == 7)
        #expect(snapshot.worktrees.dropFirst().allSatisfy { $0.changes == 0 })
        #expect(snapshot.hooks.map(\.name) == ["commit-msg", "pre-commit", "pre-push"])
        #expect(snapshot.hooks.map(\.enabled) == [true, true, false])
        #expect(snapshot.lastFetch != nil)
        #expect(!snapshot.isBare && !snapshot.isShallow)

        let modules = Dictionary(uniqueKeysWithValues: snapshot.submodules.map { ($0.path, $0) })
        #expect(modules["Vendor/libgit2"]?.state == .ahead)
        #expect(modules["Vendor/libgit2"]?.ahead == 2)
        let manifest = try Sandbox.manifest("everyday")
        let recorded = (manifest["submodules"] as? [String: [String: Any]])?["Vendor/libgit2"]?["recorded"] as? String
        #expect(modules["Vendor/libgit2"]?.recorded?.rawValue == recorded)
        let checkedOut = try await GitProcess(executable: GitExecutable.discover(), workingDirectory: Sandbox.repository("everyday/vrai/Vendor/libgit2"), environment: .sandbox(root: Sandbox.root)).run(.read(["rev-parse", "HEAD"])).output.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(modules["Vendor/libgit2"]?.checkedOut?.rawValue == checkedOut)
        #expect(snapshot.submodules.map(\.path) == ["Vendor/cmark-gfm", "Vendor/libgit2", "Vendor/swift-argument-parser"])
        #expect(modules["Vendor/cmark-gfm"]?.state == .clean)
        #expect(modules["Vendor/swift-argument-parser"]?.state == .uninitialized)

        let files = Dictionary(uniqueKeysWithValues: snapshot.working.map { ($0.path, $0) })
        #expect(files["Sources/VraiUI/History/GraphCell.swift"]?.additions == 13)
        #expect(files["Sources/VraiUI/History/GraphCell.swift"]?.deletions == 2)
        #expect(files["Sources/VraiGit/Graph/LaneLayout.swift"]?.additions == 10)
        #expect(files["Sources/VraiUI/History/HeadHalo.swift"]?.additions == 24)
        #expect(files["Notes/graph-perf.md"]?.additions == 13)
        #expect(files["Resources/Graph.xcassets/Contents.json"]?.deletions == 12)
    }

    @Test func repositoryStates() async throws {
        let conflict = try await SnapshotBuilder(git: try Sandbox.git("conflict/vrai")).build()
        #expect(conflict.state == .merging(source: "mira/spike/metal-graph"))
        #expect(conflict.conflicts.count == 2)

        let rebase = try await SnapshotBuilder(git: try Sandbox.git("rebase/vrai")).build()
        guard case .rebasing(let step, let total, let stopped, let reason, let branch, _) = rebase.state else {
            Issue.record("expected rebasing, got \(rebase.state)")
            return
        }
        #expect(step == 2 && total == 3)
        #expect(reason == .edit)
        #expect(branch == "feature/graph-renderer")
        #expect(stopped != nil)

        let detached = try await SnapshotBuilder(git: try Sandbox.git("detached/vrai")).build()
        let tagged = try await Sandbox.output("detached/vrai", ["rev-parse", "v0.9.1^{commit}"])
        #expect(detached.state == .detached(OID(tagged)!, nearestTag: "v0.9.1"))
        #expect(detached.working.count == 1)

        let bisect = try await SnapshotBuilder(git: try Sandbox.git("bisect/vrai")).build()
        guard case .bisecting(let good, let bad, let current, let remaining) = bisect.state else {
            Issue.record("expected bisecting, got \(bisect.state)")
            return
        }
        #expect(good.count == 1)
        #expect(bad?.rawValue == (try await Sandbox.output("bisect/vrai", ["rev-parse", "feature/graph-renderer"])))
        #expect(current?.rawValue == (try await Sandbox.output("bisect/vrai", ["rev-parse", "HEAD"])))
        #expect((remaining ?? -1) >= 0)
    }

    @Test func unbornEdgeAndWorktreeRepositories() async throws {
        let empty = try await SnapshotBuilder(git: try Sandbox.git("empty/pocket-notes")).build()
        #expect(empty.head == .unborn("main"))
        #expect(empty.headOID == nil)
        #expect(empty.branches.isEmpty)
        #expect(empty.working.map(\.path).sorted() == [".gitignore", "Package.swift", "README.md", "Sources/PocketNotes/App.swift"])
        #expect(empty.working.first { $0.path == "README.md" }?.additions == 5)
        #expect(empty.state == .clean)

        let edge = try await SnapshotBuilder(git: try Sandbox.git("edge/edge")).build()
        #expect(edge.state == .merging(source: "other"))
        #expect(edge.conflicts.count == 3)
        let files = Dictionary(uniqueKeysWithValues: edge.working.map { ($0.path, $0) })
        #expect(files["image.png"]?.isBinary == true)
        #expect(files["c d.txt"]?.oldPath == "a b.txt")
        #expect(files["new file ünicode.txt"]?.additions == 1)

        let review = try await SnapshotBuilder(git: try GitProcess(executable: GitExecutable.discover(), workingDirectory: Sandbox.root.appending(path: "fixtures/everyday/vrai-review"), environment: .sandbox(root: Sandbox.root))).build()
        #expect(review.gitDir.path(percentEncoded: false).contains("worktrees/vrai-review"))
        guard case .detached = review.state else {
            Issue.record("expected detached in vrai-review")
            return
        }
    }

    @Test func notARepository() async throws {
        let git = try Sandbox.git(at: Sandbox.root.appending(path: "fixtures", directoryHint: .isDirectory))
        await #expect {
            try await SnapshotBuilder(git: git).build()
        } throws: { error in
            (error as? GitError)?.code == .notARepository
        }
    }

    @Test func colorsPersistAcrossBuilds() async throws {
        var colors = BranchColors()
        colors.assign("release/0.9")
        let snapshot = try await SnapshotBuilder(git: try Sandbox.git("everyday/vrai")).build(colors: colors)
        #expect(snapshot.branches.first { $0.name == "release/0.9" }?.colorIndex == 1)
        #expect(snapshot.branchColors.color(for: "release/0.9") == 1)
    }
}

@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct HistoryPagerTests {
    @Test func everydayInOnePageMatchesTheLayout() async throws {
        let git = try Sandbox.git("everyday/vrai")
        let snapshot = try await SnapshotBuilder(git: git).build()
        let pager = HistoryPager(git: git, colors: snapshot.tipColors, head: snapshot.headOID)
        let page = try #require(try await pager.nextPage())
        #expect(page.commits.count == 32)
        #expect(page.isLast)
        #expect(page.rows.map(\.id) == page.commits.map(\.id))
        #expect(page.rows.first?.isHead == true)
        #expect(page.lanes == 4)
        #expect(try await pager.nextPage() == nil)
        let oneShot = LaneLayout.layout(page.commits.map { LayoutCommit(id: $0.id, parents: $0.parents, color: snapshot.tipColors[$0.id]) }, head: snapshot.headOID)
        #expect(oneShot.rows == page.rows)
    }

    @Test func smallPagesAgreeWithOnePage() async throws {
        let git = try Sandbox.git("everyday/vrai")
        let whole = try #require(try await HistoryPager(git: git).nextPage())
        let pager = HistoryPager(git: git, pageSize: 5)
        var rows: [GraphRow] = []
        var offsets: [Int] = []
        while let page = try await pager.nextPage() {
            rows += page.rows
            offsets.append(page.offset)
            if page.isLast { break }
        }
        #expect(rows == whole.rows)
        #expect(offsets == [0, 5, 10, 15, 20, 25, 30])
    }

    @Test func filtersAndScopes() async throws {
        let git = try Sandbox.git("everyday/vrai")
        let current = try #require(try await HistoryPager(git: git, scope: .current).nextPage())
        #expect(current.commits.count == 27)
        let byAuthor = try #require(try await HistoryPager(git: git, filter: HistoryFilter(author: "Hana Sato")).nextPage())
        #expect(!byAuthor.commits.isEmpty)
        #expect(byAuthor.commits.allSatisfy { $0.authorName == "Hana Sato" })
        let byText = try #require(try await HistoryPager(git: git, filter: HistoryFilter(text: "release")).nextPage())
        #expect(byText.commits.map(\.subject).sorted() == ["Release 0.8.0", "Release 0.9.0", "Release 0.9.1"])
        let byPath = try #require(try await HistoryPager(git: git, filter: HistoryFilter(paths: ["Sources/VraiUI/Banners/RebaseBanner.swift"])).nextPage())
        #expect(byPath.commits.map(\.subject).contains("Rebase: show step progress in the banner"))
    }

    @Test func unbornRepositoryHasAnEmptyHistory() async throws {
        let page = try #require(try await HistoryPager(git: try Sandbox.git("empty/pocket-notes")).nextPage())
        #expect(page.commits.isEmpty)
        #expect(page.isLast)
    }

    @Test(.enabled(if: Sandbox.has("large/monorepo")))
    func largePagesStream() async throws {
        let git = try Sandbox.git("large/monorepo")
        let pager = HistoryPager(git: git)
        let first = try #require(try await pager.nextPage())
        let second = try #require(try await pager.nextPage())
        #expect(first.commits.count == 2000)
        #expect(second.commits.count == 2000)
        #expect(second.offset == 2000)
        #expect(Set(first.commits.map(\.id)).isDisjoint(with: second.commits.map(\.id)))
        await pager.cancel()
    }
}
