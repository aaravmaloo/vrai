import SwiftUI
import VraiCore

struct NotchPane: View {
    let context: SettingsContext
    @Environment(Preferences.self) private var preferences

    var on: Bool { preferences.island != .off }

    static func linger(_ value: Preferences.IslandLinger) -> String {
        switch value {
        case .short: String(localized: "Briefly", bundle: .module)
        case .standard: String(localized: "A few seconds", bundle: .module)
        case .long: String(localized: "Longer", bundle: .module)
        }
    }

    static func screen(_ value: Preferences.IslandScreen) -> String {
        switch value {
        case .window: String(localized: "The display with the Vrai window", bundle: .module)
        case .builtIn: String(localized: "The built-in display", bundle: .module)
        case .pointer: String(localized: "The display with the pointer", bundle: .module)
        }
    }

    var body: some View {
        SettingsForm {
            SettingsSection(String(localized: "Notch", bundle: .module)) {
                SettingsRow(String(localized: "Show activity in the notch", bundle: .module), description: IslandCenter.shared.hasNotch || !on ? String(localized: "Vrai shows what git is doing as icons around the notch, like the Dynamic Island. Hover it to see more.", bundle: .module) : String(localized: "This display has no notch, so a small pill hangs from the top of the screen instead.", bundle: .module)) {
                    SettingsSwitch(label: String(localized: "Show activity in the notch", bundle: .module), isOn: on, id: "settings.island") { preferences.island = $0 ? .activity : .off }
                }
                SettingsRow(String(localized: "Show quick confirmations too", bundle: .module), description: String(localized: "An added remote, a published branch and other quick results go to the notch instead of the window.", bundle: .module)) {
                    SettingsSwitch(label: String(localized: "Show quick confirmations too", bundle: .module), isOn: preferences.island == .everything, id: "settings.islandEverything", disabled: !on) { preferences.island = $0 ? .everything : .activity }
                }
            }
            SettingsSection(String(localized: "What it shows", bundle: .module)) {
                toggle(String(localized: "Fetch, pull, push and clone", bundle: .module), String(localized: "A ring fills while git works, then a check or a cross.", bundle: .module), \.islandSync, "settings.islandSync")
                toggle(String(localized: "Rebase, merge, cherry-pick and bisect", bundle: .module), String(localized: "Stays by the notch while git is paused. Hover for Continue and Abort, or Good and Bad.", bundle: .module), \.islandStates, "settings.islandStates")
                toggle(String(localized: "New commits from background fetch", bundle: .module), String(localized: "When a fetch brings commits to a branch you track.", bundle: .module), \.islandFetch, "settings.islandFetch")
                toggle(String(localized: "CI results", bundle: .module), String(localized: "Follows the checks after you push and shows when they pass or fail.", bundle: .module), \.islandChecks, "settings.islandChecks")
                toggle(String(localized: "Touch ID prompts", bundle: .module), String(localized: "Sensitive actions ask for your fingerprint in the notch. When off, macOS shows its own prompt.", bundle: .module), \.islandAuth, "settings.islandAuth")
            }
            SettingsSection(String(localized: "Behavior", bundle: .module)) {
                toggle(String(localized: "Open when something needs you", bundle: .module), String(localized: "A rejected push, a failed sign-in or failing CI opens with its choices. When off, those decisions appear in the window.", bundle: .module), \.islandAttention, "settings.islandAttention")
                toggle(String(localized: "Open on hover", bundle: .module), String(localized: "When off, click the notch to see more.", bundle: .module), \.islandHover, "settings.islandHover")
                SettingsRow(String(localized: "Keep results for", bundle: .module)) {
                    SettingsSelect(
                        label: String(localized: "Keep results for", bundle: .module),
                        options: Preferences.IslandLinger.allCases.map { SettingsOption(value: $0, label: Self.linger($0)) },
                        selection: preferences.islandLinger,
                        id: "settings.islandLinger",
                        disabled: !on
                    ) { preferences.islandLinger = $0 }
                }
                SettingsRow(String(localized: "Show on", bundle: .module), description: String(localized: "With more than one display, the notch activity appears here.", bundle: .module)) {
                    SettingsSelect(
                        label: String(localized: "Show on", bundle: .module),
                        options: Preferences.IslandScreen.allCases.map { SettingsOption(value: $0, label: Self.screen($0)) },
                        selection: preferences.islandScreen,
                        id: "settings.islandScreen",
                        disabled: !on
                    ) { preferences.islandScreen = $0 }
                }
                SettingsRow(String(localized: "Preview", bundle: .module), description: String(localized: "Plays a sample push in the notch with these settings.", bundle: .module)) {
                    Button(String(localized: "Show a preview", bundle: .module)) { Self.preview(preferences) }
                        .controlSize(.small)
                        .disabled(!on)
                        .accessibilityIdentifier("settings.islandPreview")
                }
            }
        }
    }

    func toggle(_ title: String, _ description: String, _ key: ReferenceWritableKeyPath<Preferences, Bool>, _ id: String) -> some View {
        SettingsRow(title, description: description) {
            SettingsSwitch(label: title, isOn: preferences[keyPath: key], id: id, disabled: !on) { preferences[keyPath: key] = $0 }
        }
    }

    static func preview(_ preferences: Preferences) {
        let island = IslandCenter.shared
        island.preferences = preferences
        island.mode = preferences.island
        guard island.isActive else { return }
        let id = island.show(IslandActivity(phase: .running, title: String(localized: "Pushing main to origin", bundle: .module), icon: "arrow.up.to.line", source: "Vrai", progress: 0))
        Task { @MainActor in
            for step in 1...12 {
                try? await Task.sleep(for: .milliseconds(140))
                island.update(id) { $0.progress = Double(step) / 12 }
            }
            island.finish(id) { activity in
                activity.phase = .success
                activity.title = String(localized: "Pushed 2 commits to origin", bundle: .module)
                activity.progress = nil
            }
        }
    }
}
