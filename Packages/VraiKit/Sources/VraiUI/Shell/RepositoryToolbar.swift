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
        if window.widthClass.isNarrow {
            ToolbarItem(placement: .primaryAction) {
                ToolbarCapsule(label: String(localized: "Actions", bundle: .module)) {
                    NarrowActions(window: window)
                }
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) {
                ToolbarCapsule(label: String(localized: "Sync", bundle: .module)) {
                    SyncButtons(window: window)
                }
            }
            .sharedBackgroundVisibility(.hidden)
            if window.widthClass >= .regular {
                ToolbarItem(placement: .primaryAction) {
                    ToolbarCapsule(label: String(localized: "Branch", bundle: .module)) {
                        BranchButtons(window: window)
                    }
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .primaryAction) {
                    ToolbarCapsule(label: String(localized: "Stash", bundle: .module)) {
                        ToolbarIconButton(icon: "tray.and.arrow.down", label: window.optionDown ? String(localized: "Stash including untracked files", bundle: .module) : String(localized: "Stash changes", bundle: .module), shortcut: "\u{21E7}\u{2318}S", enabled: false)
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            ToolbarItem(placement: .primaryAction) {
                ToolbarField(window: window)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) {
                ToolbarCapsule(label: String(localized: "Panels", bundle: .module)) {
                    PanelButtons(window: window)
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}

struct ToolbarCapsule<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, Vrai.Space.s2)
        .frame(height: Vrai.Size.toolbarItem)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

struct ToolbarButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, active: active)
    }

    struct StyledBody: View {
        let configuration: Configuration
        let active: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(!enabled ? Color.Vrai.textDisabled : active ? Color.Vrai.accentText : Color.Vrai.text)
                .padding(.horizontal, Vrai.Space.s8)
                .frame(minWidth: Metrics.toolbarButtonMin, minHeight: Metrics.toolbarButton, maxHeight: Metrics.toolbarButton)
                .background(active ? Color.Vrai.accentSoft : configuration.isPressed ? Color.Vrai.fillActive : (hovering && enabled ? Color.Vrai.fillHover : Color.clear), in: Capsule())
                .contentShape(Capsule())
                .onHover { hovering = $0 }
        }
    }
}

struct ToolbarIconButton: View {
    let icon: String
    let label: String
    var shortcut: String?
    var badge: Int?
    var active = false
    var busy = false
    var enabled = true
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: Vrai.Space.s4) {
                if busy {
                    Spinner()
                } else {
                    Symbol(icon, font: Font.Vrai.title3)
                }
                if let badge, badge != 0 {
                    Text(String(badge))
                        .font(Font.Vrai.captionStrong)
                        .monospacedDigit()
                        .foregroundStyle(enabled ? Color.Vrai.accentText : Color.Vrai.textDisabled)
                }
            }
        }
        .buttonStyle(ToolbarButtonStyle(active: active))
        .disabled(!enabled)
        .help(shortcut.map { label + "  " + $0 } ?? label)
        .accessibilityLabel(label)
    }
}

struct ToolbarTitle: View {
    let window: WindowModel

    var body: some View {
        let snapshot = window.store.snapshot
        HStack(spacing: Vrai.Space.s6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(window.repositoryName)
                    .font(Font.Vrai.headline)
                    .foregroundStyle(Color.Vrai.text)
                    .lineLimit(1)
                HStack(spacing: Vrai.Space.s4) {
                    Symbol(isDetached(snapshot) ? "mappin.and.ellipse" : "arrow.triangle.branch", font: Font.Vrai.caption)
                        .foregroundStyle(laneColor(snapshot))
                    Text(subtitle(snapshot))
                        .font(Font.Vrai.caption)
                        .foregroundStyle(Color.Vrai.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: window.widthClass == .compact ? Metrics.compactTitle : nil, alignment: .leading)
            Symbol("chevron.down", font: Font.Vrai.overline)
                .foregroundStyle(Color.Vrai.textTertiary)
        }
        .padding(.horizontal, Vrai.Space.s6)
        .frame(height: Vrai.Size.toolbarItem)
        .help(String(localized: "Switch branch", bundle: .module))
        .accessibilityElement(children: .combine)
    }

    func isDetached(_ snapshot: RepositorySnapshot?) -> Bool {
        if case .detached? = snapshot?.head { return true }
        return false
    }

    func laneColor(_ snapshot: RepositorySnapshot?) -> Color {
        guard let snapshot else { return Color.Vrai.textTertiary }
        return window.store.headColor(snapshot).map { Color.Vrai.lane($0) } ?? Color.Vrai.textTertiary
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
        ToolbarIconButton(icon: "arrow.triangle.2.circlepath", label: labels.fetch, shortcut: alt ? "\u{2325}\u{21E7}\u{2318}F" : "\u{21E7}\u{2318}F", busy: window.store.busy.contains("fetch"), enabled: false)
        ToolbarIconButton(icon: "arrow.down.to.line", label: labels.pull, shortcut: alt ? "\u{2325}\u{21E7}\u{2318}L" : "\u{21E7}\u{2318}L", badge: alt ? nil : labels.behind, busy: window.store.busy.contains("pull"), enabled: false)
        ToolbarIconButton(icon: "arrow.up.to.line", label: labels.push, shortcut: alt ? "\u{2325}\u{21E7}\u{2318}P" : "\u{21E7}\u{2318}P", badge: alt ? nil : labels.ahead, busy: window.store.busy.contains("push"), enabled: false)
    }
}

struct BranchButtons: View {
    let window: WindowModel

