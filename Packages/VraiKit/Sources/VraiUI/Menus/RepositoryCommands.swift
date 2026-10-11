import AppKit
import SwiftUI
import VraiCore
import VraiGit

public struct RepositoryCommands: Commands {
    let app: AppModel
    @FocusedValue(\.windowModel) private var window
    @Environment(\.openWindow) private var openWindow

    public init(app: AppModel) {
        self.app = app
    }

    public var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(String(localized: "About Vrai", bundle: .module)) { openWindow(id: "about") }
        }
        CommandGroup(after: .appSettings) {
            Button(String(localized: "Check for updates\u{2026}", bundle: .module)) {}
                .disabled(true)
        }
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "New repository\u{2026}", bundle: .module)) {}
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(true)
            Button(String(localized: "Open\u{2026}", bundle: .module)) {
                OpenPanel.choose(app: app) { openWindow(value: $0) }
            }
            .keyboardShortcut("o")
            Button(String(localized: "Clone\u{2026}", bundle: .module)) {}
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(true)
            Menu(String(localized: "Open recent", bundle: .module)) {
                ForEach(app.recents) { recent in
                    Button(recent.name) { openWindow(value: app.request(RepositoryReference(path: recent.path))) }
                }
            }
            Divider()
            Button(String(localized: "Welcome window", bundle: .module)) { openWindow(id: "welcome") }
                .keyboardShortcut("1", modifiers: [.command, .shift])
        }
        CommandGroup(after: .undoRedo) {
            Button(String(localized: "Undo history\u{2026}", bundle: .module)) {}
                .disabled(true)
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
            Button(String(localized: "Command palette", bundle: .module)) {}
                .keyboardShortcut("k")
                .disabled(true)
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
            Button(String(localized: "Welcome to Vrai", bundle: .module)) { openWindow(id: "welcome") }
            Divider()
        }
        CommandGroup(replacing: .help) {
            Button(String(localized: "Keyboard shortcuts", bundle: .module)) {}
                .disabled(true)
            Menu(String(localized: "Git reference", bundle: .module)) {
                ForEach(["rebase", "reset", "reflog", "bisect", "worktree", "cherry-pick"], id: \.self) { command in
                    Button("git " + command) {}.disabled(true)
                }
            }
            Button(String(localized: "Report a git problem\u{2026}", bundle: .module)) {}
                .disabled(true)
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
        Button(String(localized: "Show console", bundle: .module)) {}
            .keyboardShortcut("j")
            .disabled(true)
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
        Button(String(localized: "Fetch", bundle: .module)) {}
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(true)
            .modifierKeyAlternate(.option) {
                Button(String(localized: "Fetch all remotes and prune", bundle: .module)) {}
                    .keyboardShortcut("f", modifiers: [.command, .shift, .option])
                    .disabled(true)
            }
        Button(behind > 0 ? String(localized: "Pull \(n(behind, "commit"))", bundle: .module) : String(localized: "Pull", bundle: .module)) {}
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(true)
            .modifierKeyAlternate(.option) {
                Button(String(localized: "Pull with rebase", bundle: .module)) {}
                    .keyboardShortcut("l", modifiers: [.command, .shift, .option])
                    .disabled(true)
            }
        Button(ahead > 0 ? String(localized: "Push \(n(ahead, "commit"))", bundle: .module) : String(localized: "Push", bundle: .module)) {}
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(true)
            .modifierKeyAlternate(.option) {
                Button(String(localized: "Force push with lease", bundle: .module)) {}
                    .keyboardShortcut("p", modifiers: [.command, .shift, .option])
                    .disabled(true)
            }
        Button(String(localized: "Fetch, pull and push with options\u{2026}", bundle: .module)) {}.disabled(true)
        Divider()
        Button(String(localized: "Stash changes\u{2026}", bundle: .module)) {}
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(true)
        Button(String(localized: "Apply latest stash", bundle: .module)) {}
            .disabled(true)
            .modifierKeyAlternate(.option) {
                Button(String(localized: "Pop latest stash", bundle: .module)) {}.disabled(true)
            }
        Divider()
        Menu(String(localized: "Remotes", bundle: .module)) {
            Button(String(localized: "Add remote\u{2026}", bundle: .module)) {}.disabled(true)
            ForEach(window?.store.snapshot?.remotes ?? []) { remote in
                Button(String(localized: "Edit \(remote.name)\u{2026}", bundle: .module)) {}.disabled(true)
            }
        }
        Button(String(localized: "Add worktree\u{2026}", bundle: .module)) {}.disabled(true)
        Button(String(localized: "Add submodule\u{2026}", bundle: .module)) {}.disabled(true)
        Button(String(localized: "Apply patches\u{2026}", bundle: .module)) {}.disabled(true)
        Button(String(localized: "Create bundle\u{2026}", bundle: .module)) {}.disabled(true)
        if expert {
            Button(String(localized: "Sparse checkout\u{2026}", bundle: .module)) {}.disabled(true)
        }
        Divider()
        Menu(String(localized: "Maintenance", bundle: .module)) {
            Button(String(localized: "Clean up", bundle: .module)) {}.disabled(true)
            Button(String(localized: "Verify integrity", bundle: .module)) {}.disabled(true)
            Button(String(localized: "Run background maintenance now", bundle: .module)) {}.disabled(true)
            if expert {
                Divider()
                Button(String(localized: "Prune unreachable objects", bundle: .module)) {}.disabled(true)
                Button(String(localized: "Repack", bundle: .module)) {}.disabled(true)
                Button(String(localized: "Write commit graph", bundle: .module)) {}.disabled(true)
            }
        }
        Button(String(localized: "Repository info\u{2026}", bundle: .module)) {}.disabled(true)
        Button(String(localized: "Edit .gitignore", bundle: .module)) {}.disabled(true)
        if expert {
            Button(String(localized: "Edit .gitattributes", bundle: .module)) {}.disabled(true)
            Button(String(localized: "Edit .mailmap", bundle: .module)) {}.disabled(true)
        }
        Divider()
        Button(String(localized: "Open in Terminal", bundle: .module)) {}.disabled(true)
        Button(String(localized: "Reveal in Finder", bundle: .module)) {
            if let root = window?.store.snapshot?.root { NSWorkspace.shared.activateFileViewerSelecting([root]) }
        }
        .disabled(window?.store.snapshot?.root == nil)
    }

    @ViewBuilder var branchItems: some View {
        let head = window?.headName ?? ""
        let branch = window?.store.snapshot?.currentBranch
        Button(String(localized: "New branch\u{2026}", bundle: .module)) {}
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(true)
        Button(String(localized: "Switch to\u{2026}", bundle: .module)) {}
            .keyboardShortcut("b")
            .disabled(true)
        Button(String(localized: "Rename \(head)\u{2026}", bundle: .module)) {}.disabled(true)
        Button(branch?.upstream == nil ? String(localized: "Set upstream\u{2026}", bundle: .module) : String(localized: "Change upstream\u{2026}", bundle: .module)) {}.disabled(true)
        Divider()
        Button(String(localized: "Merge into \(head)\u{2026}", bundle: .module)) {}
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(true)
        Button(String(localized: "Rebase \(head)\u{2026}", bundle: .module)) {}
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(true)
        Button(String(localized: "Interactive rebase\u{2026}", bundle: .module)) {}
            .keyboardShortcut("r", modifiers: [.command, .shift, .option])
            .disabled(true)
        Divider()
        Button(String(localized: "Start bisect\u{2026}", bundle: .module)) {}.disabled(true)
        Button(String(localized: "Compare branches\u{2026}", bundle: .module)) {}.disabled(true)
    }

    @ViewBuilder var commitItems: some View {
        let head = window?.headName ?? ""
        Button(String(localized: "Commit", bundle: .module)) {}
            .keyboardShortcut(.return)
            .disabled(true)
            .modifierKeyAlternate(.option) {
                Button(String(localized: "Commit and push", bundle: .module)) {}
                    .keyboardShortcut(.return, modifiers: [.command, .option])
                    .disabled(true)
            }
        Button(String(localized: "Amend last commit", bundle: .module)) {}.disabled(true)
        Divider()
        Button(String(localized: "Stage all", bundle: .module)) {}
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(true)
            .modifierKeyAlternate(.option) {
                Button(String(localized: "Stage all, including untracked", bundle: .module)) {}.disabled(true)
            }
        Button(String(localized: "Unstage all", bundle: .module)) {}.disabled(true)
        Button(String(localized: "Discard all changes\u{2026}", bundle: .module)) {}.disabled(true)
        Divider()
        Button(String(localized: "Cherry-pick selected", bundle: .module)) {}.disabled(true)
        Button(String(localized: "Revert selected", bundle: .module)) {}.disabled(true)
        Button(String(localized: "Reset \(head) to selected\u{2026}", bundle: .module)) {}.disabled(true)
        Button(String(localized: "Tag selected\u{2026}", bundle: .module)) {}.disabled(true)
        if app.preferences.expert {
            Divider()
            Button(String(localized: "Reword selected in place\u{2026}", bundle: .module)) {}.disabled(true)
            Button(String(localized: "Split selected\u{2026}", bundle: .module)) {}.disabled(true)
        }
    }
}
