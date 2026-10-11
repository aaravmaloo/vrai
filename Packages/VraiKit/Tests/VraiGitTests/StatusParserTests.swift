import Foundation
import Testing
@testable import VraiGit

struct StatusParserTests {
    @Test func everydayMatchesTheSeedsWorkingChanges() throws {
        let report = StatusParser.parse(try Recorded.data("everyday", "status"))
        #expect(report.head == .branch("feature/graph-renderer"))
        #expect(report.upstream == "origin/feature/graph-renderer")
        #expect(report.ahead == 2)
        #expect(report.behind == 1)
        #expect(report.stashCount == 3)
        let byPath = Dictionary(uniqueKeysWithValues: report.files.map { ($0.path, $0) })
        #expect(report.files.count == 7)
        #expect(byPath["Sources/VraiUI/History/GraphCell.swift"]?.staged == .full)
        #expect(byPath["Sources/VraiGit/Graph/LaneLayout.swift"]?.staged == .partial)
        #expect(byPath["Sources/VraiGit/Graph/LaneLayout.swift"]?.status == .modified)
        let renamed = try #require(byPath["Sources/VraiUI/History/LaneColors.swift"])
        #expect(renamed.status == .renamed)
        #expect(renamed.oldPath == "Sources/VraiUI/History/Palette.swift")
        #expect(renamed.staged == .full)
        #expect(byPath["Resources/Graph.xcassets/Contents.json"]?.status == .deleted)
        #expect(byPath["Resources/Graph.xcassets/Contents.json"]?.staged == StageState.none)
        #expect(byPath["Sources/VraiUI/History/HeadHalo.swift"]?.status == .untracked)
        #expect(byPath["Notes/graph-perf.md"]?.status == .untracked)
        #expect(byPath["Vendor/libgit2"]?.isSubmodule == true)
        #expect(report.conflicts.isEmpty)
    }

    @Test func edgeCoversSpacesUnicodeBinaryTypeChangesAndConflicts() throws {
        let report = StatusParser.parse(try Recorded.data("edge", "status"))
        let byPath = Dictionary(uniqueKeysWithValues: report.files.map { ($0.path, $0) })
        let rename = try #require(byPath["c d.txt"])
        #expect(rename.status == .renamed)
        #expect(rename.oldPath == "a b.txt")
        #expect(rename.staged == .partial)
        #expect(byPath["Résumé.md"]?.status == .modified)
        #expect(byPath["link-target.txt"]?.status == .typeChanged)
        #expect(byPath["script.sh"]?.status == .modified)
        #expect(byPath["image.png"]?.status == .modified)
        #expect(byPath["staged new.txt"]?.status == .added)
        #expect(byPath["staged new.txt"]?.staged == .partial)
        #expect(byPath["new file ünicode.txt"]?.status == .untracked)
        let kinds = Dictionary(uniqueKeysWithValues: report.conflicts.map { ($0.path, $0.kind) })
        #expect(kinds == ["both-added.txt": .bothAdded, "conflict.txt": .bothModified, "deleted-by-them.txt": .deletedByThem])
        #expect(byPath["conflict.txt"]?.status == .conflicted)
    }

    @Test func unbornDetachedAndInProgressStates() throws {
        let empty = StatusParser.parse(try Recorded.data("empty", "status"))
        #expect(empty.head == .unborn("main"))
        #expect(empty.files.count == 4)
        #expect(empty.files.allSatisfy { $0.status == .untracked })

        let detached = StatusParser.parse(try Recorded.data("detached", "status"))
        guard case .detached(let oid) = detached.head else {
            Issue.record("expected a detached HEAD, got \(detached.head)")
            return
        }
        #expect(oid.short.count == 7)

        let conflict = StatusParser.parse(try Recorded.data("conflict", "status"))
        #expect(conflict.conflicts.map(\.path).sorted() == ["Sources/VraiGit/Graph/LaneLayout.swift", "Sources/VraiUI/History/GraphCell.swift"])
        #expect(conflict.files.filter { $0.status == .added && $0.staged == .full }.map(\.path).sorted() == ["Sources/VraiUI/History/GraphRenderer.metal", "Sources/VraiUI/History/MetalGraphView.swift"])
        #expect(conflict.ahead == 3)
    }
}

