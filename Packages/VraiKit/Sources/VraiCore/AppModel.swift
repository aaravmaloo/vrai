import Foundation
import Observation
import VraiGit

public struct RepositoryReference: Codable, Hashable, Sendable {
    public var path: String

    public init(path: String) {
        self.path = path
    }

    public init(url: URL) {
        path = url.standardizedFileURL.path(percentEncoded: false).trimmingTrailingSlashes()
    }

    public var url: URL { URL(filePath: path, directoryHint: .isDirectory) }
    public var name: String { url.lastPathComponent }
}

public struct RecentRepository: Codable, Hashable, Sendable, Identifiable {
    public var path: String
    public var name: String
    public var lastOpened: Date
    public var remote: String?

    public var id: String { path }

    public init(path: String, name: String, lastOpened: Date, remote: String? = nil) {
        self.path = path
        self.name = name
        self.lastOpened = lastOpened
        self.remote = remote
    }

    enum CodingKeys: String, CodingKey {
        case path
        case name
        case lastOpened
        case remote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? URL(filePath: path).lastPathComponent
        let seconds = try container.decodeIfPresent(Double.self, forKey: .lastOpened) ?? 0
        lastOpened = Date(timeIntervalSince1970: seconds)
        remote = try container.decodeIfPresent(String.self, forKey: .remote)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encode(lastOpened.timeIntervalSince1970.rounded(), forKey: .lastOpened)
        try container.encodeIfPresent(remote, forKey: .remote)
    }
}

struct RecentsFile: Codable {
    var version = 1
    var repositories: [RecentRepository]
}

@MainActor
@Observable
public final class AppModel {
    public let launch: LaunchOptions
    public let preferences: Preferences
    public internal(set) var recents: [RecentRepository] = []
    public internal(set) var directoryStatus: [String: RecentStatus] = [:]
    public internal(set) var gitExecutable: GitExecutable?
    public internal(set) var gitError: GitError?
    public private(set) var pendingOpen: URL?

    @ObservationIgnored public let defaults: UserDefaults
    @ObservationIgnored public let askpass: AskpassBridge?
    @ObservationIgnored public let askpassHelper: URL?
    @ObservationIgnored private var stores: [String: RepositoryStore] = [:]
    @ObservationIgnored private var colors: [String: BranchColors] = [:]
    @ObservationIgnored private var requested: Set<String> = []
    @ObservationIgnored var directoryRefresh: Task<Void, Never>?
    @ObservationIgnored var directoryRefreshed: Date?

    public static let maximumRecents = 100
    public static let shownRecents = 20

    public init(launch: LaunchOptions) {
        PerfLog.sinceLaunch("launch.model.start")
        PerfLog.watchLaunch()
        self.launch = launch
        defaults = launch.makeDefaults()
        askpassHelper = AskpassBridge.bundledHelper()
        let socketFolder = launch.sandbox?.appending(path: "askpass", directoryHint: .isDirectory) ?? FileManager.default.temporaryDirectory.appending(path: "vrai-askpass", directoryHint: .isDirectory)
        askpass = askpassHelper == nil ? nil : try? AskpassBridge(socketURL: AskpassBridge.socketURL(in: socketFolder))
        preferences = Preferences(defaults: defaults)
        recents = loadRecents()
        pendingOpen = launch.open
        PerfLog.sinceLaunch("launch.model.git")
        do {
            gitExecutable = try discoverGit()
        } catch let error as GitError {
            gitError = error
        } catch {
            gitError = GitError(.gitNotFound)
        }
        PerfLog.sinceLaunch("launch.model.end")
    }

    private func discoverGit() throws -> GitExecutable {
        switch launch.isSandboxed ? launch.gitProblem : nil {
        case "missing": throw GitError(.gitNotFound)
        case "old": throw GitError(.gitTooOld(found: GitVersion(2, 39, 5), needed: GitVersion.minimum))
        default: return try GitExecutable.discover(preferred: defaults.string(forKey: "gitPath"))
        }
    }

    public var gitVersion: GitVersion? { gitExecutable?.version }

    public func rediscoverGit() {
        do {
            gitExecutable = try discoverGit()
            gitError = nil
        } catch let error as GitError {
            gitError = error
        } catch {
            gitError = GitError(.gitNotFound)
        }
    }

    public func takePendingOpen() -> URL? {
        defer { pendingOpen = nil }
        return pendingOpen
    }

    public var now: Date { launch.now ?? Date() }

    public var environment: GitEnvironment {
        if let sandbox = launch.sandbox { return .sandbox(root: sandbox) }
        return .user()
    }

