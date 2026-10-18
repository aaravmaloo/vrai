import AppKit
import SwiftUI
import UserNotifications
import VraiCore
import VraiGit

struct NotificationAction {
    var button: VraiNotification.Button
    var perform: @MainActor () -> Void

    init(_ id: String, _ title: String, opensApp: Bool = true, destructive: Bool = false, perform: @escaping @MainActor () -> Void) {
        button = VraiNotification.Button(id: id, title: title, opensApp: opensApp, destructive: destructive)
        self.perform = perform
    }
}

@MainActor
final class NotificationHub {
    static let shared = NotificationHub()
    static let remembered = 100

    let permission = NotificationPermission()
    var openWindow: OpenWindowAction?
    var now: () -> Date = Date.init
    var notifierOverride: (any Notifier)?
    private var handlers: [String: [String: @MainActor () -> Void]] = [:]
    private var order: [String] = []
    private var unseen: [String: [String: Int]] = [:]
    private var pending: [String: VraiNotification.Target] = [:]
    private var waiting: Set<String> = []
    private var seenOnReturn: [String: Set<String>] = [:]
    var focusAlertsOnly: () -> Bool = { NotificationFocus.alertsOnly }
    private var observing = false
    var appInactiveSince: Date?

    var notifier: any Notifier { notifierOverride ?? SyncHub.shared.notifier }

