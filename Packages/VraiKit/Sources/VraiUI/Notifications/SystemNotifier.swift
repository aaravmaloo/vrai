import AppKit
import Observation
import UserNotifications
import VraiCore

struct SystemNotifier: Notifier {
    func post(_ notification: VraiNotification) async {
        guard await NotificationPermission.authorize() else { return }
        let category = await NotificationButtons.shared.register(notification.buttons)
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.threadIdentifier = notification.repository
        content.categoryIdentifier = category
        content.interruptionLevel = notification.level == .alert ? .active : .passive
        if notification.sound { content.sound = .default }
        var info = ["repository": notification.repository]
        if let target = notification.target { info["target"] = target.link }
        content.userInfo = info
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: notification.id, content: content, trigger: nil))
    }

    func remove(_ ids: [String]) async {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }
}

struct LogNotifier: Notifier {
    let log: URL

    func post(_ notification: VraiNotification) async {
        let buttons = notification.buttons.map(\.title).joined(separator: ",")
        let body = notification.body.replacingOccurrences(of: "\n", with: " | ")
        append([notification.title, body, notification.category.rawValue, notification.id, buttons, notification.target?.link ?? ""].joined(separator: "\t"))
    }

    func remove(_ ids: [String]) async {
        for id in ids { append(["removed", id].joined(separator: "\t")) }
    }

    func append(_ line: String) {
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: log) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: log)
        }
    }
}

@MainActor
final class NotificationButtons {
    static let shared = NotificationButtons()
    private var categories: [String: UNNotificationCategory] = [:]

    static func identifier(_ buttons: [VraiNotification.Button]) -> String {
        buttons.isEmpty ? "plain" : "buttons:" + buttons.map(\.id).joined(separator: ",")
    }

    func register(_ buttons: [VraiNotification.Button]) -> String {
        let id = Self.identifier(buttons)
        guard categories[id] == nil else { return id }
        let actions = buttons.map { button in
            var options: UNNotificationActionOptions = []
            if button.opensApp { options.insert(.foreground) }
            if button.destructive { options.insert(.destructive) }
            return UNNotificationAction(identifier: button.id, title: button.title, options: options)
        }
        categories[id] = UNNotificationCategory(identifier: id, actions: actions, intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories.values))
        return id
    }
}

@MainActor
@Observable
final class NotificationPermission {
    enum Status: Equatable {
        case unknown
        case notAsked
        case allowed
        case denied
    }

    var status: Status = .unknown
    @ObservationIgnored var live = false
    @ObservationIgnored var asked = false

    var authorized: Bool { status != .denied }

    func refresh() async {
        guard live else {
            status = .allowed
            return
        }
        status = Self.status(await Self.current())
    }

    func request() async {
        asked = true
        guard live else {
            status = .allowed
            return
        }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refresh()
    }

    func askOnce() {
        guard live, !asked, status == .notAsked || status == .unknown else { return }
        asked = true
        Task {
            await refresh()
            if status == .notAsked { await request() }
        }
    }

    static func status(_ value: UNAuthorizationStatus) -> Status {
        switch value {
        case .notDetermined: .notAsked
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .allowed
        @unknown default: .unknown
        }
    }

    nonisolated static func current() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    nonisolated static func authorize() async -> Bool {
        switch await current() {
        case .notDetermined:
            return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) == true
        case .denied:
            return false
        default:
            return true
        }
    }

    static func openFocusSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=" + id) else { return }
        NSWorkspace.shared.open(url)
    }
}
