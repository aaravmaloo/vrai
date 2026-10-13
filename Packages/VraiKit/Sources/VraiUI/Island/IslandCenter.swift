import AppKit
import LocalAuthentication
import Observation
import SwiftUI
import VraiCore

public struct IslandAction: Identifiable {
    public let id = UUID()
    public var title: String
    public var prominent = false
    public var activates = true
    public var perform: @MainActor () -> Void

    public init(title: String, prominent: Bool = false, activates: Bool = true, perform: @escaping @MainActor () -> Void) {
        self.title = title
        self.prominent = prominent
        self.activates = activates
        self.perform = perform
    }
}

public struct IslandRow: Identifiable, Equatable {
    public var id: String
    public var title: String
    public var detail: String?
    public var state: CheckState

    public init(id: String, title: String, detail: String? = nil, state: CheckState) {
        self.id = id
        self.title = title
        self.detail = detail
        self.state = state
    }
}

public struct IslandActivity: Identifiable {
    public enum Phase: Equatable {
        case running
        case success
        case failure
        case warning
        case info
        case authenticating
        case authenticated
        case paused
    }

    public var id: UUID
    public var phase: Phase
    public var title: String
    public var detail: String?
    public var icon: String?
    public var source: String?
    public var progress: Double?
    public var badge: String?
    public var tint: Tone?
    public var rows: [IslandRow] = []
    public var actions: [IslandAction] = []
    public var linger: TimeInterval?
    public var attention = false
    public var accessory: String?
    public var context: LAContext?

    public init(id: UUID = UUID(), phase: Phase, title: String, detail: String? = nil, icon: String? = nil, source: String? = nil, progress: Double? = nil, badge: String? = nil, tint: Tone? = nil, rows: [IslandRow] = [], actions: [IslandAction] = [], linger: TimeInterval? = nil, attention: Bool = false) {
        self.id = id
        self.phase = phase
        self.title = title
        self.detail = detail
        self.icon = icon
        self.source = source
        self.progress = progress
        self.badge = badge
        self.tint = tint
        self.rows = rows
        self.actions = actions
        self.linger = linger
        self.attention = attention
    }

    var wantsExpand: Bool { attention || phase == .authenticating }

    var compactDuration: TimeInterval {
        if let linger { return linger }
        switch phase {
        case .failure: return 6
        case .warning: return 5
        case .authenticated: return 1.4
        case .success, .info: return actions.isEmpty ? 3.4 : 5
        case .running, .authenticating, .paused: return .infinity
        }
    }

    var isLive: Bool { phase == .running || phase == .authenticating || phase == .paused }

    var duration: TimeInterval {
        if let linger { return linger }
        switch phase {
        case .failure: return actions.isEmpty ? 7 : 10
        case .warning: return 7
        case .authenticated: return 1.1
        case .success, .info: return actions.isEmpty ? 3.6 : 7
        case .running, .authenticating, .paused: return .infinity
        }
    }
}

struct IslandMetrics: Equatable {
    var notch: Bool
    var notchWidth: CGFloat
    var height: CGFloat

    static let wing: CGFloat = Vrai.Space.s40
    static let ear: CGFloat = Vrai.Space.s8
    static let expandedWidth: CGFloat = Vrai.Size.field + Vrai.Space.s64 + Vrai.Space.s40
    static let panelWidth: CGFloat = expandedWidth + Vrai.Space.s64 * 2
    static let panelHeight: CGFloat = Vrai.Size.sheet * 0.6
    static let detachedWidth: CGFloat = Vrai.Space.s64 + Vrai.Space.s48

    static let fallback = IslandMetrics(notch: false, notchWidth: 0, height: Vrai.Size.controlLg - Vrai.Space.s4)

    var compactWidth: CGFloat {
        notch ? notchWidth + Self.wing * 2 + Self.ear * 2 : Self.detachedWidth
    }

    var expandedWidth: CGFloat {
        max(Self.expandedWidth, compactWidth + Vrai.Space.s48)
    }
}