    var body: some View {
        let alt = window.optionDown
        ToolbarIconButton(icon: "arrow.triangle.branch", label: String(localized: "New branch", bundle: .module), shortcut: "\u{21E7}\u{2318}B", enabled: false)
        ToolbarIconButton(icon: "arrow.triangle.merge", label: alt ? String(localized: "Merge with a merge commit", bundle: .module) : String(localized: "Merge", bundle: .module), shortcut: "\u{21E7}\u{2318}M", enabled: false)
        ToolbarIconButton(icon: "arrow.triangle.swap", label: alt ? String(localized: "Interactive rebase", bundle: .module) : String(localized: "Rebase", bundle: .module), shortcut: alt ? "\u{2325}\u{21E7}\u{2318}R" : "\u{21E7}\u{2318}R", enabled: false)
    }
}

struct PanelButtons: View {
    let window: WindowModel

    var body: some View {
        ToolbarIconButton(icon: "terminal", label: String(localized: "Show console", bundle: .module), shortcut: "\u{2318}J", enabled: false)
        ToolbarIconButton(icon: "sidebar.right", label: window.preferences.inspector ? String(localized: "Hide inspector", bundle: .module) : String(localized: "Show inspector", bundle: .module), shortcut: "\u{2325}\u{2318}0", active: window.preferences.inspector) {
            window.preferences.inspector.toggle()
        }
    }
}

struct ToolbarField: View {
    let window: WindowModel

    var body: some View {
        let showText = window.widthClass == .wide
        HStack(spacing: Vrai.Space.s8) {
            Symbol("magnifyingglass", font: Font.Vrai.body)
            if showText {
                Text(window.preferences.expert ? String(localized: "Search or run a git command", bundle: .module) : String(localized: "Search actions, branches, commits", bundle: .module))
                    .font(Font.Vrai.body)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(verbatim: "\u{2318}K")
                .font(Font.Vrai.callout)
        }
        .foregroundStyle(Color.Vrai.textTertiary)
        .padding(.horizontal, Vrai.Space.s12)
        .frame(width: showText ? Vrai.Size.field : nil, height: Vrai.Size.toolbarItem)
        .glassEffect(.regular, in: Capsule())
        .help(String(localized: "Command palette", bundle: .module))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Search actions, branches, commits", bundle: .module))
        .accessibilityAddTraits(.isButton)
    }
}

struct NarrowActions: View {
    let window: WindowModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let labels = SyncLabels(window: window)
        Menu {
            Button(labels.fetch, systemImage: "arrow.triangle.2.circlepath") {}.disabled(true)
            Button(labels.pull, systemImage: "arrow.down.to.line") {}.disabled(true)
            Button(labels.push, systemImage: "arrow.up.to.line") {}.disabled(true)
        } label: {
            HStack(spacing: Vrai.Space.s4) {
                Symbol("arrow.up.arrow.down", font: Font.Vrai.title3)
                if labels.ahead + labels.behind > 0 {
                    Text(String(labels.ahead + labels.behind))
                        .font(Font.Vrai.captionStrong)
                        .monospacedDigit()
                        .foregroundStyle(Color.Vrai.accentText)
                }
            }
        }
        .menuStyle(.button)
        .buttonStyle(ToolbarButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "Sync", bundle: .module))
        ToolbarIconButton(icon: "magnifyingglass", label: String(localized: "Search", bundle: .module), enabled: false)
        Menu {
            Button(String(localized: "New branch\u{2026}", bundle: .module), systemImage: "arrow.triangle.branch") {}.disabled(true)
            Button(String(localized: "Merge\u{2026}", bundle: .module), systemImage: "arrow.triangle.merge") {}.disabled(true)
            Button(String(localized: "Rebase\u{2026}", bundle: .module), systemImage: "arrow.triangle.swap") {}.disabled(true)
            Button(String(localized: "Stash changes\u{2026}", bundle: .module), systemImage: "tray.and.arrow.down") {}.disabled(true)
            Divider()
            Button(String(localized: "Show console", bundle: .module), systemImage: "terminal") {}.disabled(true)
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
            Symbol("ellipsis", font: Font.Vrai.title3)
        }
        .menuStyle(.button)
        .buttonStyle(ToolbarButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "More", bundle: .module))
    }
}
