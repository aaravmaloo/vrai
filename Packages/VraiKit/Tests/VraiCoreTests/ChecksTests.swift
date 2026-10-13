import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

struct ChecksParserTests {
    static let checkRuns = Data("""
    {"total_count": 4, "check_runs": [
      {"id": 11, "name": "test", "status": "completed", "conclusion": "failure", "started_at": "2026-10-11T12:00:00Z", "completed_at": "2026-10-11T12:03:10Z", "html_url": "https://github.com/a/b/runs/11", "check_suite": {"id": 900}, "output": {"title": "2 tests failed"}},
      {"id": 7, "name": "test", "status": "completed", "conclusion": "success", "check_suite": {"id": 900}},
      {"id": 12, "name": "build", "status": "in_progress", "conclusion": null, "started_at": "2026-10-11T12:00:00Z", "check_suite": {"id": 900}},
      {"id": 13, "name": "notarize", "status": "queued", "conclusion": null, "check_suite": {"id": 901}},
      {"id": 14, "name": "lint", "status": "completed", "conclusion": "skipped"}
    ]}
    """.utf8)

    static let workflowRuns = Data("""
    {"total_count": 3, "workflow_runs": [
      {"id": 5001, "name": "Tests", "check_suite_id": 900, "html_url": "https://github.com/a/b/actions/runs/5001"},
      {"id": 4000, "name": "Tests (old)", "check_suite_id": 900},
      {"id": 5002, "name": "Release", "check_suite_id": 901}
    ]}
    """.utf8)

    static let statuses = Data("""
    {"state": "pending", "statuses": [
      {"context": "vercel", "state": "success", "target_url": "https://vercel.com/a/b", "description": "Deployed", "created_at": "2026-10-11T12:00:00Z", "updated_at": "2026-10-11T12:01:00Z"},
      {"context": "vercel", "state": "pending"},
      {"context": "codecov", "state": "error"}
    ]}
    """.utf8)

    @Test func mapsStatusAndConclusion() {
        #expect(GitHubChecksParser.state(status: "queued", conclusion: nil) == .pending)
        #expect(GitHubChecksParser.state(status: "waiting", conclusion: nil) == .pending)
        #expect(GitHubChecksParser.state(status: "in_progress", conclusion: nil) == .running)
        #expect(GitHubChecksParser.state(status: "completed", conclusion: "success") == .passed)
        #expect(GitHubChecksParser.state(status: "completed", conclusion: "timed_out") == .failed)
        #expect(GitHubChecksParser.state(status: "completed", conclusion: "action_required") == .failed)
        #expect(GitHubChecksParser.state(status: "completed", conclusion: "cancelled") == .cancelled)
        #expect(GitHubChecksParser.state(status: "completed", conclusion: "neutral") == .skipped)
        #expect(GitHubChecksParser.state(status: "completed", conclusion: "skipped") == .skipped)
        #expect(GitHubChecksParser.statusState("error") == .failed)
        #expect(GitHubChecksParser.statusState("pending") == .running)
    }

    @Test func workflowRunsKeepTheNewestPerSuite() throws {
        let runs = try GitHubChecksParser.workflowRuns(Self.workflowRuns)
        #expect(runs[900]?.id == 5001)
        #expect(runs[900]?.name == "Tests")
        #expect(runs[901]?.name == "Release")
    }

    @Test func checkRunsKeepTheLatestAttemptAndNameTheWorkflow() throws {
        let workflows = try GitHubChecksParser.workflowRuns(Self.workflowRuns)
        let runs = try GitHubChecksParser.checkRuns(Self.checkRuns, workflows: workflows).sorted { $0.id < $1.id }
        #expect(runs.count == 4)
        let test = try #require(runs.first { $0.name == "test" })
        #expect(test.state == .failed)
        #expect(test.title == "Tests / test")
        #expect(test.runID == 5001)
        #expect(test.summary == "2 tests failed")
        #expect(test.duration(now: Date()) == 190)
        #expect(runs.first { $0.name == "notarize" }?.workflow == "Release")
        #expect(runs.first { $0.name == "lint" }?.title == "lint")
    }

