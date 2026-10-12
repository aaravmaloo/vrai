import AppKit
import SwiftUI
import VraiCore
import VraiGit

struct PaletteContext {
    let window: WindowModel
    let app: AppModel
    let openWindowID: @MainActor (String) -> Void
    let openRepository: @MainActor (RepositoryReference) -> Void
}

enum CorePaletteActions {
    static let gitReference = ["rebase", "reset", "reflog", "bisect", "worktree", "cherry-pick"]

    @MainActor static func actions(_ context: PaletteContext) -> [PaletteAction] {
        let window = context.window
        let app = context.app
        let store = window.store
        let snapshot = store.snapshot
        let preferences = window.preferences
        let branch = snapshot?.currentBranch
        let head = window.headName
        let selected = store.selection?.commitID
        let groups = window.changeGroups
        let working = !(groups.staged + groups.unstaged + groups.untracked).isEmpty
        let staged = !groups.staged.isEmpty
        let vrai = String(localized: "Vrai", bundle: .module)
        let file = String(localized: "File", bundle: .module)
        let edit = String(localized: "Edit", bundle: .module)
        let view = String(localized: "View", bundle: .module)
        let repository = String(localized: "Repository", bundle: .module)
        let branchMenu = String(localized: "Branch", bundle: .module)
        let commit = String(localized: "Commit", bundle: .module)
        let help = String(localized: "Help", bundle: .module)
        var out: [PaletteAction] = []

        out.append(PaletteAction(id: "a:app:about", title: String(localized: "About Vrai", bundle: .module), icon: "info.circle", detail: vrai) { context.openWindowID("about") })

        out.append(PaletteAction(id: "a:file:open", title: String(localized: "Open\u{2026}", bundle: .module), icon: "folder", shortcut: "\u{2318}O", detail: file) {
            OpenPanel.choose(app: app) { context.openRepository($0) }
        })
        out.append(PaletteAction(id: "a:file:switch", title: String(localized: "Switch repository\u{2026}", bundle: .module), icon: "arrow.left.arrow.right", shortcut: "\u{2318}T", detail: file) { window.toggleSwitcher() })
        for (index, recent) in app.recents.enumerated() {
            out.append(PaletteAction(id: "a:file:recent:\(index)", title: String(localized: "Open recent", bundle: .module) + " \u{203A} " + recent.name, icon: "clock", keywords: [recent.path], detail: PathText.abbreviated(recent.path)) {
                context.openRepository(app.request(RepositoryReference(path: recent.path)))
            })
        }
        out.append(PaletteAction(id: "a:file:welcome", title: String(localized: "Welcome window", bundle: .module), icon: "macwindow", shortcut: "\u{21E7}\u{2318}1", detail: file) { context.openWindowID("welcome") })

        if let undo = window.changes.latestUndo {
            out.append(PaletteAction(id: "a:edit:undo", title: ChangesCopy.undoMenuTitle(undo), icon: "arrow.uturn.backward", shortcut: "\u{2318}Z", detail: edit) { window.undoLast() })
        }
        out.append(PaletteAction(id: "a:edit:history", title: String(localized: "Undo history\u{2026}", bundle: .module), icon: "clock.arrow.circlepath", detail: edit) { window.showUndoHistory() })
        if let selected {
            out.append(PaletteAction(id: "a:edit:hash", title: String(localized: "Copy hash", bundle: .module), icon: "doc.on.doc", shortcut: "\u{2318}C", detail: edit) {
                window.copy(selected.short(expert: preferences.expert))
            })
            out.append(PaletteAction(id: "a:edit:hash:alt", title: String(localized: "Copy full hash", bundle: .module), icon: "doc.on.doc", shortcut: "\u{2325}\u{2318}C", detail: edit) {
                window.copy(selected.rawValue, label: String(localized: "full hash", bundle: .module))
            })
        }
        out.append(PaletteAction(id: "a:edit:find", title: String(localized: "Find in history", bundle: .module), icon: "magnifyingglass", shortcut: "\u{2318}F", detail: edit) {
            window.show(.history)
            window.focusFilter = true
        })

        out.append(PaletteAction(id: "a:view:history", title: String(localized: "History", bundle: .module), icon: "clock.arrow.circlepath", shortcut: "\u{2318}1", detail: view) { window.show(.history) })
        out.append(PaletteAction(id: "a:view:changes", title: String(localized: "Changes", bundle: .module), icon: "square.and.pencil", shortcut: "\u{2318}2", detail: view) { window.show(.changes) })
        out.append(PaletteAction(id: "a:view:stashes", title: String(localized: "Stashes", bundle: .module), icon: "tray.full", shortcut: "\u{2318}3", detail: view) { window.show(.stashes) })
        out.append(PaletteAction(id: "a:view:reflog", title: String(localized: "Reflog", bundle: .module), icon: "clock", shortcut: "\u{2318}4", expertOnly: true, detail: view) { window.show(.reflog) })
        out.append(PaletteAction(id: "a:view:sidebar", title: window.sidebarShown ? String(localized: "Hide sidebar", bundle: .module) : String(localized: "Show sidebar", bundle: .module), icon: "sidebar.left", shortcut: "\u{2303}\u{2318}S", detail: view) { window.toggleSidebar() })
        out.append(PaletteAction(id: "a:view:inspector", title: preferences.inspector ? String(localized: "Hide inspector", bundle: .module) : String(localized: "Show inspector", bundle: .module), icon: "sidebar.right", shortcut: "\u{2325}\u{2318}0", detail: view) { preferences.inspector.toggle() })
        out.append(PaletteAction(id: "a:view:console", title: window.console.open ? String(localized: "Hide console", bundle: .module) : String(localized: "Show console", bundle: .module), icon: "terminal", shortcut: "\u{2318}J", detail: view) { window.console.toggle() })
        out.append(PaletteAction(id: "a:view:unified", title: String(localized: "Unified diff", bundle: .module), icon: "doc.text", detail: view) { preferences.diffMode = .unified })
        out.append(PaletteAction(id: "a:view:split", title: String(localized: "Split diff", bundle: .module), icon: "rectangle.split.2x1", detail: view) { preferences.diffMode = .split })
        out.append(PaletteAction(id: "a:view:whitespace", title: String(localized: "Show whitespace", bundle: .module), icon: "eye", detail: view) { preferences.whitespace.toggle() })
        for (density, label) in [(Preferences.Density.compact, String(localized: "Compact", bundle: .module)), (.regular, String(localized: "Regular", bundle: .module)), (.comfortable, String(localized: "Comfortable", bundle: .module))] {
            out.append(PaletteAction(id: "a:view:density:\(density.rawValue)", title: String(localized: "Density", bundle: .module) + " \u{203A} " + label, icon: "textformat.size", detail: view) { preferences.density = density })
        }
        for (theme, label) in [(Preferences.Theme.system, String(localized: "Match the system", bundle: .module)), (.light, String(localized: "Light", bundle: .module)), (.dark, String(localized: "Dark", bundle: .module))] {
            out.append(PaletteAction(id: "a:view:theme:\(theme.rawValue)", title: String(localized: "Appearance", bundle: .module) + " \u{203A} " + label, icon: "circle.lefthalf.filled", detail: view) { preferences.theme = theme })
        }
        out.append(PaletteAction(id: "a:view:expert", title: String(localized: "Expert mode", bundle: .module), icon: "terminal", shortcut: "\u{2325}\u{2318}E", detail: view) { window.toggleExpert() })

        let behind = branch?.behind ?? 0
        let ahead = branch?.ahead ?? 0
        out.append(PaletteAction(id: "a:repo:fetch", title: String(localized: "Fetch", bundle: .module), icon: "arrow.triangle.2.circlepath", shortcut: "\u{21E7}\u{2318}F", detail: repository, alternate: { window.sync.openSync(.fetch) }) { window.sync.fetch() })
        out.append(PaletteAction(id: "a:repo:fetch:alt", title: String(localized: "Fetch all remotes and prune", bundle: .module), icon: "arrow.triangle.2.circlepath", shortcut: "\u{2325}\u{21E7}\u{2318}F", detail: repository) { window.sync.fetch(all: true) })
        out.append(PaletteAction(id: "a:repo:pull", title: behind > 0 ? String(localized: "Pull \(n(behind, "commit"))", bundle: .module) : String(localized: "Pull", bundle: .module), icon: "arrow.down.to.line", shortcut: "\u{21E7}\u{2318}L", enabled: branch != nil, detail: repository, alternate: { window.sync.openSync(.pull) }) { window.sync.pull() })
        out.append(PaletteAction(id: "a:repo:pull:alt", title: String(localized: "Pull with rebase", bundle: .module), icon: "arrow.down.to.line", shortcut: "\u{2325}\u{21E7}\u{2318}L", enabled: branch != nil, detail: repository) { window.sync.pull(mode: .rebase) })
        out.append(PaletteAction(id: "a:repo:push", title: ahead > 0 ? String(localized: "Push \(n(ahead, "commit"))", bundle: .module) : String(localized: "Push", bundle: .module), icon: "arrow.up.to.line", shortcut: "\u{21E7}\u{2318}P", enabled: branch != nil, detail: repository, alternate: { window.sync.openSync(.push) }) { window.sync.push() })
        out.append(PaletteAction(id: "a:repo:push:alt", title: String(localized: "Force push with lease", bundle: .module), icon: "arrow.up.to.line", shortcut: "\u{2325}\u{21E7}\u{2318}P", enabled: branch != nil, detail: repository, danger: true) { window.sync.push(force: .withLease) })
        out.append(PaletteAction(id: "a:repo:options", title: String(localized: "Fetch, pull and push with options\u{2026}", bundle: .module), icon: "slider.horizontal.3", detail: repository) { window.sync.openSync(.push) })
        out.append(PaletteAction(id: "a:repo:stash", title: String(localized: "Stash changes\u{2026}", bundle: .module), icon: "tray.and.arrow.down", shortcut: "\u{21E7}\u{2318}S", enabled: !(snapshot?.working.isEmpty ?? true), detail: repository) { RewriteActions.openStash(window) })
        let hasStash = !(snapshot?.stashes.isEmpty ?? true)
        out.append(PaletteAction(id: "a:repo:apply", title: String(localized: "Apply latest stash", bundle: .module), icon: "tray.and.arrow.up", enabled: hasStash, detail: repository) { RewriteActions.applyStash(window, index: 0, pop: false) })
        out.append(PaletteAction(id: "a:repo:pop", title: String(localized: "Pop latest stash", bundle: .module), icon: "tray.and.arrow.up", enabled: hasStash, detail: repository) { RewriteActions.applyStash(window, index: 0, pop: true) })
        let remotes = String(localized: "Remotes", bundle: .module)
        out.append(PaletteAction(id: "a:repo:remote:add", title: remotes + " \u{203A} " + String(localized: "Add remote\u{2026}", bundle: .module), icon: "plus", detail: repository) { window.sync.addRemote() })
        for remote in snapshot?.remotes ?? [] {
            out.append(PaletteAction(id: "a:repo:remote:" + remote.name, title: remotes + " \u{203A} " + String(localized: "Edit \(remote.name)\u{2026}", bundle: .module), icon: "pencil", detail: repository) { window.sync.editRemote(remote.name) })
        }
        out.append(PaletteAction(id: "a:repo:reveal", title: String(localized: "Reveal in Finder", bundle: .module), icon: "folder", enabled: snapshot?.root != nil, detail: repository) {
            if let root = store.snapshot?.root { NSWorkspace.shared.activateFileViewerSelecting([root]) }
        })

        out.append(PaletteAction(id: "a:branch:new", title: String(localized: "New branch\u{2026}", bundle: .module), icon: "arrow.triangle.branch", shortcut: "\u{21E7}\u{2318}B", enabled: snapshot != nil, detail: branchMenu) { window.sync.newBranch() })
        out.append(PaletteAction(id: "a:branch:switch", title: String(localized: "Switch to\u{2026}", bundle: .module), icon: "arrow.left.arrow.right", shortcut: "\u{2318}B", detail: branchMenu) { window.openPalette(.branches) })
        if let branch {
            out.append(PaletteAction(id: "a:branch:rename", title: String(localized: "Rename \(head)\u{2026}", bundle: .module), icon: "pencil", detail: branchMenu) { window.sync.rename(branch.name) })
            out.append(PaletteAction(id: "a:branch:upstream", title: branch.upstream == nil ? String(localized: "Set upstream\u{2026}", bundle: .module) : String(localized: "Change upstream\u{2026}", bundle: .module), icon: "link", detail: branchMenu) { window.sync.editUpstream(branch.name) })
        }
        out.append(PaletteAction(id: "a:branch:merge", title: String(localized: "Merge into \(head)\u{2026}", bundle: .module), icon: "arrow.triangle.merge", shortcut: "\u{21E7}\u{2318}M", enabled: snapshot != nil, detail: branchMenu) { RewriteActions.openMerge(window) })
        out.append(PaletteAction(id: "a:branch:rebase", title: String(localized: "Rebase \(head)\u{2026}", bundle: .module), icon: "arrow.triangle.swap", shortcut: "\u{21E7}\u{2318}R", enabled: branch != nil, detail: branchMenu) { RewriteActions.openRebase(window) })
        out.append(PaletteAction(id: "a:branch:interactive", title: String(localized: "Interactive rebase\u{2026}", bundle: .module), icon: "list.number", shortcut: "\u{2325}\u{21E7}\u{2318}R", enabled: branch != nil, detail: branchMenu) { RewriteActions.openInteractive(window) })
        out.append(PaletteAction(id: "a:branch:bisect", title: String(localized: "Start bisect\u{2026}", bundle: .module), icon: "scope", enabled: !(snapshot?.state.isOperationInProgress ?? true), detail: branchMenu) { RewriteActions.openBisect(window) })

        out.append(PaletteAction(id: "a:commit:commit", title: String(localized: "Commit", bundle: .module), icon: "checkmark.circle", shortcut: "\u{2318}\u{21A9}", enabled: window.canCommit, detail: commit) { window.commitFromMenu() })
        out.append(PaletteAction(id: "a:commit:push", title: String(localized: "Commit and push", bundle: .module), icon: "arrow.up.to.line", shortcut: "\u{2325}\u{2318}\u{21A9}", enabled: window.canCommit, detail: commit) { window.commitNow(andPush: true) })
        out.append(PaletteAction(id: "a:commit:amend", title: String(localized: "Amend last commit", bundle: .module), icon: "pencil", enabled: snapshot?.headOID != nil, detail: commit) {
            window.show(.changes)
            window.startAmend()
        })
        out.append(PaletteAction(id: "a:commit:stage", title: String(localized: "Stage all", bundle: .module), icon: "plus", shortcut: "\u{21E7}\u{2318}A", enabled: working, detail: commit) { window.stageEverything(includeUntracked: false) })
        out.append(PaletteAction(id: "a:commit:stage:alt", title: String(localized: "Stage all, including untracked", bundle: .module), icon: "plus", enabled: working, detail: commit) { window.stageEverything(includeUntracked: true) })
        out.append(PaletteAction(id: "a:commit:unstage", title: String(localized: "Unstage all", bundle: .module), icon: "minus", enabled: staged, detail: commit) { window.unstageEverything() })
        out.append(PaletteAction(id: "a:commit:discard", title: String(localized: "Discard all changes\u{2026}", bundle: .module), icon: "arrow.uturn.backward", enabled: working, detail: commit, danger: true) { window.confirmDiscardAll() })
        if let selected {
            out.append(PaletteAction(id: "a:commit:cherry", title: String(localized: "Cherry-pick selected", bundle: .module), icon: "arrow.turn.down.right", detail: commit) { RewriteActions.openCherryPick(window, ids: [selected]) })
            out.append(PaletteAction(id: "a:commit:revert", title: String(localized: "Revert selected", bundle: .module), icon: "arrow.uturn.backward", detail: commit) { RewriteActions.revert(window, id: selected) })
            out.append(PaletteAction(id: "a:commit:reset", title: String(localized: "Reset \(head) to selected\u{2026}", bundle: .module), icon: "arrow.counterclockwise", detail: commit) { RewriteActions.openReset(window, target: selected) })
            out.append(PaletteAction(id: "a:commit:tag", title: String(localized: "Tag selected\u{2026}", bundle: .module), icon: "tag", detail: commit) { window.sync.newTag(target: selected.rawValue) })
            out.append(PaletteAction(id: "a:commit:object", title: String(localized: "Show object", bundle: .module), icon: "cube", expertOnly: true, detail: commit) { window.showObject(selected) })
        }

        let reference = String(localized: "Git reference", bundle: .module)
        for command in gitReference {
            out.append(PaletteAction(id: "a:help:ref:" + command, title: reference + " \u{203A} git " + command, icon: "doc.text", detail: help) { AppSheets.present(.reference(command), window: window) })
        }
        return out
    }
}

