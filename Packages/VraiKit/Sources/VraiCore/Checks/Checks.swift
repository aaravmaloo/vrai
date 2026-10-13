import Foundation
import VraiGit

public enum CheckState: String, Sendable, Hashable, Codable, CaseIterable {
    case pending
    case running
    case passed
    case failed
    case cancelled
    case skipped

    public var isFinished: Bool {
        switch self {
        case .pending, .running: false
        case .passed, .failed, .cancelled, .skipped: true
        }
    }

    public static func combined(_ states: [CheckState]) -> CheckState? {
        guard !states.isEmpty else { return nil }
        if states.contains(.failed) { return .failed }
        if states.contains(.running) { return .running }
        if states.contains(.pending) { return .pending }
        if states.contains(.cancelled) { return .cancelled }
        if states.allSatisfy({ $0 == .skipped }) { return .skipped }
        return .passed
    }
}

public struct CheckRun: Sendable, Hashable, Identifiable {
    public enum Source: String, Sendable, Hashable {
        case check
        case status
    }

    public var id: String
    public var name: String
    public var workflow: String?
    public var state: CheckState
    public var url: URL?
    public var startedAt: Date?
    public var completedAt: Date?
    public var runID: Int?
    public var source: Source
    public var summary: String?

    public init(id: String, name: String, workflow: String? = nil, state: CheckState, url: URL? = nil, startedAt: Date? = nil, completedAt: Date? = nil, runID: Int? = nil, source: Source = .check, summary: String? = nil) {
        self.id = id
        self.name = name
        self.workflow = workflow
        self.state = state
        self.url = url
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.runID = runID
        self.source = source
        self.summary = summary
    }

    public var title: String {
        guard let workflow, !workflow.isEmpty, workflow != name else { return name }
        return workflow + " / " + name
    }

    public func duration(now: Date) -> TimeInterval? {
        guard let startedAt else { return nil }
        return max(0, (completedAt ?? now).timeIntervalSince(startedAt))
    }
}

public struct CommitChecks: Sendable, Hashable {
    public var sha: String
    public var runs: [CheckRun]
    public var url: URL?
    public var fetchedAt: Date

    public init(sha: String, runs: [CheckRun], url: URL? = nil, fetchedAt: Date = Date()) {
        self.sha = sha
        self.runs = runs
        self.url = url
        self.fetchedAt = fetchedAt
    }

    public var state: CheckState? { CheckState.combined(runs.map(\.state)) }
    public var isComplete: Bool { !runs.isEmpty && runs.allSatisfy(\.state.isFinished) }
    public var failed: [CheckRun] { runs.filter { $0.state == .failed } }
    public var finishedCount: Int { runs.count { $0.state.isFinished } }
    public var rerunnable: [Int] { Array(Set(failed.compactMap(\.runID))).sorted() }

    public func count(_ state: CheckState) -> Int {
        runs.count { $0.state == state }
    }

    public var sorted: [CheckRun] {
        runs.sorted { a, b in
            let left = Self.rank(a.state)
            let right = Self.rank(b.state)
            return left != right ? left < right : a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    static func rank(_ state: CheckState) -> Int {
        switch state {
        case .failed: 0
        case .running: 1
        case .pending: 2
        case .cancelled: 3
        case .passed: 4
        case .skipped: 5
        }
    }
}

public struct ChecksRepository: Sendable, Hashable {
    public var host: String
    public var owner: String
    public var name: String
    public var remote: String

    public init(host: String, owner: String, name: String, remote: String) {
        self.host = host
        self.owner = owner
        self.name = name
        self.remote = remote
    }

    public init?(remote: Remote) {
        self.init(url: remote.pushURL ?? remote.fetchURL, remote: remote.name)
    }

    public init?(url: String, remote: String) {
        guard let parsed = RemoteURL(url), parsed.kind == .network || parsed.kind == .scp, let host = parsed.host?.lowercased(), CredentialManager.isGitHub(host: host) else { return nil }
        let parts = parsed.repositoryPath.split(separator: "/").map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        self.host = host
        owner = parts[0]
        name = parts[1]
        self.remote = remote
    }

    public var slug: String { owner + "/" + name }

    public var apiBase: URL {
        if host == "github.com" { return URL(string: "https://api.github.com")! }
        if host.hasSuffix(".ghe.com") { return URL(string: "https://api." + host)! }
        return URL(string: "https://" + host + "/api/v3")!
    }

    public var webBase: URL { URL(string: "https://" + host + "/" + slug)! }

    public func commitURL(_ sha: String) -> URL {
        webBase.appending(path: "commit").appending(path: sha).appending(path: "checks")
    }

    public func actionsURL() -> URL {
        webBase.appending(path: "actions")
    }

    public static func pick(remotes: [Remote], upstream: String?) -> ChecksRepository? {
        let preferred = upstream.flatMap { name in remotes.map(\.name).sorted { $0.count > $1.count }.first { name.hasPrefix($0 + "/") } }
        let order = remotes.sorted { a, b in
            func rank(_ remote: Remote) -> Int {
                if remote.name == preferred { return 0 }
                if remote.name == "origin" { return 1 }
                if remote.name == "upstream" { return 2 }
                return 3
            }
            return rank(a) < rank(b)
        }
        return order.lazy.compactMap { ChecksRepository(remote: $0) }.first
    }
}

public enum ChecksProblem: Sendable, Hashable {
    case signedOut
    case rateLimited(until: Date?)
    case offline
    case server(Int)
}

public struct ChecksError: Error, Sendable, Hashable {
    public var problem: ChecksProblem

    public init(_ problem: ChecksProblem) {
        self.problem = problem
    }
}
