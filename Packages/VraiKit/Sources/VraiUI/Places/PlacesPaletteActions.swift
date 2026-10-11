import SwiftUI
import VraiCore
import VraiGit

enum PlacesPaletteActions {
    @MainActor static func actions(_ window: WindowModel) -> [PaletteAction] {
        let snapshot = window.store.snapshot
        let hasRepository = snapshot != nil
        let worktrees = snapshot?.worktrees.count ?? 0
        return [
            PaletteAction(id: "places.addWorktree", title: String(localized: "Add worktree\u{2026}", bundle: .module), icon: "rectangle.on.rectangle", keywords: ["worktree", "add", "checkout", "folder"], enabled: hasRepository && snapshot?.isBare == false) {
                PlacesActions.openAddWorktree(window)
            },
            PaletteAction(id: "places.addSubmodule", title: String(localized: "Add submodule\u{2026}", bundle: .module), icon: "shippingbox", keywords: ["submodule", "add", "vendor"], enabled: hasRepository && snapshot?.isBare == false) {
                PlacesActions.openAddSubmodule(window)
            },
            PaletteAction(id: "places.worktrees", title: String(localized: "Worktrees", bundle: .module), icon: "rectangle.on.rectangle", keywords: ["worktree", "list"], enabled: worktrees > 0) {
                PlacesActions.showWorktree(window)
            },
            PaletteAction(id: "places.submodules", title: String(localized: "Submodules", bundle: .module), icon: "shippingbox", keywords: ["submodule", "list"], enabled: hasRepository) {
                PlacesActions.showSubmodule(window)
            },
            PaletteAction(id: "places.reflog", title: String(localized: "Reflog", bundle: .module), icon: "clock", shortcut: "\u{2318}4", keywords: ["reflog", "head", "restore", "undo"], enabled: hasRepository, expertOnly: true) {
                window.show(.reflog)
            },
            PaletteAction(id: "places.refs", title: String(localized: "Refs", bundle: .module), icon: "point.3.connected.trianglepath.dotted", keywords: ["refs", "for-each-ref", "replace", "notes", "show-ref"], enabled: hasRepository, expertOnly: true) {
                window.show(.refs)
            },
            PaletteAction(id: "places.pruneWorktrees", title: String(localized: "Prune stale worktrees", bundle: .module), icon: "trash", keywords: ["worktree", "prune"], enabled: worktrees > 1, expertOnly: true) {
                PlacesActions.prune(window)
            }
        ]
    }
}
