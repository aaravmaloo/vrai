import SwiftUI
import VraiCore
import VraiGit

struct SettingsWiring: ViewModifier {
    let window: WindowModel
    @Environment(AppModel.self) private var app
    @Environment(\.appearsActive) private var active
    @Environment(\.openSettings) private var openSettings
    @State private var pendingRefresh: Task<Void, Never>?

    func body(content: Content) -> some View {
        let hub = SettingsHub.shared
        content
            .onAppear {
                hub.openSettingsAction = openSettings
                hub.register(window)
                window.store.renameThreshold = window.preferences.renameThreshold
                openForLaunch()
            }
            .onDisappear { hub.remove(window) }
            .onChange(of: active, initial: true) { _, value in
                hub.openSettingsAction = openSettings
                if value { hub.activate(window) }
            }
            .onChange(of: window.preferences.renameThreshold) { _, value in
                guard window.store.renameThreshold != value else { return }
                window.store.renameThreshold = value
                pendingRefresh?.cancel()
                let store = window.store
                pendingRefresh = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    guard !Task.isCancelled else { return }
                    try? await store.refresh()
                }
            }
    }

    func openForLaunch() {
        let hub = SettingsHub.shared
        guard !hub.openedForLaunch, let raw = app.launch.settings, let pane = SettingsPane(rawValue: raw) else { return }
        hub.openedForLaunch = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            hub.open(pane)
        }
    }
}

enum SettingsAccounts {
    @MainActor static func record(_ target: SignInTarget, username: String, preferences: Preferences) {
        let url = target.url ?? (target.host.isEmpty ? nil : "https://" + target.host)
        guard let url else { return }
        preferences.noteSignedIn(url: url, username: username)
    }
}

struct KeyboardShortcutsMenuItem: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(String(localized: "Keyboard shortcuts", bundle: .module)) {
            SettingsHub.shared.pane = .shortcuts
            SettingsHub.shared.openSettingsAction = openSettings
            openSettings()
        }
    }
}

extension View {
    func settingsWiring(_ window: WindowModel) -> some View {
        modifier(SettingsWiring(window: window))
    }
}
