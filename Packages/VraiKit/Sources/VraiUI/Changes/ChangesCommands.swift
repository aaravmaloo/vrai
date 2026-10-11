import AppKit
import SwiftUI
import VraiCore
import VraiGit

enum UndoRouter {
    @MainActor static func undo(_ window: WindowModel?) {
        if let responder = NSApp.keyWindow?.firstResponder as? NSTextView, let manager = responder.undoManager, manager.canUndo {
            manager.undo()
            return
        }
        window?.undoLast()
    }

    @MainActor static func redo() {
        guard let manager = NSApp.keyWindow?.firstResponder?.undoManager, manager.canRedo else { return }
        manager.redo()
    }
}

struct UndoCommandItems: View {
    let window: WindowModel?

    var body: some View {
        Button(ChangesCopy.undoMenuTitle(window?.changes.latestUndo)) {
            UndoRouter.undo(window)
        }
        .keyboardShortcut("z")
        Button(String(localized: "Redo", bundle: .module)) {
            UndoRouter.redo()
        }
        .keyboardShortcut("z", modifiers: [.command, .shift])
        Button(String(localized: "Undo history\u{2026}", bundle: .module)) {
            window?.showUndoHistory()
        }
        .disabled(window == nil)
    }
}

struct CommitChangesItems: View {
    let window: WindowModel?

    var body: some View {
        let groups = window?.changeGroups
        let working = groups.map { !($0.staged + $0.unstaged + $0.untracked).isEmpty } ?? false
        let staged = groups.map { !$0.staged.isEmpty } ?? false
        Button(String(localized: "Commit", bundle: .module)) {
            window?.commitFromMenu()
        }
        .keyboardShortcut(.return)
        .disabled(!(window?.canCommit ?? false))
        .modifierKeyAlternate(.option) {
            Button(String(localized: "Commit and push", bundle: .module)) {
                window?.commitNow(andPush: true)
            }
            .keyboardShortcut(.return, modifiers: [.command, .option])
            .disabled(!(window?.canCommit ?? false))
        }
        Button(String(localized: "Amend last commit", bundle: .module)) {
            window?.startAmend()
        }
        .disabled(window?.store.snapshot?.headOID == nil)
        Divider()
        Button(String(localized: "Stage all", bundle: .module)) {
            window?.stageEverything(includeUntracked: false)
        }
        .keyboardShortcut("a", modifiers: [.command, .shift])
        .disabled(!working)
        .modifierKeyAlternate(.option) {
            Button(String(localized: "Stage all, including untracked", bundle: .module)) {
                window?.stageEverything(includeUntracked: true)
            }
            .disabled(!working)
        }
        Button(String(localized: "Unstage all", bundle: .module)) {
            window?.unstageEverything()
        }
        .disabled(!staged)
        Button(String(localized: "Discard all changes\u{2026}", bundle: .module)) {
            window?.confirmDiscardAll()
        }
        .disabled(!working)
    }
}
