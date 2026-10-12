import Darwin
import Foundation
import Synchronization

public final class PerfLog: Sendable {
    public static let shared: PerfLog? = {
        #if DEBUG
        PerfLog(arguments: ProcessInfo.processInfo.arguments)
        #else
        nil
        #endif
    }()

    public static let argument = "-VraiPerfLog"

    private struct State {
        var starts: [String: ContinuousClock.Instant] = [:]
        var once: Set<String> = []
        var handle: FileHandle?
    }

    public let url: URL
    private let state: Mutex<State>
    private let clock = ContinuousClock()

    init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: Self.argument), arguments.indices.contains(index + 1) else { return nil }
        let url = URL(filePath: arguments[index + 1])
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        }
        let handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
        self.url = url
        state = Mutex(State(handle: handle))
    }

    public static var isEnabled: Bool { shared != nil }

    public static func begin(_ name: String) {
        shared?.begin(name)
    }

    public static func end(_ name: String, detail: String? = nil) {
        shared?.end(name, detail: detail)
    }

    public static func endAfterCommit(_ name: String, detail: String? = nil) {
        guard let shared else { return }
        DispatchQueue.main.async { shared.end(name, detail: detail) }
    }

    public static func isPending(_ name: String) -> Bool {
        shared?.state.withLock { $0.starts[name] != nil } ?? false
    }

    public static func record(_ name: String, _ value: Double, detail: String? = nil) {
        shared?.write(name, value, detail: detail)
    }

    public static func sinceLaunch(_ name: String) {
        guard let shared, shared.claim(name) else { return }
        guard let started = processStart else { return }
        shared.write(name, Date().timeIntervalSince(started) * 1000, detail: nil)
    }

    public static func watchLaunch() {
        guard isEnabled else { return }
        let marks = ["NSApplicationWillFinishLaunchingNotification": "launch.will", "NSApplicationDidFinishLaunchingNotification": "launch.did"]
        for (notification, mark) in marks {
            _ = NotificationCenter.default.addObserver(forName: Notification.Name(notification), object: nil, queue: nil) { _ in sinceLaunch(mark) }
        }
    }

    public static func recordMemory(_ name: String) {
        guard let shared, let bytes = footprint else { return }
        shared.write(name, Double(bytes) / 1_048_576, detail: "MB")
    }

    public static var footprint: UInt64? {
        var usage = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
        }
        return status == 0 ? usage.ri_phys_footprint : nil
    }

    public static var processStart: Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }

    func begin(_ name: String) {
        let now = clock.now
        state.withLock { $0.starts[name] = now }
    }

    func end(_ name: String, detail: String?) {
        let now = clock.now
        guard let start = state.withLock({ $0.starts.removeValue(forKey: name) }) else { return }
        let elapsed = now - start
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        write(name, ms, detail: detail)
    }

    func claim(_ name: String) -> Bool {
        state.withLock { $0.once.insert(name).inserted }
    }

    func write(_ name: String, _ value: Double, detail: String?) {
        var line = name + " " + String(format: "%.2f", value)
        if let detail { line += " " + detail }
        let data = Data((line + "\n").utf8)
        state.withLock { state in
            try? state.handle?.write(contentsOf: data)
        }
    }
}