struct RefParserTests {
    static var everyday: RefListing { RefParser.parse((try? Recorded.data("everyday", "refs")) ?? Data(), remotes: ["origin", "mira"]) }

    @Test func branchesTrackTheirUpstreams() throws {
        let branches = Dictionary(uniqueKeysWithValues: Self.everyday.branches.map { ($0.name, $0) })
        #expect(branches.keys.sorted() == ["feature/graph-renderer", "feature/line-staging", "fix/rebase-banner", "main", "mira/spike/metal-graph", "release/0.9"])
        let current = try #require(branches["feature/graph-renderer"])
        #expect(current.isCurrent)
        #expect(current.upstream == "origin/feature/graph-renderer")
        #expect(current.ahead == 2 && current.behind == 1)
        #expect(branches["main"]?.behind == 1)
        #expect(branches["main"]?.ahead == 0)
        #expect(branches["fix/rebase-banner"]?.upstream == nil)
        #expect(branches["mira/spike/metal-graph"]?.upstream == "mira/spike/metal-graph")
        #expect(branches["release/0.9"]?.worktreePath == "/SANDBOX/fixtures/everyday/vrai-release")
        #expect(branches.values.filter(\.isCurrent).count == 1)
    }

    @Test func remoteBranchesAndRemoteHeads() {
        let names = Self.everyday.remoteBranches.map(\.fullName).sorted()
        #expect(names == ["mira/spike/metal-graph", "origin/feature/graph-renderer", "origin/feature/line-staging", "origin/main", "origin/release/0.9"])
        #expect(Self.everyday.remoteHeads == ["origin": "main", "mira": "spike/metal-graph"])
    }

    @Test func tagsKnowAnnotationAndSignatures() throws {
        let tags = Dictionary(uniqueKeysWithValues: Self.everyday.tags.map { ($0.name, $0) })
        let release = try #require(tags["v0.9.1"])
        #expect(release.annotated)
        #expect(release.tagger == "Priya Raman")
        #expect(release.message == "Vrai 0.9.1")
        #expect(release.signature == .unchecked)
        #expect(release.date == Date(timeIntervalSince1970: 1_791_720_000 - 144 * 3600))
        let light = try #require(tags["v0.8.0"])
        #expect(!light.annotated)
        #expect(light.signature == .unsigned)
        #expect(light.tagger == nil)
        let branches = Dictionary(uniqueKeysWithValues: Self.everyday.branches.map { ($0.name, $0) })
        #expect(release.target == branches["release/0.9"]?.tip)
    }
}

struct ConfigParserTests {
    @Test func remotesWithPruneAndHeads() throws {
        let remotes = ConfigParser.remotes(try Recorded.data("everyday", "remotes"), heads: ["origin": "main"])
        #expect(remotes.map(\.name) == ["origin", "mira"])
        #expect(remotes[0].fetchURL == "file:///SANDBOX/fixtures/everyday/remotes/origin.git")
        #expect(remotes[0].prune)
        #expect(remotes[0].headBranch == "main")
        #expect(!remotes[1].prune)
        #expect(remotes[1].pushURL == nil)
    }

    @Test func configTableHasScopesAndOrigins() throws {
        let table = ConfigParser.table(try Recorded.data("everyday", "config"))
        let name = try #require(table.first { $0.key == "user.name" })
        #expect(name.scope == .global)
        #expect(name.origin == "file:/SANDBOX/gitconfig")
        #expect(name.value == "Avery Chen")
        #expect(table.contains { $0.scope == .local && $0.key == "remote.origin.prune" && $0.value == "true" })
        #expect(table.contains { $0.scope == .local && $0.key == "branch.feature/graph-renderer.merge" && $0.value == "refs/heads/feature/graph-renderer" })
        #expect(!table.contains { $0.scope == .system })
    }