    func start() {
        guard !observing else { return }
        observing = true
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appInactiveSince = self?.now() }
        }
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appInactiveSince = nil }
        }
    }

    func deliversWhileAway(_ category: VraiNotification.Category, level: VraiNotification.Level = .alert, preferences: Preferences) -> Bool {
        policy(preferences).delivers(category, level: level, unfocusedSince: appInactiveSince, now: now())
    }

    func configure(launch: LaunchOptions) {
        guard launch.sandbox == nil, !permission.live else { return }
        permission.live = true
        UNUserNotificationCenter.current().delegate = SyncHub.shared
    }

    func policy(_ preferences: Preferences) -> NotificationPolicy {
        preferences.notificationPolicy(authorized: permission.authorized, alertsOnly: focusAlertsOnly())
    }

    func delivers(_ category: VraiNotification.Category, level: VraiNotification.Level = .alert, window: WindowModel) -> Bool {
        policy(window.preferences).delivers(category, level: level, unfocusedSince: window.sync.unfocusedSince, now: now())
    }

    func post(_ notification: VraiNotification, preferences: Preferences, actions: [NotificationAction] = []) {
        var notification = notification
        notification.buttons = actions.map(\.button)
        remember(notification.id, actions)
        let prepared = policy(preferences).prepared(notification)
        let notifier = self.notifier
        Task { await notifier.post(prepared) }
    }

    @discardableResult
    func deliver(_ notification: VraiNotification, window: WindowModel, actions: [NotificationAction] = [], clearsOnReturn: Bool = false) -> Bool {
        guard delivers(notification.category, level: notification.level, window: window) else { return false }
        post(notification, preferences: window.preferences, actions: actions)
        if clearsOnReturn { seenOnReturn[SyncModel.normalized(window.reference.path), default: []].insert(notification.id) }
        return true
    }

    static func notification(for toast: Toast, category: VraiNotification.Category, window: WindowModel) -> VraiNotification {
        let body = [toast.message, toast.detail].compactMap { $0 }.joined(separator: "\n")
        let level: VraiNotification.Level = toast.tone == .danger || toast.tone == .warning ? .alert : .quiet
        return VraiNotification(category: category, repository: window.reference.path, title: window.repositoryName, body: body, level: level, target: toast.target)
    }

    func route(_ toast: Toast, window: WindowModel) -> Bool {
        guard !toast.busy, let category = toast.category else { return false }
        var actions: [NotificationAction] = []
        if toast.notifyButton, let title = toast.action, let perform = toast.onAction {
            actions.append(NotificationAction("action", title, perform: perform))
        }
        guard deliver(Self.notification(for: toast, category: category, window: window), window: window, actions: actions) else { return false }
        window.router.handoffUntil = .distantPast
        return true
    }

    func remember(_ id: String, _ actions: [NotificationAction]) {
        guard !actions.isEmpty else { return }
        if handlers[id] == nil { order.append(id) }
        handlers[id] = Dictionary(actions.map { ($0.button.id, $0.perform) }) { first, _ in first }
        while order.count > Self.remembered {
            handlers[order.removeFirst()] = nil
        }
    }

    func respond(id: String, action: String, repository: String?, target: String?) {
        if let perform = handlers[id]?[action] {
            handlers[id] = nil
            order.removeAll { $0 == id }
            perform()
            return
        }
        NSApp?.activate()
        guard let repository, !repository.isEmpty else { return }
        reveal(repository, target: target.flatMap(VraiNotification.Target.init(link:)))
    }

    func reveal(_ path: String, target: VraiNotification.Target?) {
        if let model = SyncHub.shared.model(path: path) {
            openWindow?(value: model.window.reference)
            Self.navigate(model.window, to: target)
            return
        }
        guard let app = SyncHub.shared.app, let openWindow else { return }
        Task {
            guard let reference = try? await app.open(path: path) else { return }
            if let target { pending[SyncModel.normalized(reference.path)] = target }
            openWindow(value: reference)
        }
    }

    func appeared(_ window: WindowModel) {
        guard let target = pending.removeValue(forKey: SyncModel.normalized(window.reference.path)) else { return }
        Self.navigate(window, to: target)
    }

    static func navigate(_ window: WindowModel, to target: VraiNotification.Target?) {
        switch target {
        case .history?:
            window.show(.history)
        case .changes?:
            window.show(.changes)
        case .conflicts?:
            window.showConflicts()
        case .console?:
            window.console.open = true
        case .ref(let name)?:
            window.show(.history)
            window.store.showRef(name)
        case .commit(let sha)?:
            window.show(.history)
            if let id = OID(sha) { window.store.selectCommit(id, scroll: true) }
        case nil:
            break
        }
    }

    static func alertID(_ window: WindowModel, slot: String) -> String { "alert:" + slot + ":" + window.reference.path }
    static func promptID(_ window: WindowModel) -> String { "prompt:" + window.reference.path }

    func alertShown(title: String, message: String?, actions: [AlertAction], buttons: Bool = true, slot: String, window: WindowModel, close: @escaping @MainActor () -> Void) {
        guard delivers(.needsYou, window: window) else { return }
        let id = Self.alertID(window, slot: slot)
        var choices: [NotificationAction] = []
        if buttons, let first = actions.first(where: { $0.role == .standard && $0.enabled }), let perform = first.action {
            choices.append(NotificationAction("choice", first.title, opensApp: first.title.hasSuffix("\u{2026}")) {
                close()
                perform()
            })
        }
        let body = [title, message].compactMap { $0 }.joined(separator: "\n")
        post(VraiNotification(id: id, category: .needsYou, repository: window.reference.path, title: window.repositoryName, body: body, level: .alert), preferences: window.preferences, actions: choices)
        waiting.insert(id)
        NSApp?.requestUserAttention(.informationalRequest)
    }

    func alertClosed(slot: String, window: WindowModel) {
        withdraw(Self.alertID(window, slot: slot))
    }

    static func promptCopy(_ request: AskpassRequest) -> String {
        let host = request.host ?? String(localized: "the remote", bundle: .module)
        return switch request.kind {
        case .password: String(localized: "git is waiting for your password for \(host).", bundle: .module)
        case .username: String(localized: "git is waiting for your username for \(host).", bundle: .module)
        case .passphrase: String(localized: "git is waiting for the passphrase of your SSH key.", bundle: .module)
        case .confirm, .other: String(localized: "git is waiting for you to answer a question.", bundle: .module)
        }
    }

    func promptShown(_ request: AskpassRequest, window: WindowModel) {
        guard delivers(.needsYou, window: window) else { return }
        let id = Self.promptID(window)
        post(VraiNotification(id: id, category: .needsYou, repository: window.reference.path, title: window.repositoryName, body: Self.promptCopy(request), level: .alert), preferences: window.preferences)
        waiting.insert(id)
        NSApp?.requestUserAttention(.criticalRequest)
    }

    func promptAnswered(window: WindowModel) {
        withdraw(Self.promptID(window))
    }

    static func stoppedID(_ window: WindowModel) -> String { "stopped:" + window.reference.path }

    func track(_ id: String) {
        waiting.insert(id)
    }

    func stateChanged(_ snapshot: RepositorySnapshot?, window: WindowModel) {
        guard snapshot?.state.isOperationInProgress != true else { return }
        withdraw(Self.stoppedID(window))
    }

    func withdraw(_ id: String) {
        guard waiting.remove(id) != nil else { return }
        handlers[id] = nil
        order.removeAll { $0 == id }
        let notifier = self.notifier
        Task { await notifier.remove([id]) }
    }

    func unseenCommits(_ counts: [String: Int], window: WindowModel) -> [String: Int] {
        let key = SyncModel.normalized(window.reference.path)
        let merged = (unseen[key] ?? [:]).merging(counts.filter { $0.value > 0 }, uniquingKeysWith: +)
        unseen[key] = merged
        return merged
    }

    func focused(_ window: WindowModel) {
        let key = SyncModel.normalized(window.reference.path)
        var ids = Array(seenOnReturn.removeValue(forKey: key) ?? []).sorted()
        if unseen.removeValue(forKey: key) != nil { ids.insert("fetch:" + window.reference.path, at: 0) }
        guard !ids.isEmpty else { return }
        for id in ids {
            handlers[id] = nil
            order.removeAll { $0 == id }
        }
        let notifier = self.notifier
        Task { await notifier.remove(ids) }
    }

    func sendTest(_ preferences: Preferences, repository: String?) {
        let note = VraiNotification(
            id: "test",
            category: .sync,
            repository: repository ?? "",
            title: String(localized: "Vrai", bundle: .module),
            body: String(localized: "Notifications from Vrai look like this. Click one to jump to its repository.", bundle: .module),
            level: .alert,
            target: repository == nil ? nil : .history
        )
        let permission = self.permission
        Task {
            if permission.status == .notAsked { await permission.request() }
            post(note, preferences: preferences)
        }
    }
}