    @Test func statusesKeepTheFirstPerContext() throws {
        let runs = try GitHubChecksParser.statuses(Self.statuses)
        #expect(runs.map(\.name) == ["vercel", "codecov"])
        #expect(runs[0].state == .passed)
        #expect(runs[0].summary == "Deployed")
        #expect(runs[1].state == .failed)
        #expect(runs[0].source == .status)
    }

    @Test func combinedStateFavorsFailuresThenWork() {
        #expect(CheckState.combined([]) == nil)
        #expect(CheckState.combined([.passed, .running, .failed]) == .failed)
        #expect(CheckState.combined([.passed, .pending, .running]) == .running)
        #expect(CheckState.combined([.passed, .pending]) == .pending)
        #expect(CheckState.combined([.passed, .cancelled]) == .cancelled)
        #expect(CheckState.combined([.skipped, .skipped]) == .skipped)
        #expect(CheckState.combined([.passed, .skipped]) == .passed)
    }

    @Test func commitChecksSummaries() throws {
        let workflows = try GitHubChecksParser.workflowRuns(Self.workflowRuns)
        let checks = CommitChecks(sha: "abc", runs: try GitHubChecksParser.checkRuns(Self.checkRuns, workflows: workflows))
        #expect(checks.state == .failed)
        #expect(!checks.isComplete)
        #expect(checks.finishedCount == 2)
        #expect(checks.rerunnable == [5001])
        #expect(checks.sorted.first?.state == .failed)
        #expect(checks.sorted.last?.state == .skipped)
    }
}

struct ChecksRepositoryTests {
    @Test func readsGitHubRemotes() throws {
        let https = try #require(ChecksRepository(url: "https://github.com/aaravmaloo/vrai.git", remote: "origin"))
        #expect(https.slug == "aaravmaloo/vrai")
        #expect(https.apiBase.absoluteString == "https://api.github.com")
        #expect(https.commitURL("abc").absoluteString == "https://github.com/aaravmaloo/vrai/commit/abc/checks")
        let scp = try #require(ChecksRepository(url: "git@github.com:aaravmaloo/vrai.git", remote: "origin"))
        #expect(scp.slug == "aaravmaloo/vrai")
        let ssh = try #require(ChecksRepository(url: "ssh://git@github.com/aaravmaloo/vrai", remote: "origin"))
        #expect(ssh.name == "vrai")
    }

    @Test func readsEnterpriseHosts() throws {
        let cloud = try #require(ChecksRepository(url: "https://acme.ghe.com/team/app.git", remote: "origin"))
        #expect(cloud.apiBase.absoluteString == "https://api.acme.ghe.com")
        let server = try #require(ChecksRepository(url: "https://github.acme.dev/team/app.git", remote: "origin"))
        #expect(server.apiBase.absoluteString == "https://github.acme.dev/api/v3")
    }

    @Test func ignoresOtherHostsAndShapes() {
        #expect(ChecksRepository(url: "https://gitlab.com/a/b.git", remote: "origin") == nil)
        #expect(ChecksRepository(url: "file:///tmp/remote.git", remote: "origin") == nil)
        #expect(ChecksRepository(url: "https://github.com/onlyowner", remote: "origin") == nil)
    }

    @Test func picksTheUpstreamRemoteFirst() {
        let remotes = [
            Remote(name: "fork", fetchURL: "git@github.com:me/vrai.git"),
            Remote(name: "origin", fetchURL: "https://github.com/team/vrai.git"),
            Remote(name: "mirror", fetchURL: "https://gitlab.com/team/vrai.git")
        ]
        #expect(ChecksRepository.pick(remotes: remotes, upstream: "fork/main")?.remote == "fork")
        #expect(ChecksRepository.pick(remotes: remotes, upstream: nil)?.remote == "origin")
        #expect(ChecksRepository.pick(remotes: remotes, upstream: "mirror/main")?.remote == "origin")
        #expect(ChecksRepository.pick(remotes: [remotes[2]], upstream: nil) == nil)
    }
}