    @Test func gitmodules() throws {
        let modules = ConfigParser.gitmodules(try Recorded.data("everyday", "gitmodules"))
        #expect(modules.map(\.path) == ["Vendor/libgit2", "Vendor/cmark-gfm", "Vendor/swift-argument-parser"])
        #expect(modules[0].url == "../libgit2.git")
        #expect(modules[0].branch == "v1.9.1")
    }
}

struct PlacesParserTests {
    @Test func stashes() throws {
        let stashes = StashParser.parse(try Recorded.data("everyday", "stashes"))
        #expect(stashes.map(\.index) == [0, 1, 2])
        #expect(stashes.map(\.message) == ["On feature/graph-renderer: halo experiments", "On main: release notes draft", "WIP on feature/line-staging: 87f2f88 Diff: stage individual lines from the gutter"])
        #expect(stashes.map(\.branch) == ["feature/graph-renderer", "main", "feature/line-staging"])
        #expect(stashes[0].date == Date(timeIntervalSince1970: 1_791_720_000 - 3 * 3600))
        #expect(stashes[2].base?.short == "87f2f88")
    }

    @Test func worktrees() throws {
        let worktrees = WorktreeParser.parse(try Recorded.data("everyday", "worktrees"))
        #expect(worktrees.count == 3)
        #expect(worktrees[0].isMain)
        #expect(worktrees[0].branch == "feature/graph-renderer")
        #expect(worktrees[1].path.hasSuffix("/vrai-release"))
        #expect(worktrees[1].branch == "release/0.9")
        #expect(!worktrees[1].isMain)
        #expect(worktrees[2].branch == nil)
        #expect(worktrees[2].detachedAt?.short == "87f2f88")
        #expect(worktrees[2].locked)
        #expect(worktrees[2].lockReason == "Reviewing line staging with Jonas")
    }

    @Test func submodulesMergeStatusAndGitmodules() throws {
        let lines = SubmoduleParser.statusLines(try Recorded.data("everyday", "submodule-status"))
        let modules = SubmoduleParser.merge(status: lines, gitmodules: try Recorded.data("everyday", "gitmodules"))
        let byPath = Dictionary(uniqueKeysWithValues: modules.map { ($0.path, $0) })
        #expect(byPath["Vendor/libgit2"]?.state == .ahead)
        #expect(byPath["Vendor/libgit2"]?.describe == "heads/v1.9.1")
        #expect(byPath["Vendor/cmark-gfm"]?.state == .clean)
        #expect(byPath["Vendor/cmark-gfm"]?.url == "../cmark-gfm.git")
        #expect(byPath["Vendor/swift-argument-parser"]?.state == .uninitialized)
        #expect(byPath["Vendor/swift-argument-parser"]?.checkedOut == nil)
    }

    @Test func gitlinksAgreeWithSubmoduleStatus() throws {
        let links = SubmoduleParser.gitlinks(try Recorded.data("everyday", "submodule-stage"))
        #expect(links.map(\.path) == ["Vendor/cmark-gfm", "Vendor/libgit2", "Vendor/swift-argument-parser"])
        #expect(links.allSatisfy { !$0.conflicted && $0.oid != nil })
        let byPath = Dictionary(uniqueKeysWithValues: links.map { ($0.path, $0) })
        for line in SubmoduleParser.statusLines(try Recorded.data("everyday", "submodule-status")) where line.flag != "+" {
            #expect(byPath[line.path]?.oid == line.oid, "\(line.path)")
        }
        let declared = ConfigParser.gitmodules(try Recorded.data("everyday", "gitmodules"))
        let link = try #require(byPath["Vendor/cmark-gfm"])
        let info = declared.first { $0.path == link.path }
        #expect(SubmoduleParser.submodule(link, declared: info, head: .commit(link.oid!)).state == .clean)
        #expect(SubmoduleParser.submodule(link, declared: info, head: .unpopulated).state == .uninitialized)
        #expect(SubmoduleParser.submodule(link, declared: info, head: .commit(OID(String(repeating: "a", count: 40))!)).state == .ahead)
        #expect(SubmoduleParser.submodule(link, declared: info, head: .unpopulated).url == "../cmark-gfm.git")
    }