struct FetchAnnouncer: Notifier {
    func post(_ notification: VraiNotification) async {
        await MainActor.run { FetchAnnouncer.announce(notification) }
    }

    @MainActor static func announce(_ notification: VraiNotification) {
        guard let model = SyncHub.shared.model(path: notification.repository) else { return }
        let hub = NotificationHub.shared
        if notification.isUpstreamChange {
            var note = notification
            note.repository = model.window.reference.path
            note.id = "upstream:" + note.repository
            if hub.deliver(note, window: model.window) { return }
            let lines = notification.body.split(separator: "\n").map(String.init)
            let rest = lines.dropFirst().joined(separator: ", ")
            model.toasts.show(Toast(tone: .warning, message: lines.first ?? "", detail: rest.isEmpty ? nil : rest, icon: "exclamationmark.triangle"))
            return
        }
        if hub.delivers(.fetch, level: .quiet, window: model.window) {
            let counts = hub.unseenCommits(notification.newCommits, window: model.window)
            var actions: [NotificationAction] = []
            if model.currentBranch?.upstream.map({ counts[$0] ?? 0 > 0 }) == true {
                actions.append(NotificationAction("pull", String(localized: "Pull", bundle: .module), opensApp: false) { [weak model] in model?.pull() })
            }
            hub.post(.fetched(repository: model.window.reference.path, name: model.window.repositoryName, newCommits: counts), preferences: model.preferences, actions: actions)
            return
        }
        IslandNotifier.show(notification)
    }
}
