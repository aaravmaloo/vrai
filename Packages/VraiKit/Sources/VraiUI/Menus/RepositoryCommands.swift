import AppKit
import SwiftUI
import VraiCore
import VraiGit

public struct RepositoryCommands: Commands {
    let app: AppModel
    let updates: UpdateCheck
    @FocusedValue(\.windowModel) private var window
    @Environment(\.openWindow) private var openWindow

    public init(app: AppModel, updates: UpdateCheck) {
        self.app = app
        self.updates = updates
    }

    public var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(String(localized: "About Vrai", bundle: .module)) { openWindow(id: "about") }
        }
        CommandGroup(after: .appSettings) {
            Button(String(localized: "Check for updates\u{2026}", bundle: .module)) { updates.check() }
                .disabled(!updates.canCheck)
        }
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "New repository\u{2026}", bundle: .module)) { AppSheets.present(.newRepository(folder: nil), window: window, app: app, openWindow: openWindow) }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button(String(localized: "Open\u{2026}", bundle: .module)) {
                AppSheets.present(.open, window: window, app: app, openWindow: openWindow)
            }
            .keyboardShortcut("o")
            Button(String(localized: "Clone\u{2026}", bundle: .module)) { AppSheets.present(.clone(url: nil), window: window, app: app, openWindow: openWindow) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button(String(localized: "Switch repository\u{2026}", bundle: .module)) { window?.toggleSwitcher() }
                .keyboardShortcut("t")
                .disabled(window == nil)
            Menu(String(localized: "Open recent", bundle: .module)) {
                ForEach(app.recents.prefix(AppModel.shownRecents)) { recent in
                    Button(recent.name) { openWindow(value: app.request(RepositoryReference(path: recent.path))) }
                }
            }
            Divider()
            Button(String(localized: "Welcome window", bundle: .module)) { openWindow(id: "welcome") }
                .keyboardShortcut("1", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .undoRedo) {
            UndoCommandItems(window: window)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button(String(localized: "Copy hash", bundle: .module)) {
                guard let window, let id = window.store.selection?.commitID else { return }
                window.copy(id.short(expert: window.preferences.expert))
            }
            .disabled(window?.store.selection?.commitID == nil)
            .modifierKeyAlternate(.option) {
                Button(String(localized: "Copy full hash", bundle: .module)) {
                    guard let window, let id = window.store.selection?.commitID else { return }
                    window.copy(id.rawValue, label: String(localized: "full hash", bundle: .module))
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(window?.store.selection?.commitID == nil)
            }
            Button(String(localized: "Find in history", bundle: .module)) {
                window?.show(.history)
                window?.focusFilter = true
            }
            .keyboardShortcut("f")
            .disabled(window == nil)
            Button(String(localized: "Command palette", bundle: .module)) { window?.openPalette() }
                .keyboardShortcut("k")
                .disabled(window == nil)
        }
        CommandGroup(replacing: .sidebar) {
            viewItems
        }
        CommandMenu(String(localized: "Repository", bundle: .module)) {
            repositoryItems
        }
        CommandMenu(String(localized: "Branch", bundle: .module)) {
            branchItems
        }
        CommandMenu(String(localized: "Commit", bundle: .module)) {
            commitItems
        }
        CommandGroup(before: .windowList) {
            Toggle(String(localized: "Console", bundle: .module), isOn: Binding(get: { window?.console.open == true }, set: { _ in window?.console.toggle() }))
                .disabled(window == nil)
            SettingsLink { Text("Settings", bundle: .module) }
            Button(String(localized: "Welcome to Vrai", bundle: .module)) { openWindow(id: "welcome") }
            Divider()
        }
        CommandGroup(replacing: .help) {
            KeyboardShortcutsMenuItem()
            Menu(String(localized: "Git reference", bundle: .module)) {
                ForEach(AppModel.referenceCommands, id: \.self) { command in
                    Button("git " + command) { AppSheets.present(.reference(command), window: window, app: app, openWindow: openWindow) }
                }
            }
            Button(String(localized: "Report a git problem\u{2026}", bundle: .module)) { AppSheets.present(.bugReport, window: window, app: app, openWindow: openWindow) }
        }
    }

    @ViewBuilder var viewItems: some View {
        let store = window?.store
        let preferences = window?.preferences
        Toggle(String(localized: "History", bundle: .module), isOn: Binding(get: { store?.view == .history }, set: { _ in window?.show(.history) }))
            .keyboardShortcut("1")
            .disabled(window == nil)
        Toggle(String(localized: "Changes", bundle: .module), isOn: Binding(get: { store?.view == .changes }, set: { _ in window?.show(.changes) }))
            .keyboardShortcut("2")
            .disabled(window == nil)
        Toggle(String(localized: "Stashes", bundle: .module), isOn: Binding(get: { store?.view == .stashes }, set: { _ in window?.show(.stashes) }))
            .keyboardShortcut("3")
            .disabled(window == nil)
        if app.preferences.expert {
            Toggle(String(localized: "Reflog", bundle: .module), isOn: Binding(get: { store?.view == .reflog }, set: { _ in window?.show(.reflog) }))
                .keyboardShortcut("4")
                .disabled(window == nil)
        }
        Divider()
        Button(window?.sidebarShown == false ? String(localized: "Show sidebar", bundle: .module) : String(localized: "Hide sidebar", bundle: .module)) {
            window?.toggleSidebar()
        }
        .keyboardShortcut("s", modifiers: [.command, .control])
        .disabled(window == nil)
        Button(preferences?.inspector == true ? String(localized: "Hide inspector", bundle: .module) : String(localized: "Show inspector", bundle: .module)) {
            preferences?.inspector.toggle()
        }
        .keyboardShortcut("0", modifiers: [.command, .option])
        .disabled(window == nil)
        Button(window?.console.open == true ? String(localized: "Hide console", bundle: .module) : String(localized: "Show console", bundle: .module)) { window?.console.toggle() }
            .keyboardShortcut("j")
            .disabled(window == nil)
        Divider()
        Toggle(String(localized: "Unified diff", bundle: .module), isOn: Binding(get: { preferences?.diffMode == .unified }, set: { _ in preferences?.diffMode = .unified }))
            .disabled(window == nil)
        Toggle(String(localized: "Split diff", bundle: .module), isOn: Binding(get: { preferences?.diffMode == .split }, set: { _ in preferences?.diffMode = .split }))
            .disabled(window == nil)
        Toggle(String(localized: "Show whitespace", bundle: .module), isOn: Binding(get: { preferences?.whitespace == true }, set: { preferences?.whitespace = $0 }))
            .disabled(window == nil)
        Divider()
        Picker(String(localized: "Density", bundle: .module), selection: Binding(get: { app.preferences.density }, set: { app.preferences.density = $0 })) {
            Text("Compact", bundle: .module).tag(Preferences.Density.compact)
            Text("Regular", bundle: .module).tag(Preferences.Density.regular)
            Text("Comfortable", bundle: .module).tag(Preferences.Density.comfortable)
        }
        Picker(String(localized: "Appearance", bundle: .module), selection: Binding(get: { app.preferences.theme }, set: { app.preferences.theme = $0 })) {
            Text("Match the system", bundle: .module).tag(Preferences.Theme.system)
            Text("Light", bundle: .module).tag(Preferences.Theme.light)
            Text("Dark", bundle: .module).tag(Preferences.Theme.dark)
        }
        Divider()
        Toggle(String(localized: "Expert mode", bundle: .module), isOn: Binding(get: { app.preferences.expert }, set: { _ in
            if let window { window.toggleExpert() } else { app.preferences.expert.toggle() }
        }))
        .keyboardShortcut("e", modifiers: [.command, .option])
    }

    @ViewBuilder var repositoryItems: some View {
        let branch = window?.store.snapshot?.currentBranch
        let behind = branch?.behind ?? 0
        let ahead = branch?.ahead ?? 0
        let expert = app.preferences.expert
        Button(String(localized: "Fetch", bundle: .module)) { window?.sync.fetch() }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(window == nil)
            .modifierKeyAlternate(.option) {
                Button(String(localized: "Fetch all remotes and prune", bundle: .module)) { window?.sync.fetch(all: true) }
                    .keyboardShortcut("f", modifiers: [.command, .shift, .option])
                    .disabled(window == nil)
            }
        Button(behind > 0 ? String(localized: "Pull \(n(behind, "commit"))", bundle: .module) : String(localized: "Pull", bundle: .module)) { window?.sync.pull() }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(branch == nil)
            .modifierKeyAlternate(.option) {
                Button(String(localized: "Pull with rebase", bundle: .module)) { window?.sync.pull(mode: .rebase) }
                    .keyboardShortcut("l", modifiers: [.command, .shift, .option])
                    .disabled(branch == nil)
            }
        Button(ahead > 0 ? String(localized: "Push \(n(ahead, "commit"))", bundle: .module) : String(localized: "Push", bundle: .module)) { window?.sync.push() }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(branch == nil)
            .modifierKeyAlternate(.option) {
                Button(String(localized: "Force push with lease", bundle: .module)) { window?.sync.push(force: .withLease) }
                    .keyboardShortcut("p", modifiers: [.command, .shift, .option])
                    .disabled(branch == nil)
            }
        Button(String(localized: "Fetch, pull and push with options\u{2026}", bundle: .module)) { window?.sync.openSync(.push) }.disabled(window == nil)
        Divider()
        Button(String(localized: "Stash changes\u{2026}", bundle: .module)) { if let window { RewriteActions.openStash(window) } }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(window?.store.snapshot?.working.isEmpty ?? true)
        Button(String(localized: "Apply latest stash", bundle: .module)) { if let window { RewriteActions.applyStash(window, index: 0, pop: false) } }
            .disabled(window?.store.snapshot?.stashes.isEmpty ?? true)
            .modifierKeyAlternate(.option) {
                Button(String(localized: "Pop latest stash", bundle: .module)) { if let window { RewriteActions.applyStash(window, index: 0, pop: true) } }
                    .disabled(window?.store.snapshot?.stashes.isEmpty ?? true)
            }
        Divider()
        Menu(String(localized: "Remotes", bundle: .module)) {
            Button(String(localized: "Add remote\u{2026}", bundle: .module)) { window?.sync.addRemote() }.disabled(window == nil)
            ForEach(window?.store.snapshot?.remotes ?? []) { remote in
                Button(String(localized: "Edit \(remote.name)\u{2026}", bundle: .module)) { window?.sync.editRemote(remote.name) }
            }
        }
        Button(String(localized: "Add worktree\u{2026}", bundle: .module)) { if let window { PlacesActions.openAddWorktree(window) } }.disabled(window?.store.snapshot == nil)
        Button(String(localized: "Add submodule\u{2026}", bundle: .module)) { if let window { PlacesActions.openAddSubmodule(window) } }.disabled(window?.store.snapshot == nil)
        Button(String(localized: "Apply patches\u{2026}", bundle: .module)) { if let window { LongTailActions.openApplyPatches(window) } }.disabled(window?.store.snapshot == nil)
        Button(String(localized: "Create bundle\u{2026}", bundle: .module)) { if let window { LongTailActions.openBundle(window) } }.disabled(window?.store.snapshot?.headOID == nil)
        if expert {
            Button(String(localized: "Sparse checkout\u{2026}", bundle: .module)) { if let window { LongTailActions.openSparse(window) } }.disabled(window?.store.snapshot?.headOID == nil)
        }
        Divider()
        Menu(String(localized: "Maintenance", bundle: .module)) {
            Button(String(localized: "Clean up", bundle: .module)) { if let window { LongTailActions.maintenance(window, .gc) } }.disabled(window == nil)
            Button(String(localized: "Verify integrity", bundle: .module)) { if let window { LongTailActions.verifyIntegrity(window) } }.disabled(window == nil)
            Button(String(localized: "Run background maintenance now", bundle: .module)) { if let window { MaintenanceFlow.run(window, auto: true) } }.disabled(window?.store.snapshot == nil)
            if expert {
                Divider()
                Button(String(localized: "Clean up thoroughly", bundle: .module)) { if let window { LongTailActions.maintenance(window, .gcAggressive) } }.disabled(window == nil)
                Button(String(localized: "Clean up and prune now", bundle: .module)) { if let window { LongTailActions.maintenance(window, .gcPruneNow) } }.disabled(window == nil)
                Button(String(localized: "Pack refs", bundle: .module)) { if let window { LongTailActions.maintenance(window, .packRefs) } }.disabled(window == nil)
                Button(String(localized: "Prune unreachable objects", bundle: .module)) { if let window { LongTailActions.maintenance(window, .prune) } }.disabled(window == nil)
                Button(String(localized: "Repack", bundle: .module)) { if let window { LongTailActions.maintenance(window, .repack) } }.disabled(window == nil)
                Button(String(localized: "Write commit graph", bundle: .module)) { if let window { LongTailActions.maintenance(window, .commitGraph) } }.disabled(window == nil)
                Button(String(localized: "Pack loose objects", bundle: .module)) { if let window { CoverageActions.packLooseObjects(window) } }.disabled(window == nil)
                Button(String(localized: "Find redundant packs", bundle: .module)) { if let window { CoverageActions.findRedundantPacks(window) } }.disabled(window == nil)
                Button(String(localized: "Recover objects from a pack file\u{2026}", bundle: .module)) { if let window { CoverageActions.recoverObjects(window) } }.disabled(window == nil)
                if window?.store.hasPromisorPacks == true {
                    Button(String(localized: "Download missing files", bundle: .module)) { if let window { LongTailActions.maintenance(window, .backfill) } }
                }
            }
        }
        Button(String(localized: "Repository info\u{2026}", bundle: .module)) { if let window { LongTailActions.openInfo(window) } }.disabled(window?.store.snapshot == nil)
        Button(String(localized: "Edit .gitignore", bundle: .module)) { if let window { LongTailActions.openTextFile(window, .gitignore) } }.disabled(window?.store.snapshot?.root == nil)
        if expert {
            Button(String(localized: "Edit .gitattributes", bundle: .module)) { if let window { LongTailActions.openTextFile(window, .gitattributes) } }.disabled(window?.store.snapshot?.root == nil)
            Button(String(localized: "Edit .mailmap", bundle: .module)) { if let window { LongTailActions.openTextFile(window, .mailmap) } }.disabled(window?.store.snapshot?.root == nil)
        }
        Divider()
        Button(String(localized: "Open in Terminal", bundle: .module)) { if let window { LongTailActions.openInTerminal(window) } }.disabled(window?.store.snapshot?.root == nil)
        Button(String(localized: "Reveal in Finder", bundle: .module)) {
            if let root = window?.store.snapshot?.root { NSWorkspace.shared.activateFileViewerSelecting([root]) }
        }
        .disabled(window?.store.snapshot?.root == nil)
    }

    @ViewBuilder var branchItems: some View {
        let head = window?.headName ?? ""
        let branch = window?.store.snapshot?.currentBranch
        Button(String(localized: "New branch\u{2026}", bundle: .module)) { window?.sync.newBranch() }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(window?.store.snapshot == nil)
        Button(String(localized: "Switch to\u{2026}", bundle: .module)) { window?.openPalette(.branches) }
            .keyboardShortcut("b")
            .disabled(window?.store.snapshot == nil)
        Button(String(localized: "Rename \(head)\u{2026}", bundle: .module)) { if let branch { window?.sync.rename(branch.name) } }.disabled(branch == nil)
        Button(branch?.upstream == nil ? String(localized: "Set upstream\u{2026}", bundle: .module) : String(localized: "Change upstream\u{2026}", bundle: .module)) { if let branch { window?.sync.editUpstream(branch.name) } }.disabled(branch == nil)
        Divider()
        Button(String(localized: "Merge into \(head)\u{2026}", bundle: .module)) { if let window { RewriteActions.openMerge(window) } }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(window?.store.snapshot == nil)
        Button(String(localized: "Rebase \(head)\u{2026}", bundle: .module)) { if let window { RewriteActions.openRebase(window) } }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(branch == nil)
        Button(String(localized: "Interactive rebase\u{2026}", bundle: .module)) { if let window { RewriteActions.openInteractive(window) } }
            .keyboardShortcut("r", modifiers: [.command, .shift, .option])
            .disabled(branch == nil)
        Divider()
        Button(String(localized: "Start bisect\u{2026}", bundle: .module)) { if let window { RewriteActions.openBisect(window) } }
            .disabled(window?.store.snapshot?.state.isOperationInProgress ?? true)
        Button(String(localized: "Compare branches\u{2026}", bundle: .module)) { if let window { LongTailActions.openCompare(window) } }.disabled(window?.store.snapshot?.headOID == nil)
    }

    @ViewBuilder var commitItems: some View {
        let head = window?.headName ?? ""
        CommitChangesItems(window: window)
        Divider()
        Button(String(localized: "Cherry-pick selected", bundle: .module)) { if let window, let id = window.store.selection?.commitID { RewriteActions.openCherryPick(window, ids: [id]) } }
            .disabled(window?.store.selection?.commitID == nil)
        Button(String(localized: "Revert selected", bundle: .module)) { if let window, let id = window.store.selection?.commitID { RewriteActions.revert(window, id: id) } }
            .disabled(window?.store.selection?.commitID == nil)
        Button(String(localized: "Reset \(head) to selected\u{2026}", bundle: .module)) { if let window, let id = window.store.selection?.commitID { RewriteActions.openReset(window, target: id) } }
            .disabled(window?.store.selection?.commitID == nil)
        Button(String(localized: "Tag selected\u{2026}", bundle: .module)) { if let id = window?.store.selection?.commitID { window?.sync.newTag(target: id.rawValue) } }.disabled(window?.store.selection?.commitID == nil)
        if app.preferences.expert {
            Divider()
            Button(String(localized: "Reword selected in place\u{2026}", bundle: .module)) { if let window, let id = window.store.selection?.commitID { LongTailActions.openReword(window, id: id) } }
                .disabled(window?.store.selection?.commitID == nil)
            Button(String(localized: "Split selected\u{2026}", bundle: .module)) { if let window, let id = window.store.selection?.commitID { LongTailActions.openSplit(window, id: id) } }
                .disabled(window?.store.selection?.commitID == nil)
        }
    }
}
