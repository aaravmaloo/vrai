import SwiftUI
import VraiCore
import VraiGit

struct GeneralPane: View {
    let context: SettingsContext
    @Environment(Preferences.self) private var preferences

    static let intervals = [5, 15, 30, 60]
    static let terminals = ["Terminal", "iTerm", "Ghostty", "Warp"]

    var remotes: [String] {
        SettingsHub.shared.activeWindow?.store.snapshot?.remotes.map(\.name) ?? []
    }

    var fetchDescription: String {
        guard SettingsHub.shared.activeWindow != nil else {
            return String(localized: "Runs git fetch --prune for the remotes of each open repository.", bundle: .module)
        }
        guard !remotes.isEmpty else { return String(localized: "This repository has no remotes yet.", bundle: .module) }
        return String(localized: "Runs git fetch --prune for \(SettingsCopy.list(remotes)).", bundle: .module)
    }

    static func interval(_ minutes: Int) -> String {
        minutes == 60 ? String(localized: "Every hour", bundle: .module) : String(localized: "Every \(n(minutes, "minute"))", bundle: .module)
    }

    var body: some View {
        SettingsForm {
            SettingsSection(String(localized: "Opening", bundle: .module)) {
                SettingsRow(String(localized: "When Vrai opens", bundle: .module)) {
                    SettingsSelect(
                        label: String(localized: "When Vrai opens", bundle: .module),
                        options: [
                            SettingsOption(value: Preferences.OpenAt.reopen, label: String(localized: "Reopen the last repository", bundle: .module)),
                            SettingsOption(value: Preferences.OpenAt.welcome, label: String(localized: "Show the Welcome window", bundle: .module))
                        ],
                        selection: preferences.openAt,
                        id: "settings.openAt"
                    ) { preferences.openAt = $0 }
                }
                SettingsRow(String(localized: "Show the Welcome window when no repository is open", bundle: .module), description: String(localized: "After you close the last repository window, for example.", bundle: .module)) {
                    SettingsSwitch(label: String(localized: "Show the Welcome window when no repository is open", bundle: .module), isOn: preferences.welcomeOnLaunch, id: "settings.welcomeOnLaunch") { preferences.welcomeOnLaunch = $0 }
                }
            }
            SettingsSection(String(localized: "Background fetch", bundle: .module)) {
                SettingsRow(String(localized: "Fetch in the background", bundle: .module), description: fetchDescription) {
                    SettingsSwitch(label: String(localized: "Fetch in the background", bundle: .module), isOn: preferences.backgroundFetch, id: "settings.backgroundFetch") { preferences.backgroundFetch = $0 }
                }
                SettingsRow(String(localized: "How often", bundle: .module)) {
                    SettingsSelect(
                        label: String(localized: "How often to fetch", bundle: .module),
                        options: Self.intervals.map { SettingsOption(value: $0, label: Self.interval($0)) },
                        selection: Self.intervals.contains(preferences.fetchInterval) ? preferences.fetchInterval : 15,
                        id: "settings.fetchInterval",
                        disabled: !preferences.backgroundFetch
                    ) { preferences.fetchInterval = $0 }
                }
                SettingsRow(String(localized: "Notify me about new commits", bundle: .module), description: String(localized: "When a fetch brings new commits to a branch you track.", bundle: .module)) {
                    SettingsSwitch(label: String(localized: "Notify me about new commits", bundle: .module), isOn: preferences.notifications, id: "settings.notifications", disabled: !preferences.backgroundFetch) { preferences.notifications = $0 }
                }
            }
            SettingsSection(String(localized: "Console and tools", bundle: .module)) {
                SettingsRow(String(localized: "Open the console when a command fails", bundle: .module), description: String(localized: "Shows git's own output and exit code, so you see exactly what went wrong.", bundle: .module)) {
                    SettingsSwitch(label: String(localized: "Open the console when a command fails", bundle: .module), isOn: preferences.consoleOnFailure, id: "settings.consoleOnFailure") { preferences.consoleOnFailure = $0 }
                }
                SettingsRow(String(localized: "Terminal app", bundle: .module), description: String(localized: "Repository, Open in Terminal uses it.", bundle: .module)) {
                    SettingsSelect(
                        label: String(localized: "Terminal app", bundle: .module),
                        options: (Self.terminals.contains(preferences.terminal) ? Self.terminals : Self.terminals + [preferences.terminal]).map { SettingsOption(value: $0, label: $0) },
                        selection: preferences.terminal,
                        id: "settings.terminal"
                    ) { preferences.terminal = $0 }
                }
            }
        }
    }
}
