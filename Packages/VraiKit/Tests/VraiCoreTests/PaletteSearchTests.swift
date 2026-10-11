import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

struct RankItem: PaletteRankable, Equatable {
    var rankLabel: String
    var rankKeywords: String?
    var rankDetail: String?
    var rankCurrent = false
}

struct PaletteRankingTests {
    @Test func matchFollowsThePrototype() {
        #expect(PaletteRanking.match("Fetch", "") == 1)
        #expect(PaletteRanking.match("Fetch", "fe") == 100 - 5.0 / 100)
        #expect(PaletteRanking.match("New branch", "branch") == 60 - 4.0 / 10)
        #expect(abs(PaletteRanking.match("feature/graph-renderer", "fgr") - 12.3) < 0.0001)
        #expect(PaletteRanking.match("feature/graph-renderer", "feat gr") > 10)
        #expect(PaletteRanking.match("main", "xyz") == 0)
        #expect(PaletteRanking.match("Push 2 commits", "PUSH") == 100 - 14.0 / 100)
    }

    @Test func relevanceUsesLabelKeywordsAndStrongDetails() {
        let item = RankItem(rankLabel: "LaneLayout.swift", rankKeywords: "Sources/VraiGit/Graph/LaneLayout.swift", rankDetail: "Sources/VraiGit/Graph")
        #expect(PaletteRanking.relevant(item, "lane"))
        #expect(PaletteRanking.relevant(item, "vraigit/graph"))
        let detailOnly = RankItem(rankLabel: "Fetch", rankKeywords: nil, rankDetail: "Repository")
        #expect(PaletteRanking.relevant(detailOnly, "repo"))
        #expect(!PaletteRanking.relevant(detailOnly, "zz"))
        let weakDetail = RankItem(rankLabel: "Fetch", rankKeywords: nil, rankDetail: "Repository")
        #expect(!PaletteRanking.relevant(weakDetail, "rpy"))
    }

    @Test func arrangeSortsByScoreAndLimits() {
        let items = ["Merge into main…", "Fetch", "Rebase main…", "Interactive rebase…", "Rename main…"].map { RankItem(rankLabel: $0) }
        let groups = PaletteRanking.arrange([PaletteGroup(.actions, items, limit: 2)], "re")
        #expect(groups.count == 1)
        #expect(groups[0].items.map(\.rankLabel) == ["Rebase main…", "Rename main…"])
        let empty = PaletteRanking.arrange([PaletteGroup(.actions, items, limit: 3)], "")
        #expect(empty[0].items.map(\.rankLabel) == ["Merge into main…", "Fetch", "Rebase main…"])
        #expect(PaletteRanking.arrange([PaletteGroup(.tags, [RankItem(rankLabel: "v0.9.0")])], "zzz").isEmpty)
    }

