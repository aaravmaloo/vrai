import Foundation
import VraiGit

public struct DirectoryProbe: Sendable, Hashable {
    public var path: String
    public var status: RecentStatus
    public var remote: String?
    public var remoteKnown: Bool
}

extension AppModel {
    public static let directoryWidth = 6
    public static let directoryFreshness: TimeInterval = 5

    public var directoryRefreshing: Bool { directoryRefresh != nil }

    public func refreshDirectory() {
        guard directoryRefresh == nil else { return }
        if let last = directoryRefreshed, Date().timeIntervalSince(last) < Self.directoryFreshness { return }
        let paths = recents.map(\.path)
        directoryRefresh = Task { [weak self] in
            await self?.probeDirectory(paths)
            self?.directoryRefreshed = Date()
            self?.directoryRefresh = nil
        }
    }

    public func probeDirectory(_ paths: [String], width: Int = AppModel.directoryWidth) async {
        var changed = false
        await withTaskGroup(of: DirectoryProbe.self) { group in
            var queue = paths.makeIterator()
            for _ in 0..<max(1, width) {
                guard let path = queue.next() else { break }
                group.addTask { await self.probe(path) }
            }
            while let probe = await group.next() {
                if apply(probe) { changed = true }
                if let path = queue.next() { group.addTask { await self.probe(path) } }
            }
        }
        if changed { saveRecents() }
    }

    func probe(_ path: String) async -> DirectoryProbe {
        let url = URL(filePath: path, directoryHint: .isDirectory)
        let status = await recentStatus(at: url)
        guard !status.missing, let origin = await origin(at: url) else { return DirectoryProbe(path: path, status: status, remote: nil, remoteKnown: false) }
        return DirectoryProbe(path: path, status: status, remote: origin, remoteKnown: true)
    }

    func apply(_ probe: DirectoryProbe) -> Bool {
        if directoryStatus[probe.path] != probe.status { directoryStatus[probe.path] = probe.status }
        guard probe.remoteKnown, let index = recents.firstIndex(where: { $0.path == probe.path }), recents[index].remote != probe.remote else { return false }
        recents[index].remote = probe.remote
        return true
    }

    public func remoteURL(at url: URL) async -> String? {
        await origin(at: url) ?? nil
    }

    func origin(at url: URL) async -> String?? {
        guard let git = try? process(at: url), let result = try? await git.runAllowingFailure(.read(["remote", "get-url", "origin"], acceptedExitCodes: [0, 2]), background: true) else { return nil }
        switch result.exitCode {
        case 0:
            let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return .some(value.isEmpty ? nil : value)
        case 2: return .some(nil)
        default: return nil
        }
    }
}
