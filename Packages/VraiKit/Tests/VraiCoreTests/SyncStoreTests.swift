import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct SyncStoreTests {
    func pushCommits(_ copy: ScenarioCopy, branch: String, count: Int, remote: String = "origin") async throws -> String {
        let other = try await copy.clone(remote, branch: branch)
        var last = ""
        for index in 0..<count {
            last = try await copy.commit(in: other, file: "upstream-\(index).txt", contents: "\(index)\n", message: "Upstream \(index)")
        }
        _ = try await copy.git(["push", "-q", "origin", branch], in: other)
        return last
    }

    @Test func fetchCountsNewCommitsAndPrunes() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let store = try await copy.store()
        let tip = try await pushCommits(copy, branch: "main", count: 2)
        let main = try #require(try await copy.remoteTip("origin", "refs/heads/main"))
        _ = try await copy.git(["update-ref", "refs/heads/doomed", main], in: copy.remote("origin"))
        try await store.fetch(remote: "origin")
        #expect(try await copy.tip("refs/remotes/origin/doomed") == main)
        _ = try await copy.git(["update-ref", "-d", "refs/heads/doomed"], in: copy.remote("origin"))

        let progress = Recorder<GitProgress>()
        let result = try await store.fetch(remote: "origin", prune: true, progress: { item in Task { await progress.append(item) } })
        #expect(result.newCommits.isEmpty)
        #expect(result.prunedRefs == ["origin/doomed"])
        #expect(try await copy.tip("refs/remotes/origin/doomed") == nil)
        #expect(try await copy.tip("refs/remotes/origin/main") == tip)
        #expect(result.summary.message == "Everything is up to date")
        #expect(result.summary.detail == "Fetched origin.")
        #expect(store.snapshot?.network == .ok)
        #expect(store.snapshot?.lastFetch != nil)
    }

    @Test func fetchReportsNewCommitsPerRemoteBranch() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let store = try await copy.store()
        let staleStaging = try #require(try await copy.tip("refs/remotes/origin/feature/line-staging"))
        _ = try await pushCommits(copy, branch: "main", count: 2)
        let staging = try await pushCommits(copy, branch: "feature/line-staging", count: 1)
        let expectedStaging = Int(try await copy.git(["rev-list", "--count", staleStaging + ".." + staging], in: copy.remote("origin"))) ?? -1
        let progress = Recorder<GitProgress>()
        let result = try await store.fetch(remote: "origin", progress: { item in Task { await progress.append(item) } })
        #expect(result.newCommits["origin/main"] == 2)
        #expect(result.newCommits["origin/feature/line-staging"] == expectedStaging)
        #expect(result.total == 2 + expectedStaging)
        #expect(result.summary.message == "Fetched \(2 + expectedStaging) new commits")
        #expect(result.summary.detail == "origin/feature/line-staging, origin/main")
        #expect(try await waitFor(.seconds(2)) { await !progress.values.isEmpty })
        #expect(await progress.values.contains { $0.phase.lowercased().contains("objects") })
        #expect(store.snapshot?.branches.first { $0.name == "main" }?.behind == 3)
    }

    @Test func fetchAllTagsDepthAndUnshallow() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let store = try await copy.store()
        let other = try await copy.clone("origin", branch: "main")
        _ = try await copy.git(["tag", "loose-tag", "HEAD~2"], in: other)
        _ = try await copy.git(["push", "-q", "origin", "refs/tags/loose-tag"], in: other)
        let all = try await store.fetch(all: true, tags: true)
        #expect(all.remotes == ["mira", "origin"])
        let again = try await store.fetch(all: true)
        #expect(again.total == 0)
        #expect(again.summary.detail == "Fetched mira and origin.")
        #expect(try await copy.tip("refs/tags/loose-tag") != nil)
        #expect(store.fetchCommand(all: true, prune: true, tags: true).display == "git fetch --all --prune --tags --progress")

        try await store.fetch(remote: "mira", depth: 1)
        #expect(try await copy.git(["rev-parse", "--is-shallow-repository"]) == "true")
        #expect(store.snapshot?.isShallow == true)
        try await store.fetch(remote: "mira", unshallow: true)
        #expect(try await copy.git(["rev-parse", "--is-shallow-repository"]) == "false")
        await expectCode("remoteNotFound") { try await store.fetch(remote: "nope") }
    }

    @Test func fetchWithoutRemotes() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        _ = try await copy.git(["remote", "remove", "origin"])
        _ = try await copy.git(["remote", "remove", "mira"])
        let store = try await copy.store()
        await expectCode("remoteNotFound") { try await store.fetch() }
    }

    @Test func operationHandleStreamsProgressAndCancels() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let store = try await copy.store()
        _ = try await pushCommits(copy, branch: "main", count: 3)
        let operation = store.fetchOperation(remote: "origin")
        var seen: [GitProgress] = []
        for await item in operation.progress { seen.append(item) }
        let result = try await operation.value
        #expect(result.newCommits["origin/main"] == 3)
        #expect(!seen.isEmpty)

        let silent = try SilentServer()
        defer { silent.close() }
        _ = try await copy.git(["remote", "add", "silent", "http://127.0.0.1:\(silent.port)/never.git"])
        let hanging = store.fetchOperation(remote: "silent")
        try await Task.sleep(for: .milliseconds(400))
        let clock = ContinuousClock()
        let started = clock.now
        hanging.cancel()
        await expectCode("cancelled") { _ = try await hanging.value }
        #expect(clock.now - started < .seconds(4))
        #expect(store.busy.isEmpty)
    }

    @Test func pullFastForwardsAndRecordsUndo() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        try await copy.clean()
        _ = try await copy.git(["switch", "-q", "main"])
        let before = try #require(try await copy.tip("HEAD"))
        let store = try await copy.store()
        #expect(store.pullCommand(mode: .merge).display == "git pull --no-rebase --progress")
        let result = try await store.pull(mode: .merge)
        let upstream = try await copy.tip("refs/remotes/origin/main")
        #expect(try await copy.tip("HEAD") == upstream)
        #expect(result.pulled == 1)
        #expect(result.ahead == 0)
        #expect(result.summary.message == "Pulled 1 commit from origin/main")
        #expect(result.summary.detail == "Fast-forwarded main.")
        let entry = try #require(await store.undo.entries.first)
        #expect(entry.kind == .pull)
        #expect(entry.refsBefore == ["refs/heads/main": OID(before)!])
        #expect(entry.label == "Pulled 1 commit into main")

        let again = try await store.pull(mode: .fastForwardOnly)
        #expect(again.upToDate)
        #expect(again.summary.message == "Already up to date")
        #expect(await store.undo.entries.count == 1)
    }

    @Test func pullRebasePutsLocalCommitsOnTop() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        try await copy.clean()
        let store = try await copy.store()
        let result = try await store.pull(mode: .rebase)
        #expect(try await copy.git(["rev-list", "--count", "refs/remotes/origin/feature/graph-renderer..HEAD"]) == "2")
        #expect(try await copy.git(["rev-list", "--count", "HEAD..refs/remotes/origin/feature/graph-renderer"]) == "0")
        #expect(result.pulled == 1)
        #expect(result.ahead == 2)
        #expect(result.summary.detail == "Your 2 commits now sit on top.")
        #expect(store.snapshot?.state == .clean)
    }

    @Test func pullMergeCreatesAMergeCommit() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        try await copy.clean()
        try copy.setHook("commit-msg", nil)
        let store = try await copy.store()
        let result = try await store.pull(mode: .merge)
        #expect(try await copy.git(["rev-list", "--count", "--merges", "-1", "HEAD^!"]) == "1")
        #expect(result.summary.detail == "Merged with your 2 commits.")
    }

    @Test func pullErrors() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let store = try await copy.store()
        await expectCode("localChangesWouldBeOverwritten") { try await store.pull(mode: .rebase) }
        try await copy.clean()
        await expectCode("divergentBranches") { try await store.pull(mode: .fastForwardOnly) }
        _ = try await copy.git(["switch", "-q", "-c", "lonely"])
        await expectCode("noUpstream") { try await store.pull(mode: .merge) }
        _ = try await copy.git(["switch", "-q", "--detach", "HEAD"])
        await expectCode("noUpstream") { try await store.pull(mode: .merge) }
        #expect(await store.undo.entries.isEmpty)
    }

    @Test func pullWithAutostashKeepsLocalChanges() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        try await copy.clean()
        let file = copy.repository.appending(path: "README.md")
        let original = try String(contentsOf: file, encoding: .utf8)
        try Data((original + "\nLocal note\n").utf8).write(to: file)
        let store = try await copy.store()
        try await store.pull(mode: .rebase, autostash: true)
        #expect(try await copy.git(["rev-list", "--count", "HEAD..refs/remotes/origin/feature/graph-renderer"]) == "0")
        #expect(try String(contentsOf: file, encoding: .utf8).hasSuffix("Local note\n"))
    }

    @Test func pullReportsConflicts() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        try await copy.clean()
        try copy.setHook("commit-msg", nil)
        _ = try await copy.git(["switch", "-q", "main"])
        _ = try await copy.git(["merge", "-q", "--ff-only", "origin/main"])
        let other = try await copy.clone("origin", branch: "main")
        _ = try await copy.commit(in: other, file: "README.md", contents: "theirs\n", message: "Theirs")
        _ = try await copy.git(["push", "-q", "origin", "main"], in: other)
        _ = try await copy.commit(in: copy.repository, file: "README.md", contents: "ours\n", message: "Ours")
        let store = try await copy.store()
        let error = await expectCode("conflicts") { try await store.pull(mode: .merge) }
        #expect(error?.code == .conflicts(paths: ["README.md"]))
        if case .merging? = store.snapshot?.state {} else { Issue.record("expected a merging state, got \(String(describing: store.snapshot?.state))") }
    }

    @Test func pushPublishesANewBranch() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        try await copy.clean()
        _ = try await copy.git(["switch", "-q", "-c", "topic", "main"])
        let tip = try await copy.commit(in: copy.repository, file: "topic.txt", contents: "topic\n", message: "Topic")
        let store = try await copy.store()
        await expectCode("noUpstream") { try await store.push() }
        #expect(try await store.pushCommand(remote: "origin").display == "git push -u --progress origin topic")
        let result = try await store.push(remote: "origin")
        #expect(try await copy.remoteTip("origin", "refs/heads/topic") == tip)
        #expect(try await copy.config("branch.topic.merge") == "refs/heads/topic")
        #expect(result.publishedUpstream)
        #expect(result.pushed == 1)
        #expect(result.summary.message == "Pushed 1 commit to origin/topic")
        #expect(result.summary.detail == "Set origin/topic as the upstream.")

        _ = try await copy.commit(in: copy.repository, file: "topic2.txt", contents: "two\n", message: "Topic two")
        _ = try await copy.commit(in: copy.repository, file: "topic3.txt", contents: "three\n", message: "Topic three")
        _ = try await copy.git(["tag", "-a", "-m", "Topic tag", "topic-tag"])
        let second = try await store.push(tags: true)
        #expect(second.pushed == 2)
        #expect(second.summary.detail == nil)
        #expect(try await copy.remoteTip("origin", "refs/tags/topic-tag") == copy.tip("HEAD"))
        let third = try await store.push()
        #expect(third.upToDate)
    }

    @Test func pushRejectedCountsWhatTheRemoteHas() async throws {
        let copy = try ScenarioCopy.make("push-rejected")
        defer { copy.remove() }
        let store = try await copy.store()
        let local = try #require(try await copy.tip("HEAD"))
        let error = await expectCode("pushRejected") { try await store.push() }
        #expect(error?.code == .pushRejected(behind: 2))
        #expect(error?.remoteURL?.hasSuffix("/push-rejected/remotes/origin.git") == true)
        #expect(store.snapshot?.currentBranch?.behind == 2)
        #expect(try await copy.remoteTip("origin", "refs/heads/feature/graph-renderer") != local)

        #expect(try await store.pushCommand(force: .withLease).risk == .rewrites)
        let result = try await store.push(force: .withLease)
        #expect(try await copy.remoteTip("origin", "refs/heads/feature/graph-renderer") == local)
        #expect(result.summary.message == "Force pushed 2 commits to origin/feature/graph-renderer")
        #expect(result.summary.detail == "Replaced the remote branch; nobody else had pushed to it.")
        #expect(store.snapshot?.currentBranch?.behind == 0)
    }

    @Test func forcePushAndHooks() async throws {
        let copy = try ScenarioCopy.make("push-rejected")
        defer { copy.remove() }
        let store = try await copy.store()
        let local = try #require(try await copy.tip("HEAD"))
        try copy.setHook("pre-push", "#!/bin/sh\necho 'pre-push: 3 tests failed' >&2\nexit 1\n")
        let hook = await expectCode("hookFailed") { try await store.push(force: .force) }
        #expect(hook?.code == .hookFailed(name: "pre-push", output: "pre-push: 3 tests failed"))
        #expect(try await store.pushCommand(force: .force, noVerify: true).display == "git push --force --no-verify --progress origin feature/graph-renderer")
        #expect(try await store.pushCommand(force: .force).risk == .destructive)
        try await store.push(force: .force, noVerify: true)
        #expect(try await copy.remoteTip("origin", "refs/heads/feature/graph-renderer") == local)
    }

    @Test func pushOptionsReachTheRemote() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        try await copy.clean()
        let bare = copy.remote("origin")
        _ = try await copy.git(["config", "receive.advertisePushOptions", "true"], in: bare)
        let log = copy.root.appending(path: "push-options.txt")
        try copy.setHook("pre-receive", "#!/bin/sh\necho \"$GIT_PUSH_OPTION_COUNT $GIT_PUSH_OPTION_0 $GIT_PUSH_OPTION_1\" > '\(log.path(percentEncoded: false))'\n", in: bare.appending(path: "hooks"))
        _ = try await copy.git(["switch", "-q", "-c", "options", "main"])
        _ = try await copy.commit(in: copy.repository, file: "options.txt", contents: "o\n", message: "Options")
        let store = try await copy.store()
        try await store.push(remote: "origin", pushOptions: ["ci.skip", "merge_request.create"])
        #expect(try String(contentsOf: log, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) == "2 ci.skip merge_request.create")
    }

    @Test func pushToAProtectedBranch() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        try await copy.clean()
        try copy.setHook("pre-receive", "#!/bin/sh\necho 'GH006: Protected branch update failed for refs/heads/main.' >&2\nexit 1\n", in: copy.remote("origin").appending(path: "hooks"))
        _ = try await copy.git(["switch", "-q", "main"])
        _ = try await copy.git(["merge", "-q", "--ff-only", "origin/main"])
        _ = try await copy.commit(in: copy.repository, file: "main.txt", contents: "m\n", message: "Main change")
        let store = try await copy.store()
        await expectCode("protectedBranch") { try await store.push() }
    }

    @Test func pushUsesTheUpstreamBranchName() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        try await copy.clean()
        _ = try await copy.git(["switch", "-q", "mira/spike/metal-graph"])
        let tip = try await copy.commit(in: copy.repository, file: "metal.txt", contents: "metal\n", message: "Metal")
        let store = try await copy.store()
        #expect(try await store.pushCommand().display == "git push --progress mira refs/heads/mira/spike/metal-graph:refs/heads/spike/metal-graph")
        let result = try await store.push()
        #expect(try await copy.remoteTip("mira", "refs/heads/spike/metal-graph") == tip)
        #expect(try await copy.remoteTip("mira", "refs/heads/mira/spike/metal-graph") == nil)
        #expect(result.summary.message == "Pushed 1 commit to mira/spike/metal-graph")
    }

    @Test func deleteARemoteBranch() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let store = try await copy.store()
        let tip = try #require(try await copy.tip("refs/remotes/origin/feature/line-staging"))
        let summary = try await store.deleteRemoteBranch(remote: "origin", name: "feature/line-staging")
        #expect(try await copy.remoteTip("origin", "refs/heads/feature/line-staging") == nil)
        #expect(try await copy.tip("refs/remotes/origin/feature/line-staging") == nil)
        #expect(summary.message == "Deleted feature/line-staging on origin")
        #expect(summary.detail == "It pointed at \(tip.prefix(7)).")
        #expect(store.snapshot?.remoteBranches.contains { $0.fullName == "origin/feature/line-staging" } == false)
        await expectCode("refNotFound") { try await store.deleteRemoteBranch(remote: "origin", name: "nope") }
    }

    @Test func offlineScenarioReportsTheHost() async throws {
        let copy = try ScenarioCopy.make("offline")
        defer { copy.remove() }
        let store = try await copy.store()
        let fetch = await expectCode("networkUnreachable") { try await store.fetch() }
        #expect(fetch?.code == .networkUnreachable(host: "127.0.0.1"))
        #expect(fetch?.remoteURL == "https://127.0.0.1:9/vrai.git")
        #expect(store.snapshot?.network == .offline(host: "127.0.0.1"))
        await expectCode("networkUnreachable") { try await store.pull(mode: .merge) }
        await expectCode("networkUnreachable") { try await store.push(force: .withLease) }
        await expectCode("networkUnreachable") { try await store.deleteRemoteBranch(remote: "origin", name: "feature/line-staging") }
        await expectCode("networkUnreachable") { try await store.pushTag(name: "v0.9.1") }
        #expect(store.snapshot?.network == .offline(host: "127.0.0.1"))
        try await store.fetch(remote: "mira")
        #expect(store.snapshot?.network == .ok)
    }

    @Test func authScenarioReportsTheHost() async throws {
        let copy = try ScenarioCopy.make("auth")
        defer { copy.remove() }
        let port = try AuthServer.port(in: copy)
        let environment = try copy.isolatedEnvironment(seed: "http://avery:vrai_expired_token@127.0.0.1%3a\(port)\n")
        let store = try await copy.store(environment: environment)
        try await AuthServer.acquire(port: port)
        defer { AuthServer.release() }
        let fetch = await expectCode("authFailed") { try await store.fetch() }
        #expect(fetch?.code == .authFailed(host: "127.0.0.1"))
        #expect(fetch?.remoteURL == "http://127.0.0.1:\(port)/vrai.git")
        #expect(fetch?.remoteURL.flatMap { RemoteURL($0)?.repositoryPath } == "vrai")
        #expect(store.snapshot?.network == .authFailed(host: "127.0.0.1"))
        await expectCode("authFailed") { try await store.pull(mode: .merge) }
        await expectCode("authFailed") { try await store.push(force: .withLease) }
        await expectCode("authFailed") { try await store.pushTag(name: "v0.9.1") }
        await expectCode("authFailed") { try await store.deleteBranch(name: "feature/line-staging", force: true, alsoOnRemote: true) }
        #expect(try await copy.tip("refs/heads/feature/line-staging") == nil)
        #expect(await store.undo.entries.first?.kind == .branchDelete)
    }
}

final class SilentServer: @unchecked Sendable {
    let fd: Int32
    let port: Int

    init() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        self.fd = fd
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 8) == 0 else { throw GitError(.unknown(exit: errno, stderr: "listen")) }
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        port = Int(UInt16(bigEndian: actual.sin_port))
    }

    func close() {
        Darwin.close(fd)
    }
}