actor FakeChecksClient: ChecksClient {
    var responses: [String: CommitChecks] = [:]
    var failure: ChecksError?
    var calls: [String] = []
    var reruns: [Int] = []
    let writable: Bool

    init(writable: Bool = true) {
        self.writable = writable
    }

    func set(_ sha: String, _ runs: [CheckRun]) {
        responses[sha] = CommitChecks(sha: sha, runs: runs)
    }

    func fail(_ error: ChecksError?) {
        failure = error
    }

    func checks(for sha: String, in repository: ChecksRepository) async throws -> CommitChecks {
        calls.append(sha)
        if let failure { throw failure }
        return responses[sha] ?? CommitChecks(sha: sha, runs: [])
    }

    func rerunFailed(runID: Int, in repository: ChecksRepository) async throws {
        reruns.append(runID)
    }

    func canWrite(_ repository: ChecksRepository) async -> Bool { writable }
}

@MainActor
final class TestClock {
    var now = Date(timeIntervalSince1970: 1_791_720_000)

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

@MainActor
struct ChecksStoreTests {
    static let main = OID(String(repeating: "a", count: 40))!
    static let feature = OID(String(repeating: "b", count: 40))!
    static let pushed = OID(String(repeating: "c", count: 40))!

    static func snapshot(tip: OID = main, remoteTip: OID? = nil, ahead: Int = 0, remoteURL: String = "git@github.com:team/vrai.git") -> RepositorySnapshot {
        RepositorySnapshot(
            root: URL(filePath: "/tmp/vrai"),
            gitDir: URL(filePath: "/tmp/vrai/.git"),
            commonDir: URL(filePath: "/tmp/vrai/.git"),
            isBare: false,
            isShallow: false,
            head: .branch("main"),
            headOID: tip,
            upstream: "origin/main",
            ahead: ahead,
            behind: 0,
            branches: [
                Branch(name: "main", tip: tip, upstream: "origin/main", ahead: ahead, isCurrent: true),
                Branch(name: "feature", tip: feature, upstream: "origin/feature")
            ],
            remoteBranches: [
                RemoteBranch(remote: "origin", name: "main", tip: remoteTip ?? tip),
                RemoteBranch(remote: "origin", name: "feature", tip: feature)
            ],
            remotes: [Remote(name: "origin", fetchURL: remoteURL, headBranch: "main")],
            tags: [],
            stashes: [],
            worktrees: [],
            submodules: [],
            working: [],
            conflicts: [],
            state: .clean,
            hooks: [],
            network: .ok,
            lastFetch: nil,
            gitVersion: GitVersion.minimum,
            branchColors: BranchColors(),
            hasCommitGraph: false
        )
    }

    static func run(_ name: String, _ state: CheckState, id: Int = 1) -> CheckRun {
        CheckRun(id: "check:" + name, name: name, state: state, runID: state == .failed ? id : nil)
    }

    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func tracksPushedBranchTipsAndFetchesThem() async {
        let client = FakeChecksClient()
        await client.set(Self.main.rawValue, [Self.run("test", .passed)])
        let clock = TestClock()
        let store = ChecksStore(client: client, now: { clock.now })
        store.update(Self.snapshot())
        await settle()
        #expect(store.repository?.slug == "team/vrai")
        #expect(store.canWrite)
        await store.tickOnce()
        #expect(store.state(of: Self.main) == .passed)
        #expect(store.results[Self.feature]?.runs.isEmpty == true)
        let calls = await client.calls
        #expect(Set(calls) == [Self.main.rawValue, Self.feature.rawValue])
    }

