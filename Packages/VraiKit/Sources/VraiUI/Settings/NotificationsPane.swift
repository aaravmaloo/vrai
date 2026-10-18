import SwiftUI
import VraiCore

struct NotificationsPane: View {
    let context: SettingsContext
    @Environment(Preferences.self) private var preferences

    var permission: NotificationPermission { NotificationHub.shared.permission }
    var on: Bool { preferences.notify }

    static func title(_ category: VraiNotification.Category) -> String {
        switch category {
        case .sync: String(localized: "Push, pull, fetch and clone", bundle: .module)
        case .needsYou: String(localized: "When git needs you", bundle: .module)
        case .history: String(localized: "Merges, rebases and other history edits", bundle: .module)
        case .fetch: String(localized: "New commits from background fetch", bundle: .module)
        case .checks: String(localized: "CI results", bundle: .module)
        case .maintenance: String(localized: "Maintenance and long commands", bundle: .module)
        }
    }

    static func description(_ category: VraiNotification.Category) -> String {
        switch category {
        case .sync: String(localized: "When they finish or fail.", bundle: .module)
        case .needsYou: String(localized: "A sign-in, a passphrase, a rejected push or a decision waiting in the window.", bundle: .module)
        case .history: String(localized: "When they finish or stop on a conflict.", bundle: .module)
        case .fetch: String(localized: "When a fetch brings commits to a branch you track.", bundle: .module)
        case .checks: String(localized: "When checks pass or fail after you push.", bundle: .module)
        case .maintenance: String(localized: "Garbage collection, integrity checks, worktrees, submodules, saved archives and commands you typed that ran a while.", bundle: .module)
        }
    }

    func blocked(_ category: VraiNotification.Category) -> String? {
        switch category {
        case .fetch where !preferences.backgroundFetch || !preferences.notifications:
            String(localized: "Turn on background fetch and Tell me about new commits in General first.", bundle: .module)
        case .checks where !preferences.checks || !preferences.checksNotify:
            String(localized: "Turn on GitHub checks and Tell me when checks finish in General first.", bundle: .module)
        default:
            nil
        }
    }

    var body: some View {
        SettingsForm {
            if permission.status == .denied {
                Section {
                    SettingsCallout(
                        tone: .warning,
                        title: String(localized: "macOS is blocking notifications from Vrai", bundle: .module),
                        message: String(localized: "Turn on Allow notifications for Vrai in System Settings, then come back here.", bundle: .module)
                    ) {
                        Button(String(localized: "Open System Settings", bundle: .module)) { NotificationPermission.openSystemSettings() }
                            .controlSize(.small)
                            .accessibilityIdentifier("settings.notificationsSystem")
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            SettingsSection(String(localized: "Notifications", bundle: .module)) {
                SettingsRow(String(localized: "Notify me when Vrai isn't in front", bundle: .module), description: String(localized: "Results and requests go to Notification Center while you work in another app or window. Click one to jump to the repository.", bundle: .module)) {
                    SettingsSwitch(label: String(localized: "Notify me when Vrai isn't in front", bundle: .module), isOn: on, id: "settings.notify") { preferences.notify = $0 }
                }
                SettingsRow(String(localized: "Play a sound when something fails", bundle: .module), description: String(localized: "Finished work arrives quietly.", bundle: .module)) {
                    SettingsSwitch(label: String(localized: "Play a sound when something fails", bundle: .module), isOn: preferences.notifySound, id: "settings.notifySound", disabled: !on) { preferences.notifySound = $0 }
                }
                SettingsRow(String(localized: "Show a badge on the Dock icon", bundle: .module), description: String(localized: "Counts commits waiting to be pulled in open repositories, plus one for each whose CI is failing.", bundle: .module)) {
                    SettingsSwitch(label: String(localized: "Show a badge on the Dock icon", bundle: .module), isOn: preferences.dockBadge, id: "settings.dockBadge") { preferences.dockBadge = $0 }
                }
                SettingsRow(String(localized: "During a Focus", bundle: .module), description: String(localized: "Add Vrai as a Focus filter to hear only about failures and requests while that Focus is on.", bundle: .module)) {
                    Button(String(localized: "Open Focus Settings", bundle: .module)) { NotificationPermission.openFocusSettings() }
                        .controlSize(.small)
                        .accessibilityIdentifier("settings.notifyFocus")
                }
                SettingsRow(String(localized: "Test", bundle: .module), description: permission.status == .notAsked ? String(localized: "macOS asks once whether Vrai may send notifications.", bundle: .module) : String(localized: "Sends a sample so you can see how it looks.", bundle: .module)) {
                    Button(permission.status == .notAsked ? String(localized: "Allow notifications", bundle: .module) : String(localized: "Send a test notification", bundle: .module)) {
                        if permission.status == .notAsked {
                            Task { await permission.request() }
                        } else {
                            NotificationHub.shared.sendTest(preferences, repository: SettingsHub.shared.activeWindow?.reference.path)
                        }
                    }
                    .controlSize(.small)
                    .disabled(!on || permission.status == .denied)
                    .accessibilityIdentifier("settings.notifyTest")
                }
            }
            SettingsSection(String(localized: "What to tell you about", bundle: .module)) {
                ForEach(VraiNotification.Category.allCases, id: \.self) { category in
                    let key = Preferences.notifyKey(category)
                    let reason = blocked(category)
                    SettingsRow(Self.title(category), description: reason ?? Self.description(category)) {
                        SettingsSwitch(label: Self.title(category), isOn: preferences[keyPath: key] && reason == nil, id: "settings.notify." + category.rawValue, disabled: !on || reason != nil) { preferences[keyPath: key] = $0 }
                    }
                }
            }
        }
        .task {
            NotificationHub.shared.configure(launch: context.app.launch)
            await permission.refresh()
        }
    }
}
