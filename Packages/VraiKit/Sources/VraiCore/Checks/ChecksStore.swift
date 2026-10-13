import Foundation
import Observation
import VraiGit

public enum ChecksEvent: Sendable, Hashable {
    case started(branch: String, checks: CommitChecks)
    case progressed(branch: String, checks: CommitChecks)
    case finished(branch: String, checks: CommitChecks)
}

@MainActor
@Observable
public final class ChecksStore {
    struct Watch {
        var branch: String
        var since: Date
        var announced = false
    }

    public private(set) var results: [OID: CommitChecks] = [:]
    public private(set) var repository: ChecksRepository?
    public private(set) var problem: ChecksProblem?
    public private(set) var canWrite = false
    public private(set) var watching: Set<OID> = []
    public var active = true

    @ObservationIgnored public let client: (any ChecksClient)?
    @ObservationIgnored public var onEvent: (@MainActor (ChecksEvent) -> Void)?
    @ObservationIgnored let fallback: ChecksRepository?
    @ObservationIgnored let now: @MainActor () -> Date
    @ObservationIgnored var tracked: [OID: String] = [:]
    @ObservationIgnored var requested: [OID] = []
    @ObservationIgnored var watches: [OID: Watch] = [:]
    @ObservationIgnored var attempts: [OID: Date] = [:]
    @ObservationIgnored var inFlight: Set<OID> = []
    @ObservationIgnored var pausedUntil: Date?
    @ObservationIgnored var lastHead: (branch: String, tip: OID)?
    @ObservationIgnored var loop: Task<Void, Never>?
    @ObservationIgnored var configured = false
    @ObservationIgnored public var enabled = true {
        didSet {
            guard enabled != oldValue else { return }
            if enabled { start() } else { stop() }
        }
    }

    public static let tick: Duration = .seconds(5)
    public static let busyInterval: TimeInterval = 12
    public static let backgroundInterval: TimeInterval = 30
    public static let watchedEmptyInterval: TimeInterval = 8
    public static let emptyInterval: TimeInterval = 300
    public static let watchGiveUp: TimeInterval = 180
    public static let trackedLimit = 12
    public static let anonymousLimit = 3
    public static let requestedLimit = 24

    public init(client: (any ChecksClient)?, fallback: ChecksRepository? = nil, now: @escaping @MainActor () -> Date = { Date() }) {
        self.client = client
        self.fallback = fallback
        self.now = now
    }

    public var isAvailable: Bool { client != nil && repository != nil && enabled }

    public func state(of id: OID) -> CheckState? {
        guard isAvailable else { return nil }
        return results[id]?.state
    }

    public var states: [OID: CheckState] {
        guard isAvailable else { return [:] }
        var map: [OID: CheckState] = [:]
        for (id, checks) in results {
            if let state = checks.state { map[id] = state }
        }
        return map
    }

    public func start() {
        guard loop == nil, client != nil, enabled else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tickOnce()
                try? await Task.sleep(for: Self.tick)
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    public func update(_ snapshot: RepositorySnapshot) {
        let next = ChecksRepository.pick(remotes: snapshot.remotes, upstream: snapshot.currentBranch?.upstream) ?? (snapshot.remotes.isEmpty ? nil : fallback)
        if next != repository {
            repository = next
            results = [:]
            attempts = [:]
            watches = [:]
            watching = []
            problem = nil
            lastHead = nil
            configured = false
            if let next, let client {
                Task { [weak self] in
                    let write = await client.canWrite(next)
                    guard let self, self.repository == next else { return }
                    self.canWrite = write
                    self.retrack(snapshot)
                }
            }
        }
        retrack(snapshot)
    }

    func retrack(_ snapshot: RepositorySnapshot) {
        guard let repository else {
            tracked = [:]
            return
        }
        var order: [(OID, String)] = []
        func add(_ id: OID?, _ label: String) {
            guard let id, !order.contains(where: { $0.0 == id }) else { return }
            order.append((id, label))
        }
        let remoteTips = Dictionary(snapshot.remoteBranches.map { ($0.fullName, $0.tip) }, uniquingKeysWith: { first, _ in first })
        if let current = snapshot.currentBranch, let upstream = current.upstream, !current.upstreamGone {
            if current.ahead == 0 { add(current.tip, current.name) }
            add(remoteTips[upstream], upstream)
        }
        let remote = repository.remote
        let head = snapshot.remotes.first { $0.name == remote }?.headBranch
        for name in [head, "main", "master", "develop"].compactMap({ $0 }) {
            add(remoteTips[remote + "/" + name], remote + "/" + name)
        }
        for branch in snapshot.branches where branch.upstream != nil && !branch.upstreamGone && branch.ahead == 0 {
            add(branch.tip, branch.name)
        }
        for branch in snapshot.remoteBranches where branch.remote == remote && branch.name != "HEAD" {
            add(branch.tip, branch.fullName)
        }
        let limit = canWrite ? Self.trackedLimit : Self.anonymousLimit
        tracked = Dictionary(order.prefix(limit).map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first })
        if let current = snapshot.currentBranch, current.upstream != nil, current.ahead == 0, !current.upstreamGone {
            if configured, let lastHead, lastHead.tip != current.tip, results[current.tip]?.isComplete != true {
                watch(current.tip, branch: current.name)
            }
            lastHead = (current.name, current.tip)
        }
        configured = true
    }

