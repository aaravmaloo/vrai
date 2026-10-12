import AppKit
import QuartzCore
import SwiftUI
import VraiCore

extension View {
    func perfEnd(_ name: String, when ready: Bool, detail: @autoclosure @escaping () -> String? = nil) -> some View {
        modifier(PerfEnd(name: name, ready: ready, detail: detail))
    }

    func perfLaunch(_ name: String) -> some View {
        modifier(PerfLaunch(name: name))
    }

    func perfFrames(_ name: String) -> some View {
        modifier(PerfFrames(name: name))
    }
}

struct PerfEnd: ViewModifier {
    let name: String
    let ready: Bool
    let detail: () -> String?

    func body(content: Content) -> some View {
        if PerfLog.isEnabled {
            content
                .onAppear { if ready { PerfLog.endAfterCommit(name, detail: detail()) } }
                .onChange(of: ready) { _, value in if value { PerfLog.endAfterCommit(name, detail: detail()) } }
        } else {
            content
        }
    }
}

struct PerfLaunch: ViewModifier {
    let name: String

    func body(content: Content) -> some View {
        if PerfLog.isEnabled {
            content.onAppear {
                PerfLog.sinceLaunch(name + ".appear")
                DispatchQueue.main.async { PerfLog.sinceLaunch(name) }
            }
        } else {
            content
        }
    }
}

struct PerfFrames: ViewModifier {
    let name: String

    func body(content: Content) -> some View {
        if PerfLog.isEnabled {
            content.background(FrameMonitor(name: name))
        } else {
            content
        }
    }
}

struct FrameMonitor: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> FrameMonitorView {
        FrameMonitorView(name: name)
    }

    func updateNSView(_ nsView: FrameMonitorView, context: Context) {}
}

final class FrameMonitorView: NSView {
    let name: String
    weak var scrollView: NSScrollView?
    private var link: CADisplayLink?
    private var lastOrigin: CGFloat?
    private var lastTimestamp: CFTimeInterval?
    private var lastMove: CFTimeInterval = 0
    private var frames = 0
    private var dropped = 0
    private var worst: CFTimeInterval = 0
    private var distance: CGFloat = 0
    private var nominal: CFTimeInterval = 0
    private var observers: [CFRunLoopObserver] = []
    private var passStart: CFTimeInterval = 0
    private var passes = 0
    private var slowPasses = 0
    private var worstPass: CFTimeInterval = 0

    static let budget120: CFTimeInterval = 1.0 / 120

    init(name: String) {
        self.name = name
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else {
            flush()
            for observer in observers { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
            observers.removeAll()
            return
        }
        let link = displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        watchPasses()
    }

    private func watchPasses() {
        guard observers.isEmpty else { return }
        let start = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue, true, Int.min) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.passStart = CACurrentMediaTime() }
        }
        let end = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, Int.max) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.passEnded() }
        }
        for observer in [start, end].compactMap({ $0 }) {
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            observers.append(observer)
        }
    }

    private func passEnded() {
        guard passStart > 0, frames > 0 else { return }
        let now = CACurrentMediaTime()
        guard now - lastMove < 0.1 else { return }
        let duration = now - passStart
        passes += 1
        if duration > Self.budget120 { slowPasses += 1 }
        worstPass = max(worstPass, duration)
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let scroll = scrollView ?? enclosingScrollView else { return }
        let origin = scroll.contentView.bounds.origin.y
        let now = link.timestamp
        nominal = link.targetTimestamp - link.timestamp
        defer {
            lastOrigin = origin
            lastTimestamp = now
        }
        guard let lastOrigin, let lastTimestamp else { return }
        if origin != lastOrigin {
            let interval = now - lastTimestamp
            if frames > 0, nominal > 0 {
                let missed = Int((interval / nominal).rounded()) - 1
                if missed > 0 { dropped += missed }
                worst = max(worst, interval)
            }
            frames += 1
            distance += abs(origin - lastOrigin)
            lastMove = now
        } else if frames > 0, now - lastMove > 0.5 {
            flush()
        }
    }

    private func flush() {
        guard frames > 0 else { return }
        let hz = nominal > 0 ? Int((1 / nominal).rounded()) : 0
        PerfLog.record(name, Double(dropped), detail: "frames=\(frames) points=\(Int(distance)) worst=\(String(format: "%.1f", worst * 1000))ms hz=\(hz) passes=\(passes) slow120=\(slowPasses) worstpass=\(String(format: "%.1f", worstPass * 1000))ms")
        PerfLog.recordMemory("memory")
        frames = 0
        dropped = 0
        worst = 0
        distance = 0
        passes = 0
        slowPasses = 0
        worstPass = 0
    }
}