    @Test func finishedResultsAreNotFetchedAgain() async {
        let client = FakeChecksClient()
        await client.set(Self.main.rawValue, [Self.run("test", .passed)])
        await client.set(Self.feature.rawValue, [Self.run("test", .running)])
        let clock = TestClock()
        let store = ChecksStore(client: client, now: { clock.now })
        store.update(Self.snapshot())
        await settle()
        await store.tickOnce()
        clock.advance(ChecksStore.busyInterval + 1)
        await store.tickOnce()
        let calls = await client.calls
        #expect(calls.filter { $0 == Self.main.rawValue }.count == 1)
        #expect(calls.filter { $0 == Self.feature.rawValue }.count == 2)
    }

    @Test func unpushedTipsAreNotTracked() async {
        let client = FakeChecksClient()
        let store = ChecksStore(client: client, now: { Date() })
        store.update(Self.snapshot(tip: Self.pushed, remoteTip: Self.main, ahead: 2))
        await settle()
        #expect(store.tracked[Self.pushed] == nil)
        #expect(store.tracked[Self.main] == "origin/main")
        #expect(store.tracked[Self.feature] != nil)
    }

    @Test func anonymousTrackingStaysSmall() async {
        let client = FakeChecksClient(writable: false)
        let store = ChecksStore(client: client, now: { Date() })
        store.update(Self.snapshot())
        await settle()
        #expect(!store.canWrite)
        #expect(store.tracked.count <= ChecksStore.anonymousLimit)
    }

    @Test func nonGitHubRemotesTurnChecksOff() async {
        let store = ChecksStore(client: FakeChecksClient(), now: { Date() })
        store.update(Self.snapshot(remoteURL: "https://gitlab.com/team/vrai.git"))
        #expect(store.repository == nil)
        #expect(!store.isAvailable)
        #expect(store.states.isEmpty)
    }

    @Test func watchingAPushAnnouncesStartAndFinish() async {
        let client = FakeChecksClient()
        let clock = TestClock()
        let store = ChecksStore(client: client, now: { clock.now })
        var events: [ChecksEvent] = []
        store.onEvent = { events.append($0) }
        store.update(Self.snapshot())
        await settle()
        store.watch(Self.pushed, branch: "main")
        #expect(store.watching.contains(Self.pushed))
        await store.tickOnce()
        #expect(events.isEmpty)
        await client.set(Self.pushed.rawValue, [Self.run("test", .running), Self.run("build", .pending)])
        clock.advance(ChecksStore.watchedEmptyInterval + 1)
        await store.tickOnce()
        guard case .started(let branch, let checks)? = events.last else {
            Issue.record("expected a started event, got \(events)")
            return
        }
        #expect(branch == "main")
        #expect(checks.runs.count == 2)
        await client.set(Self.pushed.rawValue, [Self.run("test", .passed), Self.run("build", .running)])
        clock.advance(ChecksStore.busyInterval + 1)
        await store.tickOnce()
        guard case .progressed? = events.last else {
            Issue.record("expected a progress event, got \(events)")
            return
        }
        await client.set(Self.pushed.rawValue, [Self.run("test", .passed), Self.run("build", .failed, id: 77)])
        clock.advance(ChecksStore.busyInterval + 1)
        await store.tickOnce()
        guard case .finished(_, let done)? = events.last else {
            Issue.record("expected a finished event, got \(events)")
            return
        }
        #expect(done.state == .failed)
        #expect(!store.watching.contains(Self.pushed))
        #expect(events.count == 3)
    }

    @Test func watchGivesUpWhenNoChecksAppear() async {
        let client = FakeChecksClient()
        let clock = TestClock()
        let store = ChecksStore(client: client, now: { clock.now })
        store.update(Self.snapshot())
        await settle()
        store.watch(Self.pushed, branch: "main")
        await store.tickOnce()
        clock.advance(ChecksStore.watchGiveUp + 1)
        await store.tickOnce()
        #expect(!store.watching.contains(Self.pushed))
    }

    @Test func aNewPushedTipIsWatchedAutomatically() async {
        let client = FakeChecksClient()
        let store = ChecksStore(client: client, now: { Date() })
        store.update(Self.snapshot())
        await settle()
        #expect(store.watching.isEmpty)
        store.update(Self.snapshot(tip: Self.pushed))
        #expect(store.watching.contains(Self.pushed))
    }