@MainActor
@Observable
public final class IslandCenter {
    public static let shared = IslandCenter()

    public private(set) var activities: [IslandActivity] = []
    public internal(set) var hovering = false {
        didSet {
            guard hovering != oldValue else { return }
            if !hovering { extendAfterHover() }
            refresh()
        }
    }
    public private(set) var expanded = false
    public internal(set) var presented = false
    var holdCompact = false
    public private(set) var shown: IslandActivity?
    var metrics = IslandMetrics.fallback
    var frame: CGRect = .zero
    public var mode: Preferences.Island = .off {
        didSet { if mode == .off { clear() } }
    }

    @ObservationIgnored var expandUntil: [UUID: Date] = [:]
    @ObservationIgnored var removeAt: [UUID: Date] = [:]
    @ObservationIgnored var leaving: Set<UUID> = []
    @ObservationIgnored lazy var controller = IslandController(center: self)
    @ObservationIgnored var escape: Any?
    @ObservationIgnored var stubCancelled = false
    @ObservationIgnored let headless: Bool
    @ObservationIgnored var notchOverride: Bool?
    @ObservationIgnored public var preferences: Preferences?

    public enum Feature {
        case sync
        case states
        case fetch
        case checks
        case auth
    }

    public func allows(_ feature: Feature) -> Bool {
        guard isActive else { return false }
        guard let preferences else { return true }
        switch feature {
        case .sync: return preferences.islandSync
        case .states: return preferences.islandStates
        case .fetch: return preferences.islandFetch
        case .checks: return preferences.islandChecks
        case .auth: return preferences.islandAuth
        }
    }

    var hoverOpens: Bool { preferences?.islandHover ?? true }
    var attentionOpens: Bool { preferences?.islandAttention ?? true }
    var lingerScale: Double { preferences?.islandLinger.scale ?? 1 }
    var screenChoice: Preferences.IslandScreen { preferences?.islandScreen ?? .window }

    init(headless: Bool = false) {
        self.headless = headless
    }

    public var current: IslandActivity? { activities.last { !leaving.contains($0.id) } ?? activities.last }
    public var isActive: Bool { mode != .off }
    public var hasNotch: Bool { notchOverride ?? (headless ? false : controller.peekMetrics().notch) }

    func shouldExpand(at now: Date) -> Bool {
        guard let current else { return false }
        if current.phase == .authenticating { return true }
        if hovering { return true }
        if let until = expandUntil[current.id] { return until > now }
        return false
    }

    var stage: IslandStage {
        guard presented else { return .hidden }
        return expanded && !holdCompact ? .expanded : .compact
    }

    func animate(_ animation: Animation, _ body: () -> Void) {
        if headless { body() } else { withAnimation(IslandStyle.animation(animation), body) }
    }

    func refresh(_ now: Date = Date()) {
        let next = shouldExpand(at: now)
        guard next != expanded else { return }
        animate(next ? IslandStyle.grow : IslandStyle.shrink) { expanded = next }
    }

    func syncShown() {
        guard let current else { return }
        if shown?.id != current.id || shown?.phase != current.phase || shown?.title != current.title {
            animate(IslandStyle.morph) { shown = current }
        } else {
            shown = current
        }
    }

    public func contains(_ id: UUID) -> Bool {
        activities.contains { $0.id == id }
    }

    @discardableResult
    public func show(_ activity: IslandActivity, expand: TimeInterval? = nil) -> UUID {
        guard mode != .off else { return activity.id }
        let gone = leaving
        leaving = []
        for id in gone { forget(id) }
        schedule(activity, expand: expand)
        animate(IslandStyle.morph) {
            activities.removeAll { $0.id == activity.id || !$0.isLive || gone.contains($0.id) }
            activities.append(activity)
            shown = current
        }
        refresh()
        if headless { presented = true } else { controller.present() }
        announce(activity)
        return activity.id
    }

