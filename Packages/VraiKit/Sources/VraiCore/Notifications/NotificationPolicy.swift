import Foundation

public struct NotificationPolicy: Sendable, Equatable {
    public static let grace: TimeInterval = 2
    public static let longCommand: TimeInterval = 10

    public var enabled: Bool
    public var categories: Set<VraiNotification.Category>
    public var authorized: Bool
    public var sound: Bool
    public var alertsOnly: Bool

    public init(enabled: Bool, categories: Set<VraiNotification.Category>, authorized: Bool = true, sound: Bool = true, alertsOnly: Bool = false) {
        self.enabled = enabled
        self.categories = categories
        self.authorized = authorized
        self.sound = sound
        self.alertsOnly = alertsOnly
    }

    public func delivers(_ category: VraiNotification.Category, level: VraiNotification.Level = .alert, unfocusedSince: Date?, now: Date = Date()) -> Bool {
        guard enabled, authorized, categories.contains(category), let unfocusedSince else { return false }
        if alertsOnly, level == .quiet { return false }
        return now.timeIntervalSince(unfocusedSince) >= Self.grace
    }

    public func prepared(_ notification: VraiNotification) -> VraiNotification {
        var notification = notification
        notification.sound = sound && notification.level == .alert
        return notification
    }
}

extension Preferences {
    public static func notifyKey(_ category: VraiNotification.Category) -> ReferenceWritableKeyPath<Preferences, Bool> {
        switch category {
        case .sync: \.notifySync
        case .needsYou: \.notifyNeedsYou
        case .history: \.notifyHistory
        case .fetch: \.notifyFetch
        case .checks: \.notifyChecks
        case .maintenance: \.notifyMaintenance
        }
    }

    public func notificationPolicy(authorized: Bool = true, alertsOnly: Bool = false) -> NotificationPolicy {
        let categories = VraiNotification.Category.allCases.filter { self[keyPath: Self.notifyKey($0)] }
        return NotificationPolicy(enabled: notify, categories: Set(categories), authorized: authorized, sound: notifySound, alertsOnly: alertsOnly)
    }
}
