import CoreServices
import Foundation

public enum RepositoryChange: String, Sendable, Hashable, CaseIterable {
    case head
    case refs
    case index
    case state
    case config
    case worktree
}

public final class RepositoryWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable (Set<RepositoryChange>) -> Void

    public static let latency: TimeInterval = 0.05
    public static let debounce: TimeInterval = 0.3

    public let root: URL?
    public let gitDir: URL
    public let commonDir: URL
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.aaravmaloo.vrai.watcher")
    private var stream: FSEventStreamRef?
    private var pending: Set<RepositoryChange> = []
    private var scheduled = false

    public init(root: URL?, gitDir: URL, commonDir: URL, handler: @escaping Handler) {
        self.root = root
        self.gitDir = gitDir.standardizedFileURL
        self.commonDir = commonDir.standardizedFileURL
        self.handler = handler
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    public var watchedPaths: [String] {
        var paths: [String] = []
        for url in [root, gitDir, commonDir].compactMap({ $0 }) {
            let path = Self.canonical(url.path(percentEncoded: false))
            if paths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { continue }
            paths.removeAll { $0.hasPrefix(path + "/") }
            paths.append(path)
        }
        return paths
    }

    @discardableResult
    public func start() -> Bool {
        queue.sync {
            guard stream == nil else { return true }
            var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
            let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
            guard let created = FSEventStreamCreate(kCFAllocatorDefault, Self.callback, &context, watchedPaths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), Self.latency, flags) else { return false }
            FSEventStreamSetDispatchQueue(created, queue)
            guard FSEventStreamStart(created) else {
                FSEventStreamInvalidate(created)
                FSEventStreamRelease(created)
                return false
            }
            stream = created
            return true
        }
    }

    public func stop() {
        queue.sync {
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            pending.removeAll()
        }
    }

    private static let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
        guard let info else { return }
        let watcher = Unmanaged<RepositoryWatcher>.fromOpaque(info).takeUnretainedValue()
        let array = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as NSArray
        var changes: Set<RepositoryChange> = []
        for index in 0..<min(count, array.count) {
            guard let path = array[index] as? String else { continue }
            if let change = watcher.classify(path) { changes.insert(change) }
        }
        watcher.receive(changes)
    }

    private func receive(_ changes: Set<RepositoryChange>) {
        guard !changes.isEmpty else { return }
        pending.formUnion(changes)
        guard !scheduled else { return }
        scheduled = true
        queue.asyncAfter(deadline: .now() + Self.debounce) { [weak self] in
            guard let self else { return }
            let batch = self.pending
            self.pending.removeAll()
            self.scheduled = false
            guard !batch.isEmpty, self.stream != nil else { return }
            self.handler(batch)
        }
    }

    public func classify(_ rawPath: String) -> RepositoryChange? {
        let path = Self.canonical(rawPath)
        for dir in [gitDir, commonDir] {
            let base = Self.canonical(dir.path(percentEncoded: false))
            guard path == base || path.hasPrefix(base + "/") else { continue }
            let relative = path == base ? "" : String(path.dropFirst(base.count + 1))
            return Self.classifyGitPath(relative)
        }
        if let root {
            let base = Self.canonical(root.path(percentEncoded: false))
            guard path == base || path.hasPrefix(base + "/") else { return nil }
            let relative = path == base ? "" : String(path.dropFirst(base.count + 1))
            if relative == ".git" || relative.hasPrefix(".git/") { return Self.classifyGitPath(String(relative.dropFirst(min(relative.count, 5)))) }
            return .worktree
        }
        return nil
    }

    static func classifyGitPath(_ relative: String) -> RepositoryChange? {
        let first = relative.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        if relative.hasSuffix(".lock") { return nil }
        switch first {
        case "objects", "logs", "vrai", "hooks", "info", "description", "COMMIT_EDITMSG", "FETCH_HEAD", "ORIG_HEAD", "gk", "lfs":
            return nil
        case "HEAD":
            return .head
        case "refs", "packed-refs":
            return .refs
        case "index":
            return .index
        case "config":
            return .config
        case "MERGE_HEAD", "MERGE_MSG", "MERGE_MODE", "rebase-merge", "rebase-apply", "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_LOG", "BISECT_START", "BISECT_EXPECTED_REV", "BISECT_TERMS", "BISECT_NAMES", "sequencer", "AUTO_MERGE":
            return .state
        case "worktrees", "modules":
            return .refs
        default:
            return nil
        }
    }

    static func canonical(_ path: String) -> String {
        var value = path
        while value.count > 1, value.hasSuffix("/") { value.removeLast() }
        if value.hasPrefix("/private/var/") { value.removeFirst("/private".count) }
        if value.hasPrefix("/private/tmp/") { value.removeFirst("/private".count) }
        return value
    }
}
