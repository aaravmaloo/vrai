import SwiftUI
import VraiCore
import VraiGit

struct RepositoryToolbar: ToolbarContent {
    let window: WindowModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            ToolbarTitle(window: window)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem {
            Spacer(minLength: 0)
        }
        .sharedBackgroundVisibility(.hidden)
        if window.widthClass.isNarrow {
            ToolbarItem {
                ToolbarGlassGroup { NarrowActions(window: window) }
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem {
                ToolbarGlassGroup { SyncButtons(window: window) }
            }
            .sharedBackgroundVisibility(.hidden)
            if window.widthClass >= .regular {
                ToolbarItem {
                    ToolbarGlassGroup { BranchButtons(window: window) }
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem {
                    ToolbarGlassGroup { StashButton(window: window) }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            ToolbarItem {
                ToolbarGlassGroup { PaletteButton(window: window) }
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem {
                ToolbarGlassGroup { PanelToggles(window: window) }
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}

struct ToolbarGlassGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, Vrai.Space.s2)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

enum ToolbarMotion {
    case bounce
    case bounceDown
    case bounceUp
    case spin
}

struct ToolbarIcon: View {
    let icon: String
    var motion: ToolbarMotion = .bounce
    var busy = false
    var count = 0
    var tinted = false
    let taps: Int

    var body: some View {
        symbol
            .font(.title3.weight(.regular))
            .foregroundStyle(tinted ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .frame(width: Vrai.Size.toolbarItem + Vrai.Space.s4, height: Vrai.Size.toolbarItem)
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text(verbatim: String(count))
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, Vrai.Space.s4)
                        .frame(minWidth: Vrai.Space.s16, minHeight: Vrai.Space.s16)
                        .background(Color.Vrai.accent, in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
    }

    @ViewBuilder var symbol: some View {
        let image = Image(systemName: icon)
        switch motion {
        case .spin:
            image
                .symbolEffect(.rotate, value: taps)
                .symbolEffect(.rotate, isActive: busy)
        case .bounceDown:
            if busy { Spinner() } else { image.symbolEffect(.bounce.down, value: taps) }
        case .bounceUp:
            if busy { Spinner() } else { image.symbolEffect(.bounce.up, value: taps) }
        case .bounce:
            if busy { Spinner() } else { image.symbolEffect(.bounce, value: taps) }
        }
    }
}

struct ToolbarAction: View {
    let title: String
    let icon: String
    let identifier: String
    var shortcut: String?
    var count = 0
    var busy = false
    var enabled = true
    var motion: ToolbarMotion = .bounce
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            ToolbarIcon(icon: icon, motion: motion, busy: busy, count: count, taps: taps)
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .help(shortcut.map { title + "  " + $0 } ?? title)
        .accessibilityLabel(title)
        .accessibilityValue(count > 0 ? Text(verbatim: String(count)) : Text(verbatim: ""))
        .accessibilityIdentifier(identifier)
    }
}

struct ToolbarToggle: View {
    let title: String
    let icon: String
    let identifier: String
    let shortcut: String
    @Binding var isOn: Bool
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            isOn.toggle()
        } label: {
            ToolbarIcon(icon: icon, tinted: isOn, taps: taps)
        }
        .buttonStyle(.borderless)
        .help(title + "  " + shortcut)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

struct ToolbarTitle: View {
    let window: WindowModel
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var context: PaletteContext {
        let openWindow = openWindow
        return PaletteContext(
            window: window,
            app: app,
            openWindowID: { openWindow(id: $0) },
            openRepository: { openWindow(value: $0) }
        )
    }

    var body: some View {
        let snapshot = window.store.snapshot
        Button {
            window.openPalette(.branches)
        } label: {
            HStack(spacing: Vrai.Space.s6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(window.repositoryName)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: Vrai.Space.s4) {
                        Image(systemName: isDetached(snapshot) ? "mappin.and.ellipse" : "arrow.triangle.branch")
                            .foregroundStyle(laneColor(snapshot))
                            .accessibilityHidden(true)
                        Text(subtitle(snapshot))
                            .lineLimit(1)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: window.widthClass == .compact ? Metrics.compactTitle : nil, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Vrai.Space.s6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "Switch branch", bundle: .module))
        .popover(isPresented: Binding(get: { window.branchPicker }, set: { window.branchPicker = $0 }), arrowEdge: .bottom) {
            BranchPicker(context: context)
        }
    }

    func isDetached(_ snapshot: RepositorySnapshot?) -> Bool {
        if case .detached? = snapshot?.head { return true }
        return false
    }

    func laneColor(_ snapshot: RepositorySnapshot?) -> Color {
        guard let snapshot else { return .secondary }
        return window.store.headColor(snapshot).map { Color.Vrai.lane($0) } ?? .secondary
    }

    func subtitle(_ snapshot: RepositorySnapshot?) -> String {
        guard let snapshot else { return "" }
        switch snapshot.state {
        case .rebasing(_, _, _, _, let branch, _):
            return String(localized: "Rebasing \(branch ?? window.headName)", bundle: .module)
        case .bisecting:
            return String(localized: "Bisecting at \(snapshot.headOID?.short ?? "")", bundle: .module)
        case .detached(let id, _):
            return String(localized: "HEAD at \(id.short)", bundle: .module)
        default:
            return window.headName
        }
    }
}

struct SyncLabels {
    let fetch: String
    let pull: String
    let push: String
    let ahead: Int
    let behind: Int
    let onBranch: Bool

    @MainActor init(window: WindowModel) {
        let snapshot = window.store.snapshot
        let branch = snapshot?.currentBranch
        let alt = window.optionDown
        ahead = branch?.ahead ?? 0
        behind = branch?.behind ?? 0
        onBranch = branch != nil
        fetch = alt ? String(localized: "Fetch all remotes and prune", bundle: .module) : String(localized: "Fetch", bundle: .module)
        if alt {
            pull = String(localized: "Pull with rebase", bundle: .module)
            push = String(localized: "Force push with lease", bundle: .module)
        } else {
            pull = behind > 0 ? String(localized: "Pull \(n(behind, "commit"))", bundle: .module) : String(localized: "Pull", bundle: .module)
            if ahead > 0 {
                push = String(localized: "Push \(n(ahead, "commit"))", bundle: .module)
            } else if let branch, branch.upstream == nil {
                push = String(localized: "Publish \(branch.name)", bundle: .module)
            } else {
                push = String(localized: "Push", bundle: .module)
            }
        }
    }
}

struct SyncButtons: View {
    let window: WindowModel

    var body: some View {
        let labels = SyncLabels(window: window)
        let alt = window.optionDown
        let sync = window.sync
        ToolbarAction(title: sync.busyLabel(.fetch) ?? labels.fetch, icon: "arrow.triangle.2.circlepath", identifier: "toolbar-fetch", shortcut: alt ? "\u{2325}\u{21E7}\u{2318}F" : "\u{21E7}\u{2318}F", busy: sync.isBusy(.fetch), motion: .spin) { alt ? sync.fetch(all: true) : sync.fetch() }
        ToolbarAction(title: sync.busyLabel(.pull) ?? labels.pull, icon: "arrow.down.to.line", identifier: "toolbar-pull", shortcut: alt ? "\u{2325}\u{21E7}\u{2318}L" : "\u{21E7}\u{2318}L", count: alt ? 0 : labels.behind, busy: sync.isBusy(.pull), enabled: labels.onBranch, motion: .bounceDown) { alt ? sync.pull(mode: .rebase) : sync.pull() }
        ToolbarAction(title: sync.busyLabel(.push) ?? labels.push, icon: "arrow.up.to.line", identifier: "toolbar-push", shortcut: alt ? "\u{2325}\u{21E7}\u{2318}P" : "\u{21E7}\u{2318}P", count: alt ? 0 : labels.ahead, busy: sync.isBusy(.push), enabled: labels.onBranch, motion: .bounceUp) { alt ? sync.push(force: .withLease) : sync.push() }
    }
}

struct BranchButtons: View {
    let window: WindowModel

    var body: some View {
        let alt = window.optionDown
        let busy = window.store.busy
        ToolbarAction(title: String(localized: "New branch", bundle: .module), icon: "arrow.triangle.branch", identifier: "toolbar-new-branch", shortcut: "\u{21E7}\u{2318}B") { window.sync.newBranch() }
        ToolbarAction(title: alt ? String(localized: "Merge with a merge commit", bundle: .module) : String(localized: "Merge", bundle: .module), icon: "arrow.triangle.merge", identifier: "toolbar-merge", shortcut: "\u{21E7}\u{2318}M", busy: busy.contains("merge"), enabled: window.store.snapshot != nil) { RewriteToolbar.merge(window) }
        ToolbarAction(title: alt ? String(localized: "Interactive rebase", bundle: .module) : String(localized: "Rebase", bundle: .module), icon: "arrow.triangle.swap", identifier: "toolbar-rebase", shortcut: alt ? "\u{2325}\u{21E7}\u{2318}R" : "\u{21E7}\u{2318}R", busy: busy.contains("rebase") || busy.contains("interactiveRebase"), enabled: window.store.snapshot?.currentBranch != nil) { RewriteToolbar.rebase(window) }
    }
}

struct StashButton: View {
    let window: WindowModel

    var body: some View {
        ToolbarAction(title: window.optionDown ? String(localized: "Stash including untracked files", bundle: .module) : String(localized: "Stash changes", bundle: .module), icon: "tray.and.arrow.down", identifier: "toolbar-stash", shortcut: "\u{21E7}\u{2318}S", busy: window.store.busy.contains("stash"), enabled: !(window.store.snapshot?.working.isEmpty ?? true)) { RewriteToolbar.stash(window) }
    }
}

struct PaletteButton: View {
    let window: WindowModel

    var body: some View {
        let prompt = window.preferences.expert ? String(localized: "Search or run a git command", bundle: .module) : String(localized: "Search actions, branches, commits", bundle: .module)
        ToolbarAction(title: prompt, icon: "magnifyingglass", identifier: "toolbar-palette-field", shortcut: "\u{2318}K") {
            window.openPalette()
        }
    }
}

struct PanelToggles: View {
    let window: WindowModel

    var body: some View {
        let console = window.console
        let preferences = window.preferences
        ToolbarToggle(
            title: console.open ? String(localized: "Hide console", bundle: .module) : String(localized: "Show console", bundle: .module),
            icon: "terminal",
            identifier: "toolbar-console",
            shortcut: "\u{2318}J",
            isOn: Binding(get: { console.open }, set: { if $0 != console.open { console.toggle() } })
        )
        ToolbarToggle(
            title: preferences.inspector ? String(localized: "Hide inspector", bundle: .module) : String(localized: "Show inspector", bundle: .module),
            icon: "sidebar.right",
            identifier: "toolbar-inspector",
            shortcut: "\u{2325}\u{2318}0",
            isOn: Binding(get: { preferences.inspector }, set: { preferences.inspector = $0 })
        )
    }
}

struct NarrowActions: View {
    let window: WindowModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let labels = SyncLabels(window: window)
        Menu {
            SyncMenuItems(window: window, labels: labels)
        } label: {
            ToolbarIcon(icon: "arrow.up.arrow.down", count: labels.ahead + labels.behind, taps: 0)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .accessibilityLabel(String(localized: "Sync", bundle: .module))
        .help(String(localized: "Sync", bundle: .module))
        .accessibilityIdentifier("toolbar-sync")
        PaletteButton(window: window)
        Menu {
            Button(String(localized: "New branch\u{2026}", bundle: .module), systemImage: "arrow.triangle.branch") { window.sync.newBranch() }
            Button(String(localized: "Merge\u{2026}", bundle: .module), systemImage: "arrow.triangle.merge") { RewriteActions.openMerge(window) }
            Button(String(localized: "Rebase\u{2026}", bundle: .module), systemImage: "arrow.triangle.swap") { RewriteActions.openRebase(window) }.disabled(window.store.snapshot?.currentBranch == nil)
            Button(String(localized: "Stash changes\u{2026}", bundle: .module), systemImage: "tray.and.arrow.down") { RewriteActions.openStash(window) }.disabled(window.store.snapshot?.working.isEmpty ?? true)
            Divider()
            Button(window.console.open ? String(localized: "Hide console", bundle: .module) : String(localized: "Show console", bundle: .module), systemImage: "terminal") { window.console.toggle() }
            Toggle(isOn: Binding(get: { window.preferences.expert }, set: { _ in window.toggleExpert() })) {
                Label(String(localized: "Expert mode", bundle: .module), systemImage: "terminal")
            }
            Picker(selection: Binding(get: { window.preferences.theme }, set: { window.preferences.theme = $0 })) {
                Text("Match the system", bundle: .module).tag(Preferences.Theme.system)
                Text("Light", bundle: .module).tag(Preferences.Theme.light)
                Text("Dark", bundle: .module).tag(Preferences.Theme.dark)
            } label: {
                Label(String(localized: "Appearance", bundle: .module), systemImage: "circle.lefthalf.filled")
            }
            Button(String(localized: "Settings\u{2026}", bundle: .module), systemImage: "gearshape") { openSettings() }
        } label: {
            ToolbarIcon(icon: "ellipsis", taps: 0)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .accessibilityLabel(String(localized: "More", bundle: .module))
        .help(String(localized: "More", bundle: .module))
        .accessibilityIdentifier("toolbar-more")
    }
}
