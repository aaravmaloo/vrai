import AppKit
import Foundation
import SwiftUI
import Testing
import VraiCore
import VraiGit
@testable import VraiUI

enum PerfFixture {
    static var hasLarge: Bool {
        let root = ProcessInfo.processInfo.environment["VRAI_SANDBOX"] ?? ""
        return !root.isEmpty && FileManager.default.fileExists(atPath: root + "/fixtures/large/monorepo/.git")
    }
}

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["VRAI_PERF"] == "1" && PerfFixture.hasLarge, "run Scripts/perf.sh"))
struct PerformanceViewTests {
    static let sandbox = ProcessInfo.processInfo.environment["VRAI_SANDBOX"] ?? ""
    static let large = sandbox + "/fixtures/large/monorepo"
    static let reportURL = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "build/perf/views.txt")
    static let frame120 = 1000.0 / 120

    static func record(_ line: String) {
        print("PERF " + line)
        try? FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: reportURL) {
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            try? handle.close()
        } else {
            try? Data((line + "\n").utf8).write(to: reportURL)
        }
    }

    @MainActor
    struct Window {
        let app: AppModel
        let store: RepositoryStore
        let model: WindowModel
        let host: NSView
        let window: NSWindow

        func draw() {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }

        func close() {
            store.close()
            window.close()
        }
    }

    static var load: String {
        var samples = [Double](repeating: 0, count: 3)
        return getloadavg(&samples, 3) > 0 ? String(format: "%.1f", samples[0]) : "-"
    }

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    static func turnRunLoop(_ seconds: Double = 0) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func settle(_ seconds: Double) async {
        let clock = ContinuousClock()
        let end = clock.now + .milliseconds(Int(seconds * 1000))
        while clock.now < end {
            turnRunLoop(0.005)
            await Task.yield()
        }
    }

    static func until(_ timeout: Double = 10, _ condition: () -> Bool) async {
        let clock = ContinuousClock()
        let end = clock.now + .milliseconds(Int(timeout * 1000))
        while !condition(), clock.now < end {
            turnRunLoop(0.001)
            await Task.yield()
        }
    }

    static func openLarge() async throws -> Window {
        let app = AppModel(launch: LaunchOptions(sandbox: URL(filePath: sandbox), appearance: .light, now: Date(timeIntervalSince1970: 1_791_720_000), capture: true))
        let reference = app.request(RepositoryReference(url: URL(filePath: large, directoryHint: .isDirectory)))
        let store = try app.store(for: reference)
        let model = WindowModel(reference: reference, store: store, preferences: app.preferences, now: app.launch.now)
        let host = NSHostingView(rootView: RepositoryShell().environment(model).environment(store).environment(model.toasts).environment(model.preferences).environment(app))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 780), styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        await store.open(watch: false)
        let opened = Window(app: app, store: store, model: model, host: host, window: window)
        opened.draw()
        await settle(0.5)
        return opened
    }

    static func listScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView, scroll.documentView is CommitTableView { return scroll }
        for subview in view.subviews {
            if let found = listScrollView(in: subview) { return found }
        }
        return nil
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return .infinity }
        return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }

    @Test func scrollingTenThousandRowsOfLarge() async throws {
        let opened = try await Self.openLarge()
        defer { opened.close() }
        let scroll = try #require(Self.listScrollView(in: opened.host))
        let meter = BusyMeter()
        meter.install()
        defer { meter.remove() }
        let clock = ContinuousClock()
        let frame = Duration.microseconds(8333)
        let rowHeight = (scroll.documentView as? NSTableView)?.rowHeight ?? 28
        let target = rowHeight * 10_000
        let step: CGFloat = 60
        var samples: [Double] = []
        var travelled: CGFloat = 0
        var direction: CGFloat = 1
        var deadline = clock.now
        _ = meter.take()
        while travelled < target, samples.count < 20_000 {
            deadline = max(deadline + frame, clock.now)
            let limit = max(0, (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height)
            let previous = scroll.contentView.bounds.origin.y
            let waiting = direction > 0 && previous >= limit && opened.store.history.commits.count < 10_000 && !opened.store.history.isComplete
            if !waiting {
                if direction > 0, previous >= limit { direction = -1 } else if direction < 0, previous <= 0 { direction = 1 }
                let next = min(max(previous + step * direction, 0), limit)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: next))
                scroll.reflectScrolledClipView(scroll.contentView)
                travelled += abs(next - previous)
            }
            opened.draw()
            try await Task.sleep(until: deadline, clock: clock)
            samples.append(meter.take())
        }
        let slow = samples.filter { $0 > Self.frame120 }
        let sorted = samples.sorted()
        let rows = Int(travelled / rowHeight)
        let loaded = opened.store.history.commits.count
        Self.record(String(format: "history scrolling on large, in process at 120 Hz pacing: %d of %d frames with over 8.3 ms of main-thread work (median %.2f ms, p99 %.2f ms, worst %.2f ms) while scrolling %d rows, %d commits loaded, load %@ (budget: none over 8.3 ms)", slow.count, samples.count, Self.median(samples), sorted[sorted.count * 99 / 100], sorted.last ?? 0, rows, loaded, Self.load))
        #expect(rows >= 10_000)
        #expect(loaded >= 10_000)
        #expect(slow.isEmpty)
    }

    @Test func selectingACommitAndTheBigDiff() async throws {
        let opened = try await Self.openLarge()
        defer { opened.close() }
        let store = opened.store
        let big = try #require(store.history.commits.first { $0.subject.hasPrefix("Generated: add the lexer tables") }?.id)
        let small = try #require(store.history.commits.first { $0.subject.hasPrefix("Module22: refactor patch builder") }?.id)
        let clock = ContinuousClock()
        var selects: [Double] = []
        var diffs: [Double] = []
        for round in 0..<7 {
            for id in [small, big] {
                let start = clock.now
                opened.model.select(.commit(id))
                opened.draw()
                await Self.until { store.detail?.commit.id == id && store.detailState == .loaded }
                opened.draw()
                let shown = clock.now
                await Self.until { store.patchState == .loaded }
                opened.draw()
                let drawn = clock.now
                if round > 0 { selects.append(Self.milliseconds(shown - start)) }
                if round > 0, id == big {
                    #expect(store.patch?.hunks.reduce(0) { $0 + $1.lines.count } == 5000)
                    diffs.append(Self.milliseconds(drawn - shown))
                }
                await Self.settle(0.2)
            }
        }
        Self.record(String(format: "select a commit to file list drawn on large, in process: median %.1f ms, worst %.1f ms (%d selections, load %@, budget 100 ms)", Self.median(selects), selects.max() ?? 0, selects.count, Self.load))
        Self.record(String(format: "diff of the 5,000-line file to first lines drawn, in process: median %.1f ms, worst %.1f ms (%d runs, budget 100 ms)", Self.median(diffs), diffs.max() ?? 0, diffs.count))
        #expect(Self.median(selects) < 100)
        #expect(Self.median(diffs) < 100)
    }
}

@MainActor
final class BusyMeter {
    var busy: Double = 0
    private var started: CFAbsoluteTime?
    private var observer: CFRunLoopObserver?

    func install() {
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { [weak self] _, activity in
            MainActor.assumeIsolated { self?.note(activity) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }

    func take() -> Double {
        defer { busy = 0 }
        return busy
    }

    func remove() {
        if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
        observer = nil
    }

    private func note(_ activity: CFRunLoopActivity) {
        let now = CFAbsoluteTimeGetCurrent()
        if activity == .afterWaiting {
            started = now
        } else if let started {
            busy += (now - started) * 1000
            self.started = nil
        }
    }
}
