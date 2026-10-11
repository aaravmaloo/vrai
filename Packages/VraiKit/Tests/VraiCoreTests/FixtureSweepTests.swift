import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct FixtureSweepTests {
    static let repositories = [
        "everyday/vrai", "everyday/vrai-release", "everyday/vrai-review", "push-rejected/vrai", "conflict/vrai", "rebase/vrai",
        "detached/vrai", "bisect/vrai", "auth/vrai", "offline/vrai", "empty/pocket-notes", "edge/edge",
        "welcome/swift-collections", "welcome/dotfiles", "large/monorepo"
    ]

    static func lines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    @Test(arguments: repositories)
    func snapshotAgreesWithGit(_ repository: String) async throws {
        let git = try Sandbox.git(repository)
        let snapshot = try await SnapshotBuilder(git: git).build()
        let head = try await git.runAllowingFailure(.read(["rev-parse", "--verify", "--quiet", "HEAD"]))
        #expect(snapshot.headOID?.rawValue == (head.exitCode == 0 ? head.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil))

        let porcelain = try await Sandbox.output(repository, ["status", "--porcelain=v1", "--untracked-files=all", "--find-renames"])
        #expect(snapshot.working.count == Self.lines(porcelain).count)
        #expect(snapshot.conflicts.count == Self.lines(porcelain).filter { ["DD", "AU", "UD", "UA", "DU", "AA", "UU"].contains(String($0.prefix(2))) }.count)
        #expect(snapshot.working.allSatisfy { !$0.path.isEmpty && !$0.path.hasPrefix("\"") })

        #expect(snapshot.branches.count == Self.lines(try await Sandbox.output(repository, ["for-each-ref", "--format=%(refname)", "refs/heads"])).count)
        #expect(snapshot.tags.count == Self.lines(try await Sandbox.output(repository, ["for-each-ref", "--format=%(refname)", "refs/tags"])).count)
        let remoteRefs = Self.lines(try await Sandbox.output(repository, ["for-each-ref", "--format=%(if)%(symref)%(then)link%(else)branch%(end)", "refs/remotes"])).filter { $0 == "branch" }
        #expect(snapshot.remoteBranches.count == remoteRefs.count)
        #expect(snapshot.remotes.count == Self.lines(try await Sandbox.output(repository, ["remote"])).count)
        #expect(snapshot.stashes.count == Self.lines(try await Sandbox.output(repository, ["stash", "list"])).count)
        #expect(snapshot.worktrees.count == Self.lines(try await Sandbox.output(repository, ["worktree", "list"])).count)
        let tracking = try await Sandbox.output(repository, ["submodule", "status"])
        #expect(snapshot.submodules.map(\.path) == Self.lines(tracking).map { line in
            let rest = line.dropFirst().split(separator: " ", maxSplits: 1)[1]
            return rest.range(of: " (").map { String(rest[..<$0.lowerBound]) } ?? String(rest)
        })
    }

    @Test(arguments: repositories.filter { $0 != "large/monorepo" })
    func historyAgreesWithRevList(_ repository: String) async throws {
        let git = try Sandbox.git(repository)
        let hasHead = try await git.runAllowingFailure(.read(["rev-parse", "--verify", "--quiet", "HEAD"])).exitCode == 0
        let scope = ["--branches", "--remotes", "--tags"] + (hasHead ? ["HEAD"] : [])
        let expected = try await Sandbox.output(repository, ["rev-list", "--topo-order"] + scope)
        let pager = HistoryPager(git: git, pageSize: 10)
        var ids: [String] = []
        while let page = try await pager.nextPage() {
            ids += page.commits.map(\.id.rawValue)
            #expect(page.rows.count == page.commits.count)
            if page.isLast { break }
        }
        #expect(ids == Self.lines(expected))
    }
}