    public func watch(_ id: OID, branch: String) {
        guard client != nil, repository != nil else { return }
        if watches[id] == nil { watches[id] = Watch(branch: branch, since: now()) }
        watching.insert(id)
        attempts[id] = nil
    }

    public func request(_ id: OID) {
        guard client != nil, repository != nil, tracked[id] == nil else { return }
        requested.removeAll { $0 == id }
        requested.append(id)
        if requested.count > Self.requestedLimit { requested.removeFirst(requested.count - Self.requestedLimit) }
    }

    public func refresh(_ id: OID) async {
        attempts[id] = nil
        await fetch(id)
    }

    func due(at date: Date) -> [OID] {
        var ids: [OID] = []
        var seen: Set<OID> = []
        let candidates = Array(watches.keys) + Array(tracked.keys) + requested.reversed()
        for id in candidates where seen.insert(id).inserted && !inFlight.contains(id) {
            let last = attempts[id]
            let result = results[id]
            let interval: TimeInterval
            if let result, result.isComplete {
                continue
            } else if let result, !result.runs.isEmpty {
                interval = active || watches[id] != nil ? Self.busyInterval : Self.backgroundInterval
            } else if watches[id] != nil {
                interval = Self.watchedEmptyInterval
            } else if result != nil {
                interval = Self.emptyInterval
            } else {
                interval = 0
            }
            if let last, date.timeIntervalSince(last) < interval { continue }
            ids.append(id)
        }
        return Array(ids.prefix(6))
    }

    public func tickOnce() async {
        guard enabled, client != nil, repository != nil else { return }
        let date = now()
        if let pausedUntil, pausedUntil > date { return }
        pausedUntil = nil
        for id in due(at: date) {
            await fetch(id)
            if pausedUntil != nil { break }
        }
    }

    func fetch(_ id: OID) async {
        guard let client, let repository, !inFlight.contains(id) else { return }
        inFlight.insert(id)
        attempts[id] = now()
        defer { inFlight.remove(id) }
        do {
            let checks = try await client.checks(for: id.rawValue, in: repository)
            guard self.repository == repository else { return }
            problem = nil
            apply(checks, to: id)
        } catch let error as ChecksError {
            problem = error.problem
            switch error.problem {
            case .rateLimited(let until):
                pausedUntil = until ?? now().addingTimeInterval(300)
            case .offline:
                pausedUntil = now().addingTimeInterval(60)
            case .signedOut:
                if results[id] == nil { results[id] = CommitChecks(sha: id.rawValue, runs: [], url: repository.commitURL(id.rawValue), fetchedAt: now()) }
                pausedUntil = now().addingTimeInterval(300)
            case .server:
                pausedUntil = now().addingTimeInterval(30)
            }
        } catch {
            pausedUntil = now().addingTimeInterval(60)
        }
    }

    func apply(_ checks: CommitChecks, to id: OID) {
        let previous = results[id]
        results[id] = checks
        guard var watch = watches[id] else { return }
        if checks.runs.isEmpty {
            if now().timeIntervalSince(watch.since) > Self.watchGiveUp { unwatch(id) }
            return
        }
        if checks.isComplete {
            unwatch(id)
            onEvent?(.finished(branch: watch.branch, checks: checks))
        } else if !watch.announced {
            watch.announced = true
            watches[id] = watch
            onEvent?(.started(branch: watch.branch, checks: checks))
        } else if previous?.runs.map(\.state) != checks.runs.map(\.state) {
            onEvent?(.progressed(branch: watch.branch, checks: checks))
        }
    }

    func unwatch(_ id: OID) {
        watches[id] = nil
        watching.remove(id)
    }

    public func rerunFailed(_ id: OID, branch: String) async throws {
        guard let client, let repository, let checks = results[id] else { return }
        for runID in checks.rerunnable {
            try await client.rerunFailed(runID: runID, in: repository)
        }
        var next = checks
        next.runs = checks.runs.map { run in
            var run = run
            if run.state == .failed {
                run.state = .pending
                run.completedAt = nil
            }
            return run
        }
        results[id] = next
        watches[id] = Watch(branch: branch, since: now(), announced: true)
        watching.insert(id)
        attempts[id] = nil
    }
}