    @Test func topHitPrefersWeightedGroupsAndSkipsTheCurrentBranch() {
        let branches = [RankItem(rankLabel: "main", rankCurrent: true), RankItem(rankLabel: "mira/spike/metal-graph")]
        let actions = [RankItem(rankLabel: "Merge into main…"), RankItem(rankLabel: "Fetch")]
        let groups = [PaletteGroup(.actions, actions), PaletteGroup(.branches, branches)]
        let promoted = PaletteRanking.promoteTopHit(PaletteRanking.filterRelevant(groups, "mi"), "mi") { $0 == $1 }
        #expect(promoted.first?.kind == .topHit)
        #expect(promoted.first?.items == [RankItem(rankLabel: "mira/spike/metal-graph")])
        #expect(promoted.first { $0.kind == .branches }?.items == [RankItem(rankLabel: "main", rankCurrent: true)])
        let weak = PaletteRanking.promoteTopHit([PaletteGroup(.commits, [RankItem(rankLabel: "abc")])], "xyzzy") { $0 == $1 }
        #expect(weak.first?.kind == .commits)
    }
}

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct PaletteSearchTests {
    @Test func findsBranchesAndTagsFromTheSnapshot() async throws {
        let fixture = try await ConsoleFixture.make()
        defer { fixture.remove() }
        let snapshot = try #require(fixture.store.snapshot)
        let branches = snapshot.branches.map { RankItem(rankLabel: $0.name, rankKeywords: ($0.name.split(separator: "/").last.map(String.init) ?? "") + " " + ($0.upstream ?? ""), rankCurrent: $0.isCurrent) }
        let tags = snapshot.tags.map { RankItem(rankLabel: $0.name) }
        let groups = PaletteRanking.arrange(PaletteRanking.filterRelevant([PaletteGroup(.branches, branches, limit: 5), PaletteGroup(.tags, tags, limit: 3)], "line"), "line")
        #expect(groups.first { $0.kind == .branches }?.items.first?.rankLabel == "feature/line-staging")
        let tagGroups = PaletteRanking.arrange(PaletteRanking.filterRelevant([PaletteGroup(.tags, tags, limit: 3)], "v0.9"), "v0.9")
        #expect(Set(tagGroups.first?.items.map(\.rankLabel) ?? []) == ["v0.9.0", "v0.9.1"])
    }

    @Test func findsCommitsBySubjectAndHash() async throws {
        let fixture = try await ConsoleFixture.make()
        defer { fixture.remove() }
        let bySubject = try await fixture.store.searchCommits("snap nodes")
        #expect(bySubject.map(\.subject).contains("Graph: snap nodes to the pixel grid"))
        let target = try #require(bySubject.first { $0.subject == "Graph: snap nodes to the pixel grid" })
        let byHash = try await fixture.store.searchCommits(String(target.id.rawValue.prefix(7)))
        #expect(byHash.first?.id == target.id)
        let parent = try await fixture.store.searchCommits("main~1")
        #expect(parent.first?.id.rawValue == (try await fixture.copy.tip("main~1")))
        let message = try await fixture.store.searchCommits(":/snap nodes")
        #expect(message.isEmpty)
        let found = try await fixture.store.searchCommits(":/Graph:")
        #expect(found.count == 1)
        let range = try await fixture.store.searchCommits("main..feature/graph-renderer")
        let expectedRange = try await fixture.copy.git(["rev-list", "--count", "main..feature/graph-renderer"])
        #expect(range.count == min(20, Int(expectedRange) ?? -1))
        #expect(RepositoryStore.looksLikeRevision("HEAD@{2}"))
        #expect(!RepositoryStore.looksLikeRevision("snap nodes"))
        let nothing = try await fixture.store.searchCommits("no commit says this")
        #expect(nothing.isEmpty)
        let entries = fixture.console.entries.filter { $0.command.contains("--grep=") }
        #expect(entries.allSatisfy { $0.background })
        let commands = fixture.console.entries.map(\.command)
        #expect(commands.allSatisfy { !$0.contains("refs/vrai") })
    }

    @Test func findsTrackedFilesWithSpacesAndUnicode() async throws {
        let fixture = try await ConsoleFixture.make()
        defer { fixture.remove() }
        let files = try await fixture.store.trackedFiles()
        #expect(files.contains("Sources/VraiGit/Graph/LaneLayout.swift"))
        #expect(files.contains("Docs/Design notes/Lane colors.md"))
        #expect(files.contains("Docs/Résumé des branches.md"))
        let items = files.map { RankItem(rankLabel: PathParts.split($0).name, rankKeywords: $0, rankDetail: PathParts.split($0).directory) }
        let groups = PaletteRanking.arrange(PaletteRanking.filterRelevant([PaletteGroup(.files, items, limit: 5)], "lanelay"), "lanelay")
        #expect(groups.first?.items.first?.rankLabel == "LaneLayout.swift")
    }

    @Test func searchesCodeWithGitGrep() async throws {
        let fixture = try await ConsoleFixture.make()
        defer { fixture.remove() }
        let files = try await fixture.store.trackedFiles()
        let readme = try String(contentsOf: fixture.repository.appending(path: "README.md"), encoding: .utf8)
        let word = try #require(readme.split(whereSeparator: { !$0.isLetter }).first { $0.count >= 5 }.map(String.init))
        let matches = try await fixture.store.grep(text: word.uppercased())
        #expect(!matches.isEmpty)
        #expect(matches.allSatisfy { files.contains($0.path) || $0.path == "README.md" })
        #expect(matches.contains { $0.path == "README.md" && $0.text.localizedCaseInsensitiveContains(word) })
        #expect(try await fixture.store.grep(text: "zz-no-such-text-zz").isEmpty)
        let atMain = try await fixture.store.grep(text: word, at: "main")
        #expect(atMain.allSatisfy { !$0.path.hasPrefix("main:") })
    }

    @Test func recentBranchesFollowTheReflog() async throws {
        let fixture = try await ConsoleFixture.make()
        defer { fixture.remove() }
        _ = try await fixture.copy.git(["stash", "push", "-u", "-m", "aside"])
        try await fixture.store.refresh()
        _ = try await fixture.store.switchTo(branch: "main")
        _ = try await fixture.store.switchTo(branch: "fix/rebase-banner")
        let recent = await fixture.store.recentBranches()
        #expect(Array(recent.prefix(3)) == ["fix/rebase-banner", "main", "feature/graph-renderer"])
        #expect(Set(recent) == Set(fixture.store.snapshot?.branches.map(\.name) ?? []))
    }
}
