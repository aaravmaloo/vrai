import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct BackgroundFetcherTests {
    func pushToOrigin(_ copy: ScenarioCopy, branch: String, count: Int) async throws {
        let other = try await copy.clone("origin", branch: branch)
        for index in 0..<count {
            _ = try await copy.commit(in: other, file: "bg-\(UUID().uuidString.prefix(8)).txt", contents: "\(index)\n", message: "Background \(index)")
        }
        _ = try await copy.git(["push", "-q", "origin", branch], in: other)
    }

    @Test func notifiesAboutNewCommitsOnUpstreams() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        _ = try await copy.git(["fetch", "-q", "origin"])
        let console = ConsoleRecorder()
        let store = try await copy.store(observer: console.observer)
        let posted = Recorder<FetchNotification>()
        let fetcher = BackgroundFetcher(store: store, notifier: ClosureNotifier { await posted.append($0) }, interval: .seconds(3600))
        var events: [[String: Int]] = []
        fetcher.onFetched = { events.append($0) }
        try await pushToOrigin(copy, branch: "main", count: 2)
        _ = try await copy.git(["update-ref", "refs/heads/not-tracked", try #require(try await copy.remoteTip("origin", "refs/heads/main"))], in: copy.remote("origin"))

        let outcome = await fetcher.fetchNow()
        #expect(outcome == .fetched(newCommits: ["origin/main": 2]))
        #expect(events == [["origin/main": 2]])
        let notes = await posted.values
        #expect(notes.count == 1)
        #expect(notes.first?.body == "2 new commits on origin/main")
        #expect(notes.first?.title == "vrai")
        #expect(try await copy.tip("refs/remotes/origin/not-tracked") != nil)
        #expect(store.snapshot?.branches.first { $0.name == "main" }?.behind == 3)
        let fetches = console.entries.filter { $0.command == "git fetch --all" }
        #expect(fetches.count == 1)
        #expect(!fetches.contains { !$0.background })
        #expect(!console.entries.contains { !$0.background })

        #expect(await fetcher.fetchNow() == .fetched(newCommits: [:]))
        #expect(await posted.values.count == 1)
    }

    @Test func staysQuietWhenTheWindowIsKeyOrNotificationsAreOff() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        _ = try await copy.git(["fetch", "-q", "origin"])
        let store = try await copy.store()
        let posted = Recorder<FetchNotification>()
        let fetcher = BackgroundFetcher(store: store, notifier: ClosureNotifier { await posted.append($0) }, isWindowKey: { true })
        try await pushToOrigin(copy, branch: "main", count: 1)
        #expect(await fetcher.fetchNow() == .fetched(newCommits: ["origin/main": 1]))
        fetcher.isWindowKey = { false }
        fetcher.notifyAboutNewCommits = false
        try await pushToOrigin(copy, branch: "main", count: 1)
        #expect(await fetcher.fetchNow() == .fetched(newCommits: ["origin/main": 1]))
        #expect(await posted.values.isEmpty)
    }

    @Test func prunesOnlyRemotesConfiguredToPrune() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let originTip = try #require(try await copy.remoteTip("origin", "refs/heads/main"))
        let miraTip = try #require(try await copy.remoteTip("mira", "refs/heads/spike/metal-graph"))
        _ = try await copy.git(["update-ref", "refs/heads/gone", originTip], in: copy.remote("origin"))
        _ = try await copy.git(["update-ref", "refs/heads/gone", miraTip], in: copy.remote("mira"))
        let store = try await copy.store()
        let fetcher = BackgroundFetcher(store: store, notifier: ClosureNotifier { _ in })
        _ = await fetcher.fetchNow()
        #expect(try await copy.tip("refs/remotes/origin/gone") == originTip)
        #expect(try await copy.tip("refs/remotes/mira/gone") == miraTip)
        _ = try await copy.git(["update-ref", "-d", "refs/heads/gone"], in: copy.remote("origin"))
        _ = try await copy.git(["update-ref", "-d", "refs/heads/gone"], in: copy.remote("mira"))
        _ = await fetcher.fetchNow()
        #expect(try await copy.tip("refs/remotes/origin/gone") == nil)
        #expect(try await copy.tip("refs/remotes/mira/gone") == miraTip)
    }

    @Test func runsOnAnInterval() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let store = try await copy.store()
        let fetcher = BackgroundFetcher(store: store, notifier: ClosureNotifier { _ in }, interval: .milliseconds(150))
        fetcher.start()
        #expect(fetcher.isRunning)
        #expect(try await waitFor(.seconds(10)) { await MainActor.run { fetcher.fetchCount >= 2 } })
        fetcher.stop()
        let settled = fetcher.fetchCount
        try await Task.sleep(for: .milliseconds(500))
        #expect(fetcher.fetchCount <= settled + 1)
        #expect(!fetcher.isRunning)
        #expect(BackgroundFetcher.interval(minutes: 15) == .seconds(900))
    }

    @Test func failuresOnlySetTheQuietNetworkBadge() async throws {
        let copy = try ScenarioCopy.make("offline")
        defer { copy.remove() }
        let store = try await copy.store()
        let posted = Recorder<FetchNotification>()
        let fetcher = BackgroundFetcher(store: store, notifier: ClosureNotifier { await posted.append($0) })
        let outcome = await fetcher.fetchNow()
        #expect(outcome == .failed(.networkUnreachable(host: "127.0.0.1")))
        #expect(store.snapshot?.network == .offline(host: "127.0.0.1"))
        #expect(await posted.values.isEmpty)
        #expect(store.busy.isEmpty)

        let auth = try ScenarioCopy.make("auth")
        defer { auth.remove() }
        let port = try AuthServer.port(in: auth)
        let authStore = try await auth.store(environment: try auth.isolatedEnvironment(seed: "http://avery:vrai_expired_token@127.0.0.1%3a\(port)\n"))
        try await AuthServer.acquire(port: port)
        defer { AuthServer.release() }
        let authOutcome = await BackgroundFetcher(store: authStore, notifier: ClosureNotifier { _ in }).fetchNow()
        #expect(authOutcome == .failed(.authFailed(host: "127.0.0.1")))
        #expect(authStore.snapshot?.network == .authFailed(host: "127.0.0.1"))
    }
}