    @Test func conflictedGitlinkKeepsOurs() {
        let ours = String(repeating: "b", count: 40)
        let data = Data("160000 \(String(repeating: "a", count: 40)) 1\tVendor/x\u{0}160000 \(ours) 2\tVendor/x\u{0}160000 \(String(repeating: "c", count: 40)) 3\tVendor/x\u{0}".utf8)
        let links = SubmoduleParser.gitlinks(data)
        #expect(links.count == 1)
        #expect(links.first?.conflicted == true)
        #expect(links.first?.oid?.rawValue == ours)
        #expect(SubmoduleParser.submodule(links[0], declared: nil, head: .unpopulated).state == .conflicted)
    }

    @Test func reflog() throws {
        let entries = ReflogParser.parse(try Recorded.data("rebase", "reflog"))
        #expect(!entries.isEmpty)
        #expect(entries[0].selector == "HEAD@{0}")
        #expect(entries.contains { $0.message.hasPrefix("rebase (start): checkout origin/main") })
        #expect(entries.contains { $0.message.hasPrefix("rebase (edit): Graph: keep the HEAD halo above merge rings") || $0.message.hasPrefix("rebase (pick): Graph: keep the HEAD halo") })
    }

    @Test func location() throws {
        let location = try #require(RepositoryLocation.parse(try Recorded.data("everyday", "location")))
        #expect(location.root?.path(percentEncoded: false) == "/SANDBOX/fixtures/everyday/vrai/")
        #expect(location.gitDir.lastPathComponent == ".git")
        #expect(!location.isBare)
        #expect(!location.isShallow)
        #expect(location.hooksDir.path(percentEncoded: false).hasSuffix(".git/hooks/"))
        let worktree = try #require(RepositoryLocation.parse(try Recorded.data("worktree-review", "location")))
        #expect(worktree.gitDir.path(percentEncoded: false).contains(".git/worktrees/vrai-review"))
        #expect(worktree.commonDir.path(percentEncoded: false).hasSuffix("everyday/vrai/.git/"))
    }
}

