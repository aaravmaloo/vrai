import SwiftUI
import VraiCore
import VraiGit

@MainActor
enum RewriteToolbar {
    static func merge(_ window: WindowModel) {
        RewriteActions.openMerge(window, mode: window.optionDown || NSEvent.modifierFlags.contains(.option) ? .mergeCommit : .auto)
    }

    static func rebase(_ window: WindowModel) {
        if window.optionDown || NSEvent.modifierFlags.contains(.option) {
            RewriteActions.openInteractive(window)
        } else {
            RewriteActions.openRebase(window)
        }
    }

    static func stash(_ window: WindowModel) {
        guard window.optionDown || NSEvent.modifierFlags.contains(.option) else {
            RewriteActions.openStash(window)
            return
        }
        let count = window.store.snapshot?.working.count ?? 0
        RewriteActions.stash(window, message: nil, includeUntracked: true, keepIndex: false, onlyStaged: false, paths: [], count: count)
    }
}
