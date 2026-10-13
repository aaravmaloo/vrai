import Foundation
import VraiGit

public protocol ChecksClient: Sendable {
    func checks(for sha: String, in repository: ChecksRepository) async throws -> CommitChecks
    func rerunFailed(runID: Int, in repository: ChecksRepository) async throws
    func canWrite(_ repository: ChecksRepository) async -> Bool
}

public typealias TokenProvider = @Sendable (_ host: String) async -> String?

public actor GitHubChecksClient: ChecksClient {
    struct Cached {
        var etag: String
        var data: Data
    }

    public let session: URLSession
    let token: TokenProvider
    private var cache: [URL: Cached] = [:]
    private var tokens: [String: (value: String?, at: Date)] = [:]

    public init(session: URLSession = .shared, token: @escaping TokenProvider) {
        self.session = session
        self.token = token
    }

    func token(for host: String) async -> String? {
        if let cached = tokens[host], Date().timeIntervalSince(cached.at) < (cached.value == nil ? 120 : 1800) { return cached.value }
        let value = await token(host)
        tokens[host] = (value, Date())
        return value
    }

    func forgetToken(_ host: String) {
        tokens[host] = nil
    }

    public func canWrite(_ repository: ChecksRepository) async -> Bool {
        await token(for: repository.host) != nil
    }

    public func checks(for sha: String, in repository: ChecksRepository) async throws -> CommitChecks {
        let base = repository.apiBase.appending(path: "repos").appending(path: repository.owner).appending(path: repository.name)
        let commit = base.appending(path: "commits").appending(path: sha)
        let runsURL = base.appending(path: "actions").appending(path: "runs").appending(queryItems: [URLQueryItem(name: "head_sha", value: sha), URLQueryItem(name: "per_page", value: "50")])
        let checksURL = commit.appending(path: "check-runs").appending(queryItems: [URLQueryItem(name: "per_page", value: "100")])
        let statusURL = commit.appending(path: "status")
        guard let checksData = try await get(checksURL, host: repository.host) else {
            return CommitChecks(sha: sha, runs: [], url: repository.commitURL(sha))
        }
        let signedIn = await token(for: repository.host) != nil
        let workflows = signedIn ? (try? await get(runsURL, host: repository.host)).flatMap { try? GitHubChecksParser.workflowRuns($0) } ?? [:] : [:]
        var runs = try GitHubChecksParser.checkRuns(checksData, workflows: workflows)
        if let statusData = try? await get(statusURL, host: repository.host) {
            runs += (try? GitHubChecksParser.statuses(statusData)) ?? []
        }
        return CommitChecks(sha: sha, runs: runs, url: repository.commitURL(sha))
    }

    public func rerunFailed(runID: Int, in repository: ChecksRepository) async throws {
        let url = repository.apiBase.appending(path: "repos").appending(path: repository.owner).appending(path: repository.name)
            .appending(path: "actions").appending(path: "runs").appending(path: String(runID)).appending(path: "rerun-failed-jobs")
        guard let token = await token(for: repository.host) else { throw ChecksError(.signedOut) }
        var request = Self.request(url, token: token)
        request.httpMethod = "POST"
        let (_, response) = try await load(request)
        guard let http = response as? HTTPURLResponse else { throw ChecksError(.offline) }
        guard (200..<300).contains(http.statusCode) else { throw Self.error(http) }
    }

    static func request(_ url: URL, token: String?) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Vrai", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        return request
    }

    static func error(_ response: HTTPURLResponse) -> ChecksError {
        switch response.statusCode {
        case 401:
            return ChecksError(.signedOut)
        case 403, 429:
            if response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" || response.statusCode == 429 {
                let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
                return ChecksError(.rateLimited(until: reset))
            }
            return ChecksError(.signedOut)
        default:
            return ChecksError(.server(response.statusCode))
        }
    }

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw ChecksError(.offline)
        }
    }

    func get(_ url: URL, host: String) async throws -> Data? {
        let token = await token(for: host)
        var request = Self.request(url, token: token)
        if let cached = cache[url] { request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await load(request)
        guard let http = response as? HTTPURLResponse else { throw ChecksError(.offline) }
        switch http.statusCode {
        case 200:
            if let etag = http.value(forHTTPHeaderField: "ETag") { cache[url] = Cached(etag: etag, data: data) }
            return data
        case 304:
            return cache[url]?.data
        case 404:
            if token == nil { throw ChecksError(.signedOut) }
            return nil
        case 422:
            return nil
        case 401:
            forgetToken(host)
            throw ChecksError(.signedOut)
        default:
            throw Self.error(http)
        }
    }
}

public struct FixtureChecksClient: ChecksClient {
    struct Entry: Decodable {
        struct Run: Decodable {
            var name: String
            var workflow: String?
            var state: CheckState
            var seconds: Double?
            var summary: String?
        }

        var runs: [Run]
    }

    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    public func checks(for sha: String, in repository: ChecksRepository) async throws -> CommitChecks {
        let data = try Data(contentsOf: file)
        let entries = try JSONDecoder().decode([String: Entry].self, from: data)
        let entry = entries.first { sha.hasPrefix($0.key) }?.value
        let started = Date(timeIntervalSince1970: 1_791_720_000)
        let runs = (entry?.runs ?? []).enumerated().map { index, run in
            CheckRun(
                id: "fixture:" + String(index),
                name: run.name,
                workflow: run.workflow,
                state: run.state,
                url: repository.commitURL(sha),
                startedAt: run.seconds == nil ? nil : started,
                completedAt: run.seconds.flatMap { run.state.isFinished ? started.addingTimeInterval($0) : nil },
                runID: run.state == .failed ? index + 1 : nil,
                summary: run.summary
            )
        }
        return CommitChecks(sha: sha, runs: runs, url: repository.commitURL(sha))
    }

    public func rerunFailed(runID: Int, in repository: ChecksRepository) async throws {}

    public func canWrite(_ repository: ChecksRepository) async -> Bool { true }
}

public enum GitHubToken {
    public static let ghLocations = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]

    public static func provider(git: GitProcess, environment: [String: String] = ProcessInfo.processInfo.environment) -> TokenProvider {
        { host in
            if host == "github.com" {
                for key in ["GH_TOKEN", "GITHUB_TOKEN"] {
                    if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
                }
            }
            if let value = await fromGH(host: host, environment: environment) { return value }
            let store = CredentialStore(git: git)
            return try? await store.fill(url: "https://" + host)?.password
        }
    }

    static func ghExecutable(environment: [String: String]) -> URL? {
        let fromPath = (environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/gh" }
        return (ghLocations + fromPath).first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(filePath: $0) }
    }

    static func fromGH(host: String, environment: [String: String]) async -> String? {
        guard let gh = ghExecutable(environment: environment) else { return nil }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = gh
            process.arguments = ["auth", "token", "--hostname", host]
            var env = environment
            env["GH_PROMPT_DISABLED"] = "1"
            env["NO_COLOR"] = "1"
            process.environment = env
            process.standardOutput = Pipe()
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            process.terminationHandler = { process in
                let data = (process.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
                let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: process.terminationStatus == 0 && !value.isEmpty && !value.contains(" ") ? value : nil)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
