import SwiftUI
import VraiCore
import VraiGit

enum CoveragePaletteActions {
    @MainActor static func actions(_ window: WindowModel) -> [PaletteAction] {
        let snapshot = window.store.snapshot
        let maintenance = String(localized: "Maintenance", bundle: .module)
        var out: [PaletteAction] = [
            PaletteAction(id: "coverage.pack-objects", title: maintenance + " \u{203A} " + String(localized: "Pack loose objects", bundle: .module), icon: "archivebox", keywords: ["pack-objects", "prune-packed", "loose"], enabled: snapshot != nil, expertOnly: true) {
                CoverageActions.packLooseObjects(window)
            },
            PaletteAction(id: "coverage.pack-redundant", title: maintenance + " \u{203A} " + String(localized: "Find redundant packs", bundle: .module), icon: "archivebox", keywords: ["pack-redundant", "duplicate"], enabled: snapshot != nil, expertOnly: true) {
                CoverageActions.findRedundantPacks(window)
            },
            PaletteAction(id: "coverage.unpack-objects", title: maintenance + " \u{203A} " + String(localized: "Recover objects from a pack file\u{2026}", bundle: .module), icon: "shippingbox", keywords: ["unpack-objects", "recover", "corrupt"], enabled: snapshot != nil, expertOnly: true) {
                CoverageActions.recoverObjects(window)
            }
        ]
        if let branch = snapshot?.currentBranch {
            out.append(PaletteAction(id: "coverage.range-diff", title: String(localized: "Compare with before rebase", bundle: .module), icon: "arrow.left.arrow.right", keywords: ["range-diff", "rebase", branch.name], expertOnly: true) {
                CoverageActions.compareWithBeforeRebase(window, branch: branch.name)
            })
        }
        return out
    }
}
