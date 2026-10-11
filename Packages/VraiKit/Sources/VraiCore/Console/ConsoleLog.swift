import Foundation
import Observation
import VraiGit

public final class ConsoleInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [ConsoleEntry] = []
    private var scheduled = false
    private var wake: (@Sendable () -> Void)?

    public init() {}

    func setWake(_ wake: @escaping @Sendable () -> Void) {
        lock.withLock { self.wake = wake }
    }

    public func receive(_ entry: ConsoleEntry) {
        let wake: (@Sendable () -> Void)? = lock.withLock {
            pending.append(entry)
            guard !scheduled, let wake = self.wake else { return nil }
            scheduled = true
            return wake
        }
        wake?()
    }

    func take() -> [ConsoleEntry] {
        lock.withLock {
            scheduled = false
            defer { pending.removeAll() }
            return pending
        }
    }
}

@MainActor
@Observable
public final class ConsoleLog {
    public struct Running: Sendable, Hashable, Identifiable {
        public let id: UUID
        public var command: String
        public var startedAt: Date
        public var source: ConsoleEntry.Source
    }

    public static let defaultLimit = 1000
    public static let backgroundOutputCap = 16 * 1024
    public static let byteBudget = 48 * 1024 * 1024
    public static let historyLimit = 200

    public private(set) var entries: [ConsoleEntry] = []
    public private(set) var running: [Running] = []
    public private(set) var expanded: Set<UUID> = []
    public private(set) var history: [String] = []
    public private(set) var failures = 0
    public private(set) var lastFailure: UUID?
    public private(set) var spilled: [UUID: URL] = [:]
    public private(set) var revision = 0

    @ObservationIgnored public let limit: Int
    @ObservationIgnored public var spillFolder: URL
    @ObservationIgnored public nonisolated let inbox: ConsoleInbox
    @ObservationIgnored private var bytes = 0

    public init(limit: Int = ConsoleLog.defaultLimit, spillFolder: URL? = nil) {
        self.limit = max(1, limit)
        self.spillFolder = spillFolder ?? FileManager.default.temporaryDirectory.appending(path: "vrai-console", directoryHint: .isDirectory)
        inbox = ConsoleInbox()
        inbox.setWake { [weak self] in
            Task { @MainActor in self?.flush() }
        }
    }

    public nonisolated var observer: GitProcess.Observer {
        let inbox = inbox
        return { entry in inbox.receive(entry) }
    }

    public func flush() {
        let fresh = inbox.take()
        guard !fresh.isEmpty else { return }
        for entry in fresh { insert(entry) }
        trim()
        revision += 1
    }

    public func append(_ entry: ConsoleEntry) {
        flush()
        insert(entry)
        trim()
        revision += 1
    }

    private func insert(_ raw: ConsoleEntry) {
        var entry = raw
        entry.command = ConsoleRedaction.redact(entry.command)
        entry.stdout = ConsoleRedaction.redact(entry.stdout)
        entry.stderr = ConsoleRedaction.redact(entry.stderr)
        if entry.background {
            if entry.stdout.utf8.count > Self.backgroundOutputCap {
                entry.stdout = Self.prefix(entry.stdout, Self.backgroundOutputCap)
                entry.stdoutTruncated = true
            }
            if entry.stderr.utf8.count > Self.backgroundOutputCap {
                entry.stderr = Self.prefix(entry.stderr, Self.backgroundOutputCap)
                entry.stderrTruncated = true
            }
        }
        entries.append(entry)
        bytes += Self.size(entry)
        if entry.failed, !entry.background {
            expanded.insert(entry.id)
            failures += 1
            lastFailure = entry.id
        }
    }

    private func trim() {
        while entries.count > limit || (bytes > Self.byteBudget && entries.count > 1) {
            let index = entries.firstIndex { $0.background } ?? entries.startIndex
            let removed = entries.remove(at: index)
            bytes -= Self.size(removed)
            expanded.remove(removed.id)
            if let url = spilled.removeValue(forKey: removed.id) { try? FileManager.default.removeItem(at: url) }
        }
    }

    public func clear() {
        flush()
        for url in spilled.values { try? FileManager.default.removeItem(at: url) }
        entries.removeAll()
        expanded.removeAll()
        spilled.removeAll()
        bytes = 0
        revision += 1
    }

    public func isExpanded(_ id: UUID) -> Bool { expanded.contains(id) }

    public func setExpanded(_ id: UUID, _ open: Bool) {
        if open { expanded.insert(id) } else { expanded.remove(id) }
    }

    public func toggle(_ id: UUID) {
        setExpanded(id, !expanded.contains(id))
    }

    public func remember(_ typed: String) {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if history.last != text { history.append(text) }
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
    }

    public func begin(_ command: String, source: ConsoleEntry.Source = .you) -> UUID {
        let item = Running(id: UUID(), command: ConsoleRedaction.redact(command), startedAt: Date(), source: source)
        running.append(item)
        return item.id
    }

    public func end(_ id: UUID) {
        running.removeAll { $0.id == id }
    }

    public func entry(for result: GitResult) -> ConsoleEntry? {
        flush()
        let command = ConsoleRedaction.redact(result.command.display)
        return entries.last { $0.startedAt == result.startedAt && $0.command == command }
    }

    public func entry(id: UUID) -> ConsoleEntry? {
        entries.first { $0.id == id }
    }

    @discardableResult
    public func spill(_ result: GitResult, for id: UUID) -> URL? {
        guard result.stdout.count > ConsoleEntry.outputCap || result.stderr.count > ConsoleEntry.outputCap else { return nil }
        do {
            try FileManager.default.createDirectory(at: spillFolder, withIntermediateDirectories: true)
            let url = spillFolder.appending(path: id.uuidString + ".txt")
            var data = Data(ConsoleRedaction.redact(result.output).utf8)
            if !result.stderr.isEmpty {
                if !data.isEmpty { data.append(0x0A) }
                data.append(Data(ConsoleRedaction.redact(result.errorOutput).utf8))
            }
            try data.write(to: url, options: .atomic)
            spilled[id] = url
            return url
        } catch {
            return nil
        }
    }

    public func output(of entry: ConsoleEntry) -> String {
        let out = entry.stdout.trimmingCharacters(in: .newlines)
        let err = entry.stderr.trimmingCharacters(in: .newlines)
        if out.isEmpty { return err }
        if err.isEmpty { return out }
        return out + "\n" + err
    }

    static func prefix(_ text: String, _ limit: Int) -> String {
        String(decoding: Data(text.utf8.prefix(limit)), as: UTF8.self)
    }

    static func size(_ entry: ConsoleEntry) -> Int {
        entry.stdout.utf8.count + entry.stderr.utf8.count + entry.command.utf8.count
    }
}

public enum ConsoleRedaction {
    public static func redact(_ text: String) -> String {
        guard text.contains("://"), text.contains("@") else { return text }
        return text.replacing(#/([A-Za-z][A-Za-z0-9+.\-]*://)([^/@\s:]+):([^/@\s]+)@/#) { match in
            String(match.output.1) + String(match.output.2) + ":***@"
        }
    }
}
