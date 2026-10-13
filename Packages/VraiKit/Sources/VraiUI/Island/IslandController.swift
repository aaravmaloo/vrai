import AppKit
import SwiftUI
import VraiCore

final class IslandPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        appearance = NSAppearance(named: .darkAqua)
        setAccessibilityIdentifier("island-panel")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class IslandController {
    unowned let center: IslandCenter
    private var panel: IslandPanel?
    private var timer: Timer?
    private var hideTask: Task<Void, Never>?
    private var screen: NSScreen?

    init(center: IslandCenter) {
        self.center = center
    }

    static func metrics(for screen: NSScreen) -> IslandMetrics {
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return IslandMetrics(notch: true, notchWidth: max(width, Vrai.Space.s64 * 2), height: top)
        }
        let bar = screen.frame.maxY - screen.visibleFrame.maxY
        let height = bar > 0 ? bar : NSStatusBar.system.thickness
        return IslandMetrics(notch: false, notchWidth: 0, height: max(height, Vrai.Size.controlSm))
    }

    static func targetScreen(_ choice: Preferences.IslandScreen = .window) -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        let pointer = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        let notched = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        switch choice {
        case .builtIn:
            if let notched { return notched }
        case .pointer:
            if let pointer { return pointer }
        case .window:
            if NSApp.isActive, let screen = NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen { return screen }
        }
        return pointer ?? NSScreen.main ?? NSScreen.screens.first
    }

    func peekMetrics() -> IslandMetrics {
        (screen ?? Self.targetScreen(center.screenChoice)).map(Self.metrics(for:)) ?? .fallback
    }

    func present() {
        hideTask?.cancel()
        hideTask = nil
        let panel = self.panel ?? makePanel()
        let visible = panel.isVisible
        if !visible || screen == nil {
            guard let target = Self.targetScreen(center.screenChoice) else { return }
            screen = target
            center.metrics = Self.metrics(for: target)
            let size = CGSize(width: IslandMetrics.panelWidth, height: IslandMetrics.panelHeight)
            panel.setFrame(CGRect(x: target.frame.midX - size.width / 2, y: target.frame.maxY - size.height, width: size.width, height: size.height), display: false)
        }
        if !visible || !center.presented {
            center.presented = false
            center.holdCompact = true
            if !visible { panel.orderFrontRegardless() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                guard let self, !self.center.activities.isEmpty else { return }
                withAnimation(IslandStyle.animation(IslandStyle.drop)) { self.center.presented = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    guard let self else { return }
                    withAnimation(IslandStyle.animation(IslandStyle.grow)) { self.center.holdCompact = false }
                }
            }
        }
        startTimer()
        center.watchEscape(center.activities.contains { $0.phase == .authenticating })
    }

    func hideSoon() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, let self, self.center.activities.isEmpty else { return }
            self.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        timer?.invalidate()
        timer = nil
        panel?.ignoresMouseEvents = true
        panel?.orderOut(nil)
        screen = nil
        center.watchEscape(false)
    }

    private func makePanel() -> IslandPanel {
        let panel = IslandPanel()
        let host = IslandHostingView(rootView: IslandRoot(center: center))
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel
        return panel
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { _ in
            MainActor.assumeIsolated { IslandCenter.shared.controller.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func poll() {
        guard let panel else { return }
        center.watchEscape(center.activities.contains { $0.phase == .authenticating })
        let mouse = NSEvent.mouseLocation
        let local = CGPoint(x: mouse.x - panel.frame.minX, y: panel.frame.maxY - mouse.y)
        let inside = !center.activities.isEmpty && center.frame.insetBy(dx: -Vrai.Space.s4, dy: -Vrai.Space.s4).contains(local)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        let hover = inside && center.hoverOpens
        if center.hovering != hover { center.hovering = hover }
        center.tick(Date())
    }
}
