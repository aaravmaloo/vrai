import SwiftUI
import VraiCore
import VraiGit

@MainActor
enum RewriteBanners {
    static let wired: Set<String> = ["merge", "rebase", "cherry", "revert", "am", "bisect"]

    static func wire(_ model: BannerModel, window: WindowModel) -> BannerModel {
        guard wired.contains(model.id) else { return model }
        var model = model
        let running = RewriteActivity.shared.key(for: window)
        let storeBusy = !window.store.busy.isEmpty
        model.actions = model.actions.map { action in
            var action = action
            guard let (key, perform) = handler(for: action.title, banner: model.id, window: window) else { return action }
            action.perform = perform
            action.busy = running == key
            action.enabled = running == nil && !storeBusy
            return action
        }
        return model
    }

    static func handler(for title: String, banner: String, window: WindowModel) -> (String, @MainActor () -> Void)? {
        func text(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }
        switch title {
        case text("Resolve conflicts"):
            return ("show", { window.showConflicts() })
        case text("Abort merge"), text("Abort"):
            return ("abort", { RewriteActions.abort(window) })
        case text("Commit merge"), text("Continue"):
            return ("continue", { RewriteActions.continueOperation(window) })
        case text("Amend\u{2026}"):
            return ("show", { window.show(.changes) })
        case text("Skip"):
            if banner == "bisect" { return ("bisect-skip", { RewriteActions.markBisect(window, .skip) }) }
            return ("skip", { RewriteActions.continueOperation(window, skip: true) })
        case text("Good"):
            return ("bisect-good", { RewriteActions.markBisect(window, .good) })
        case text("Bad"):
            return ("bisect-bad", { RewriteActions.markBisect(window, .bad) })
        case text("End"), text("End bisect"):
            return ("end", { RewriteActions.endBisect(window) })
        default:
            return nil
        }
    }
}