    @Test func rateLimitsPausePolling() async {
        let client = FakeChecksClient()
        let clock = TestClock()
        await client.fail(ChecksError(.rateLimited(until: clock.now.addingTimeInterval(600))))
        let store = ChecksStore(client: client, now: { clock.now })
        store.update(Self.snapshot())
        await settle()
        await store.tickOnce()
        #expect(store.problem == .rateLimited(until: clock.now.addingTimeInterval(600)))
        let first = await client.calls.count
        #expect(first == 1)
        clock.advance(300)
        await store.tickOnce()
        #expect(await client.calls.count == first)
        await client.fail(nil)
        clock.advance(301)
        await store.tickOnce()
        #expect(await client.calls.count > first)
        #expect(store.problem == nil)
    }

    @Test func rerunMarksFailuresPendingAndWatches() async throws {
        let client = FakeChecksClient()
        await client.set(Self.main.rawValue, [Self.run("test", .failed, id: 42), Self.run("lint", .passed)])
        let store = ChecksStore(client: client, now: { Date() })
        store.update(Self.snapshot())
        await settle()
        await store.tickOnce()
        try await store.rerunFailed(Self.main, branch: "main")
        #expect(await client.reruns == [42])
        #expect(store.results[Self.main]?.state == .pending)
        #expect(store.watching.contains(Self.main))
    }

    @Test func disabledStoresReportNothing() async {
        let client = FakeChecksClient()
        await client.set(Self.main.rawValue, [Self.run("test", .passed)])
        let store = ChecksStore(client: client, now: { Date() })
        store.update(Self.snapshot())
        await settle()
        await store.tickOnce()
        store.enabled = false
        #expect(store.state(of: Self.main) == nil)
        #expect(store.states.isEmpty)
    }

    @Test func fixtureClientReadsRunsByPrefix() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vrai-checks-" + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "checks.json")
        try Data(#"{"aaaaaaa": {"runs": [{"name": "test", "workflow": "Tests", "state": "failed", "seconds": 95}, {"name": "build", "state": "running"}]}}"#.utf8).write(to: file)
        let client = FixtureChecksClient(file: file)
        let repository = ChecksRepository(host: "github.com", owner: "a", name: "b", remote: "origin")
        let checks = try await client.checks(for: Self.main.rawValue, in: repository)
        #expect(checks.runs.count == 2)
        #expect(checks.state == .failed)
        #expect(checks.runs[0].duration(now: Date()) == 95)
        #expect(checks.rerunnable == [1])
        let none = try await client.checks(for: Self.feature.rawValue, in: repository)
        #expect(none.runs.isEmpty)
    }
}

struct ChecksLiveTests {
    static let target = ProcessInfo.processInfo.environment["VRAI_LIVE_CHECKS"]

    @Test(.enabled(if: target != nil, "Set VRAI_LIVE_CHECKS=owner/repo@sha to read real checks from GitHub"))
    func readsRealChecksFromGitHub() async throws {
        let parts = try #require(Self.target?.split(separator: "@").map(String.init))
        let slug = parts[0].split(separator: "/").map(String.init)
        let repository = ChecksRepository(host: "github.com", owner: slug[0], name: slug[1], remote: "origin")
        let git = GitProcess(executable: try GitExecutable.discover(), workingDirectory: FileManager.default.temporaryDirectory, environment: .user())
        let client = GitHubChecksClient(token: GitHubToken.provider(git: git))
        #expect(await client.canWrite(repository))
        let checks = try await client.checks(for: parts[1], in: repository)
        for run in checks.sorted {
            print("live check:", run.title, run.state.rawValue, run.runID.map(String.init) ?? "-", run.url?.absoluteString ?? "-")
        }
        #expect(!checks.runs.isEmpty)
        let again = try await client.checks(for: parts[1], in: repository)
        #expect(again.runs.map(\.id).sorted() == checks.runs.map(\.id).sorted())
    }
}
