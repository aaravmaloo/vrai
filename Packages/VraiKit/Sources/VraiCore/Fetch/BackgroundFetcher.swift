import Foundation
import Observation
import VraiGit

@MainActor
@Observable
public final class BackgroundFetcher {
    public enum Outcome: Sendable, Hashable {
        case fetched(newCommits: [String: Int])
        case failed(GitErrorCode)
        case skipped
    }

    public let store: RepositoryStore
    public let notifier: any Notifier
    public var interval: Duration {
        didSet { if isRunning, oldValue != interval { restart() } }
    }
    public var notifyAboutNewCommits: Bool
    @ObservationIgnored public var isWindowKey: @MainActor () -> Bool
    @ObservationIgnored public var onFetched: (@MainActor ([String: Int]) -> Void)?
    public private(set) var lastOutcome: Outcome?
    public private(set) var lastRun: Date?
    public private(set) var isRunning = false
    public private(set) var fetchCount = 0
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var inFlight = false

    public init(store: RepositoryStore, notifier: any Notifier, interval: Duration = .seconds(15 * 60), notifyAboutNewCommits: Bool = true, isWindowKey: @escaping @MainActor () -> Bool = { false }) {
        self.store = store
        self.notifier = notifier
        self.interval = interval
        self.notifyAboutNewCommits = notifyAboutNewCommits
        self.isWindowKey = isWindowKey
    }

    public static func interval(minutes: Int) -> Duration {
        .seconds(max(1, minutes) * 60)
    }

    public func start(fetchImmediately: Bool = false) {
        guard loop == nil else { return }
        isRunning = true
        let interval = self.interval
        loop = Task { [weak self] in
            if fetchImmediately { await self?.fetchNow() }
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                guard let self, !Task.isCancelled else { return }
                await self.fetchNow()
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        isRunning = false
    }

    private func restart() {
        stop()
        start()
    }

    @discardableResult
    public func fetchNow() async -> Outcome {
        guard !inFlight else { return .skipped }
        inFlight = true
        defer { inFlight = false }
        let outcome = await run()
        lastOutcome = outcome
        lastRun = Date()
        fetchCount += 1
        return outcome
    }

    private func run() async -> Outcome {
        do {
            let remotes = try await store.remoteNames()
            guard !remotes.isEmpty else { return .skipped }
            let before = try await store.remoteTips()
            try await store.runNetwork(SyncCommands.backgroundFetch(), background: true, progress: nil)
            let after = try await store.remoteTips()
            let result = try await store.fetchResult(remotes: remotes, before: before, after: after)
            let upstreams = try await upstreamNames()
            let counts = result.newCommits.filter { upstreams.contains($0.key) && $0.value > 0 }
            try? await store.refresh()
            if !counts.isEmpty {
                onFetched?(counts)
                if notifyAboutNewCommits, !isWindowKey() {
                    await notifier.post(notification(for: counts))
                }
            }
            return .fetched(newCommits: counts)
        } catch let error as GitError {
            return .failed(error.code)
        } catch {
            return .failed(.cancelled)
        }
    }

    private func upstreamNames() async throws -> Set<String> {
        let output = try await store.git.run(.read(["for-each-ref", "--format=%(upstream:short)", "refs/heads"]), background: true).output
        return Set(output.split(separator: "\n").map(String.init).filter { !$0.isEmpty })
    }

    private func notification(for counts: [String: Int]) -> FetchNotification {
        let root = store.snapshot?.root ?? store.git.workingDirectory
        let name = root.lastPathComponent
        return FetchNotification(repository: root.path(percentEncoded: false), title: name, body: FetchNotification.lines(for: counts).joined(separator: "\n"), newCommits: counts)
    }
}