    public func process(at url: URL, observer: GitProcess.Observer? = nil) throws -> GitProcess {
        guard let gitExecutable else { throw gitError ?? GitError(.gitNotFound) }
        var environment = self.environment
        if let askpass, let askpassHelper { environment = askpass.environment(environment, helper: askpassHelper, context: url.path(percentEncoded: false)) }
        return GitProcess(executable: gitExecutable, workingDirectory: url, environment: environment, observer: observer)
    }

    public func open(path: String) async throws -> RepositoryReference {
        let url = URL(filePath: path, directoryHint: .isDirectory).standardizedFileURL
        let process = try process(at: url)
        let result = try await process.run(.read(["rev-parse", "--show-toplevel"]), background: true)
        let top = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let reference = RepositoryReference(url: URL(filePath: top.isEmpty ? url.path(percentEncoded: false) : top, directoryHint: .isDirectory))
        noteOpened(reference)
        return request(reference)
    }

    @discardableResult
    public func request(_ reference: RepositoryReference) -> RepositoryReference {
        requested.insert(reference.path)
        return reference
    }

    public func wasRequested(_ reference: RepositoryReference) -> Bool {
        requested.contains(reference.path)
    }

    public func store(for reference: RepositoryReference) throws -> RepositoryStore {
        if let existing = stores[reference.path] { return existing }
        let console = ConsoleLog(spillFolder: launch.sandbox?.appending(path: "console", directoryHint: .isDirectory))
        let store = RepositoryStore(git: try process(at: reference.url, observer: console.observer), colors: colors[reference.path] ?? loadColors(reference), console: console)
        store.renameThreshold = preferences.renameThreshold
        stores[reference.path] = store
        return store
    }

    public func isOpen(_ reference: RepositoryReference) -> Bool {
        stores[reference.path] != nil
    }

    public func release(_ reference: RepositoryReference) {
        guard let store = stores.removeValue(forKey: reference.path) else { return }
        saveColors(store.branchColors, for: reference)
        store.close()
    }

    public func noteOpened(_ reference: RepositoryReference) {
        let remote = recents.first { $0.path == reference.path }?.remote
        var list = recents.filter { $0.path != reference.path }
        list.insert(RecentRepository(path: reference.path, name: reference.name, lastOpened: now, remote: remote), at: 0)
        recents = Array(list.prefix(Self.maximumRecents))
        saveRecents()
    }

    public func removeRecent(_ recent: RecentRepository) {
        recents.removeAll { $0.path == recent.path }
        saveRecents()
    }

    private func loadRecents() -> [RecentRepository] {
        if let file = launch.recentsFile {
            guard let data = try? Data(contentsOf: file), let decoded = try? JSONDecoder().decode(RecentsFile.self, from: data) else { return [] }
            return decoded.repositories
        }
        guard let data = defaults.data(forKey: "recents"), let decoded = try? JSONDecoder().decode(RecentsFile.self, from: data) else { return [] }
        return decoded.repositories
    }

    func saveRecents() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(RecentsFile(repositories: recents)) else { return }
        if let file = launch.recentsFile {
            try? data.write(to: file, options: .atomic)
        } else {
            defaults.set(data, forKey: "recents")
        }
    }

    private func colorsKey(_ reference: RepositoryReference) -> String { "branchColors:" + reference.path }

    private func loadColors(_ reference: RepositoryReference) -> BranchColors {
        guard let data = defaults.data(forKey: colorsKey(reference)), let decoded = try? JSONDecoder().decode(BranchColors.self, from: data) else { return BranchColors() }
        return decoded
    }

    public func branchLane(for path: String, branch: String) -> Int? {
        (colors[path] ?? loadColors(RepositoryReference(path: path))).color(for: branch)
    }

    public func saveColors(_ colors: BranchColors, for reference: RepositoryReference) {
        self.colors[reference.path] = colors
        guard let data = try? JSONEncoder().encode(colors) else { return }
        defaults.set(data, forKey: colorsKey(reference))
    }

    private func layoutKey(_ reference: RepositoryReference) -> String { "layout:" + reference.path }

    public func layout(for reference: RepositoryReference) -> RepositoryLayout? {
        guard let data = defaults.data(forKey: layoutKey(reference)) else { return nil }
        return try? JSONDecoder().decode(RepositoryLayout.self, from: data)
    }

    public func saveLayout(_ layout: RepositoryLayout, for reference: RepositoryReference) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        defaults.set(data, forKey: layoutKey(reference))
    }
}

extension String {
    func trimmingTrailingSlashes() -> String {
        var value = self
        while value.count > 1, value.hasSuffix("/") { value.removeLast() }
        return value
    }
}
