import SwiftUI
import VraiCore
import VraiGit

enum SettingsPaletteActions {
    @MainActor static func actions(_ window: WindowModel) -> [PaletteAction] {
        let hub = SettingsHub.shared
        let store = window.store
        return [
            PaletteAction(id: "settings.open", title: String(localized: "Settings\u{2026}", bundle: .module), icon: "gearshape", shortcut: "\u{2318},", keywords: ["preferences", "identity", "signing", "accounts", "appearance", "git config"]) {
                hub.activate(window)
                hub.open()
            },
            PaletteAction(id: "settings.shortcuts", title: String(localized: "Keyboard shortcuts", bundle: .module), icon: "keyboard", keywords: ["keys", "help"]) {
                hub.activate(window)
                hub.open(.shortcuts)
            },
            PaletteAction(id: "settings.maintenance.run", title: String(localized: "Maintenance \u{203A} Run background maintenance now", bundle: .module), icon: "wrench.and.screwdriver", keywords: ["git maintenance run", "commit graph", "prefetch"], enabled: store.snapshot != nil && !store.busy.contains("maintenance")) {
                MaintenanceFlow.run(window, auto: true)
            }
        ]
    }
}

enum MaintenanceFlow {
    @MainActor static func run(_ window: WindowModel, auto: Bool = false) {
        let store = window.store
        Task { @MainActor in
            do {
                let summary = try await store.runMaintenance(auto: auto)
                window.toasts.show(Toast(message: summary.message, detail: summary.detail, icon: "wrench.and.screwdriver"))
            } catch let error as GitError {
                window.alerts.present(error)
            } catch {
                window.alerts.present(GitError(.unknown(exit: -1, stderr: String(describing: error))))
            }
        }
    }
}