struct LogParserTests {
    @Test func everydayHistoryHasTheSeedTopology() throws {
        let commits = LogParser.history(try Recorded.data("everyday", "history"))
        #expect(commits.count == 32)
        #expect(commits[0].subject == "Graph: draw merge curves with cubic béziers")
        #expect(commits[0].authorName == "Avery Chen")
        #expect(commits[0].authorDate == Date(timeIntervalSince1970: 1_791_720_000 - 2 * 3600))
        #expect(commits[0].refs.contains { $0.kind == .branch && $0.name == "feature/graph-renderer" && $0.isHead })
        #expect(commits.filter(\.isMerge).map(\.subject) == ["Merge branch 'fix/rebase-banner'", "Merge branch 'feature/conflict-view'", "Merge branch 'feature/blame'"])
        let root = try #require(commits.last)
        #expect(root.parents.isEmpty)
        #expect(root.subject == "Create the Vrai app target")
        let release = try #require(commits.first { $0.subject == "Release 0.9.1" })
        #expect(release.refs.contains { $0.kind == .tag && $0.name == "v0.9.1" })
        #expect(release.refs.contains { $0.kind == .remoteBranch && $0.name == "origin/release/0.9" })
        let spike = try #require(commits.first { $0.subject == "Metal: draw lanes with instanced quads" })
        #expect(spike.refs.contains { $0.kind == .branch && $0.name == "mira/spike/metal-graph" })
        #expect(spike.refs.contains { $0.kind == .remoteBranch && $0.name == "mira/spike/metal-graph" })
        #expect(!commits.flatMap(\.refs).contains { $0.fullName == "refs/stash" })
        let ids = Set(commits.map(\.id))
        for commit in commits { #expect(commit.parents.allSatisfy(ids.contains)) }
        #expect(commits.map(\.authorName).contains("Tomás Ferreira"))
    }

    @Test func signaturesMatchTheSeed() throws {
        let commits = LogParser.history(try Recorded.data("everyday", "history"))
        let signatures = LogParser.signatures(try Recorded.data("everyday", "signatures"))
        let bySubject = Dictionary(uniqueKeysWithValues: commits.map { ($0.subject, signatures[$0.id]) })
        #expect(bySubject["Graph: draw merge curves with cubic béziers"] == .verified)
        #expect(bySubject["Diff: track selected line ranges per hunk"] == .unknownKey)
        #expect(bySubject["Metal: draw lanes with instanced quads"] == .unsigned)
        #expect(bySubject["Rebase: show step progress in the banner"] == .unsigned)
    }

    @Test func detailedHeadCommitWithFiles() throws {
        let detail = try #require(LogParser.detail(try Recorded.data("everyday", "detail-head")))
        #expect(detail.commit.subject == "Graph: draw merge curves with cubic béziers")
        #expect(detail.commit.body?.hasPrefix("Lane changes used straight segments") == true)
        #expect(detail.commit.signature == .verified)
        #expect(detail.signer == "avery@vrai.app")
        #expect(detail.signingKey?.hasPrefix("SHA256:") == true)
        #expect(detail.files.map(\.path) == ["Sources/VraiGit/Graph/LaneLayout.swift", "Sources/VraiUI/History/GraphCell.swift"])
        #expect(detail.files[0].additions == 8)
        #expect(detail.files[0].deletions == 2)
        #expect(detail.files.allSatisfy { $0.status == .modified })
    }

    @Test func unbornRepositoryHasNoHistory() throws {
        #expect(LogParser.history(try Recorded.data("empty", "history")).isEmpty)
    }

    @Test func decorationsWithFullNames() {
        let refs = LogParser.decorations("HEAD -> refs/heads/main, refs/remotes/origin/main, refs/remotes/origin/HEAD, tag: refs/tags/v1.0, refs/stash")
        #expect(refs.map(\.kind) == [.branch, .remoteBranch, .tag])
        #expect(refs[0].isHead)
        #expect(refs.map(\.name) == ["main", "origin/main", "v1.0"])
        #expect(LogParser.decorations("HEAD").first?.kind == .head)
        #expect(LogParser.decorations("").isEmpty)
    }

    @Test func changedFilesHandleRenamesAndBinaries() {
        let tokens = [":100644 100644 aaa bbb R064", "old name.txt", "new name.txt", ":100644 100644 ccc ddd M", "image.png", "3\t3\t", "old name.txt", "new name.txt", "-\t-\timage.png", ""]
        let files = LogParser.changedFiles(tokens)
        #expect(files.count == 2)
        #expect(files[0].status == .renamed)
        #expect(files[0].oldPath == "old name.txt")
        #expect(files[0].path == "new name.txt")
        #expect(files[0].additions == 3)
        #expect(files[1].isBinary)
    }
}

struct BlameParserTests {
    @Test func blameOfLaneLayout() throws {
        let lines = BlameParser.parse(try Recorded.data("everyday", "blame"))
        #expect(lines.count == 96)
        #expect(lines.map(\.number) == Array(1...96))
        #expect(lines[0].text == "import CoreGraphics")
        #expect(lines[0].authorName == "Mira Okafor")
        #expect(lines[0].summary == "Graph: first lane layout")
        let curve = try #require(lines.first { $0.text == "        let mid = row.midY" })
        #expect(curve.summary == "Graph: draw merge curves with cubic béziers")
        #expect(curve.authorEmail == "avery@vrai.app")
        #expect(curve.previous != nil)
        #expect(curve.previousPath == "Sources/VraiGit/Graph/LaneLayout.swift")
        #expect(Set(lines.map(\.commit)).count >= 3)
    }

    @Test func blameOfAUnicodePath() throws {
        let lines = BlameParser.parse(try Recorded.data("edge", "blame"))
        #expect(lines.count == 3)
        #expect(lines[0].path == "Résumé.md")
        #expect(lines[2].text == "Naïve café notes.")
    }
}