    public func update(_ id: UUID, _ change: (inout IslandActivity) -> Void) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        change(&activities[index])
        syncShown()
    }

    public func finish(_ id: UUID, _ change: (inout IslandActivity) -> Void) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        var activity = activities[index]
        change(&activity)
        activities.remove(at: index)
        leaving.remove(id)
        _ = show(activity)
    }

    public func dismiss(_ id: UUID, after delay: TimeInterval = 0.3) {
        guard contains(id) else { return }
        leaving.insert(id)
        removeAt[id] = Date().addingTimeInterval(delay)
        expandUntil[id] = nil
        refresh()
    }

    func remove(_ id: UUID) {
        activities.removeAll { $0.id == id }
        forget(id)
        if activities.isEmpty {
            hovering = false
            if headless {
                expanded = false
                presented = false
                return
            }
            animate(IslandStyle.shrink) { expanded = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                guard let self, self.activities.isEmpty else { return }
                self.animate(IslandStyle.shrink) { self.presented = false }
            }
            controller.hideSoon()
        } else {
            syncShown()
        }
    }

    func forget(_ id: UUID) {
        expandUntil[id] = nil
        removeAt[id] = nil
        leaving.remove(id)
    }

    public func clear() {
        for activity in activities where activity.phase == .authenticating { activity.context?.invalidate() }
        activities = []
        expandUntil = [:]
        removeAt = [:]
        leaving = []
        hovering = false
        expanded = false
        presented = false
        shown = nil
        if !headless { controller.hide() }
    }

    func schedule(_ activity: IslandActivity, expand: TimeInterval?) {
        let now = Date()
        let open = expand != nil || (activity.wantsExpand && (attentionOpens || activity.phase == .authenticating))
        let scale = lingerScale
        if activity.isLive {
            expandUntil[activity.id] = open ? now.addingTimeInterval(expand ?? 4) : nil
            removeAt[activity.id] = nil
        } else if open {
            let duration = (expand ?? activity.duration) * scale
            expandUntil[activity.id] = now.addingTimeInterval(duration)
            removeAt[activity.id] = now.addingTimeInterval(duration + 1.8)
        } else {
            expandUntil[activity.id] = nil
            removeAt[activity.id] = now.addingTimeInterval(activity.compactDuration * scale)
        }
    }

    func peek() {
        guard let current else { return }
        let now = Date()
        let open = expanded
        expandUntil[current.id] = open ? now : now.addingTimeInterval(6 * lingerScale)
        if !current.isLive, let remove = removeAt[current.id] {
            removeAt[current.id] = max(remove, now.addingTimeInterval(open ? 1.5 : 7 * lingerScale))
        }
        refresh(now)
    }

    func extendAfterHover() {
        let now = Date()
        for activity in activities where !activity.isLive {
            removeAt[activity.id] = max(removeAt[activity.id] ?? now, now.addingTimeInterval(1.6))
            expandUntil[activity.id] = max(expandUntil[activity.id] ?? now, now.addingTimeInterval(0.5))
        }
    }

    func tick(_ now: Date) {
        for (id, date) in removeAt where date <= now && (!hovering || leaving.contains(id)) {
            remove(id)
        }
        refresh(now)
    }

    func perform(_ action: IslandAction, in activity: IslandActivity) {
        if action.activates { NSApp.activate() }
        if activity.phase != .authenticating, activity.phase != .paused { dismiss(activity.id, after: 0.15) }
        action.perform()
    }

    func announce(_ activity: IslandActivity) {
        let text = activity.detail.map { activity.title + ". " + $0 } ?? activity.title
        AccessibilityNotification.Announcement(text).post()
    }

    func watchEscape(_ on: Bool) {
        if on, escape == nil {
            escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53 else { return event }
                let handled = MainActor.assumeIsolated { IslandCenter.shared.cancelAuthentication() }
                return handled ? nil : event
            }
        } else if !on, let escape {
            NSEvent.removeMonitor(escape)
            self.escape = nil
        }
    }

    @discardableResult
    func cancelAuthentication() -> Bool {
        guard let activity = activities.last(where: { $0.phase == .authenticating }) else { return false }
        if let context = activity.context { context.invalidate() } else { stubCancelled = true }
        return true
    }
}
