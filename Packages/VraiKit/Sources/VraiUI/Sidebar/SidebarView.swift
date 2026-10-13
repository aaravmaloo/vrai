import SwiftUI
import VraiCore
import VraiGit

struct SidebarView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(Preferences.self) private var preferences
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            RepositorySwitcher()
                .padding(.horizontal, Vrai.Space.s6)
                .padding(.bottom, Vrai.Space.s4)
            ScrollViewReader { proxy in
                List(selection: selection) {
                    workspace
                    branches
                    remotes
                    tags
                    worktrees
                    submodules
                }
                .listStyle(.sidebar)
                .environment(\.sidebarRowSize, rowSize)
                .onChange(of: window.expandedSections) { old, new in
                    guard let key = SidebarAnchor.revealed.first(where: { new[$0] == true && old[$0] != true }) else { return }
                    Task { proxy.scrollTo(SidebarAnchor(key: key)) }
                }
            }
            HStack(spacing: Vrai.Space.s8) {
                Toggle(isOn: Binding(get: { preferences.expert }, set: { _ in window.toggleExpert() })) {
                    Text("Expert", bundle: .module)
                        .font(Font.Vrai.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help(String(localized: "Expert mode", bundle: .module))
                .accessibilityIdentifier("sidebar-expert")
                IconButton(icon: "gearshape", label: String(localized: "Settings", bundle: .module), small: true) {
                    openSettings()
                }
            }
            .padding(.horizontal, Vrai.Space.s12)
            .padding(.vertical, Vrai.Space.s8)
            .hairline(.top)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Repository", bundle: .module))
    }

    var snapshot: RepositorySnapshot? { store.snapshot }

    var rowSize: SidebarRowSize {
        switch preferences.density {
        case .compact: .small
        case .regular: .medium
        case .comfortable: .large
        }
    }

    var selectedKey: String? {
        switch store.view {
        case .changes: return SidebarKey.view(.changes)
        case .stashes: return SidebarKey.view(.stashes)
        case .reflog: return SidebarKey.view(.reflog)
        case .refs: return SidebarKey.view(.refs)
        case .worktrees: return PlacesActions.selectedWorktree(store).map(PlacesActions.worktreeKey)
        case .submodules: return PlacesActions.selectedSubmodule(store).map(PlacesActions.submoduleKey)
        case .history: return store.sidebarSelection ?? SidebarKey.view(.history)
        case .blame, .fileHistory: return store.sidebarSelection
        }
    }

    var selection: Binding<String?> {
        Binding(get: { selectedKey }, set: { key in
            guard let key, key != selectedKey else { return }
            choose(key)
        })
    }

    func choose(_ key: String) {
        if let view = SidebarKey.parseView(key) {
            if view == .history { store.sidebarSelection = nil }
            window.show(view)
        } else if key == "head" {
            pick(key, ref: "HEAD")
        } else if key.hasPrefix("branch:") {
            pick(key, ref: String(key.dropFirst("branch:".count)))
        } else if key.hasPrefix("remote:") {
            pick(key, ref: String(key.dropFirst("remote:".count)))
        } else if key.hasPrefix("tag:") {
            pick(key, ref: String(key.dropFirst("tag:".count)))
        } else if key.hasPrefix("worktree:") {
            PlacesActions.showWorktree(window, path: String(key.dropFirst("worktree:".count)))
        } else if key.hasPrefix("submodule:") {
            PlacesActions.showSubmodule(window, path: String(key.dropFirst("submodule:".count)))
        }
    }

    @ViewBuilder var workspace: some View {
        SidebarSection(title: String(localized: "Workspace", bundle: .module), key: "workspace", collapsible: false) {
            SidebarItem(icon: "clock.arrow.circlepath", label: String(localized: "History", bundle: .module))
                .tag(SidebarKey.view(.history))
            SidebarItem(icon: "square.and.pencil", label: String(localized: "Changes", bundle: .module), count: snapshot?.working.count, tone: snapshot?.conflicts.isEmpty == false ? .danger : nil)
                .tag(SidebarKey.view(.changes))
            SidebarItem(icon: "tray.full", label: String(localized: "Stashes", bundle: .module), count: snapshot?.stashes.count)
                .tag(SidebarKey.view(.stashes))
            if preferences.expert {
                SidebarItem(icon: "clock", label: String(localized: "Reflog", bundle: .module))
                    .tag(SidebarKey.view(.reflog))
                SidebarItem(icon: "point.3.connected.trianglepath.dotted", label: String(localized: "Refs", bundle: .module))
                    .tag(SidebarKey.view(.refs))
            }
        }
    }

    func pick(_ key: String, ref: String) {
        store.showRef(ref)
        store.sidebarSelection = key
        if window.widthClass.isNarrow { window.columns = .detailOnly }
    }

    @ViewBuilder var branches: some View {
        if let snapshot {
            let current = snapshot.head.branchName
            let names = snapshot.branches.map(\.name).sorted { a, b in
                if a == current { return true }
                if b == current { return false }
                if a == "main" { return true }
                if b == "main" { return false }
                return a < b
            }
            let tree = BranchTree(names: names)
            SidebarSection(title: String(localized: "Branches", bundle: .module), key: "branches", count: names.count, action: (icon: "plus", label: String(localized: "New branch", bundle: .module)), perform: { window.sync.newBranch() }) {
                if case .detached(let id) = snapshot.head {
                    SidebarItem(icon: "mappin.and.ellipse", label: String(localized: "HEAD at \(id.short)", bundle: .module), tone: .warning, current: true, help: String(localized: "Detached HEAD", bundle: .module))
                        .tag("head")
                }
                if case .unborn(let name) = snapshot.head {
                    SidebarItem(icon: "arrow.triangle.branch", iconColor: Color.Vrai.lane(0), label: name, detail: String(localized: "no commits yet", bundle: .module), current: true, muted: true)
                        .selectionDisabled()
                }
                BranchTreeView(node: tree.root, snapshot: snapshot)
            }
        }
    }

    @ViewBuilder var remotes: some View {
        if let snapshot, !snapshot.remotes.isEmpty {
            SidebarSection(title: String(localized: "Remotes", bundle: .module), key: "remotes", count: snapshot.remotes.count, action: (icon: "plus", label: String(localized: "Add remote", bundle: .module)), perform: { window.sync.addRemote() }) {
                ForEach(snapshot.remotes) { remote in
                    let row = SidebarItem(icon: "network", label: remote.name, detail: PathText.remoteDetail(remote.fetchURL), help: remote.fetchURL, trailing: SyncSidebar.badge(for: remote, snapshot: snapshot))
                        .simultaneousGesture(TapGesture(count: 2).onEnded { window.sync.editRemote(remote.name) })
                        .contextMenu { RemoteMenu(remote: remote, window: window) }
                    if preferences.showRemotes {
                        DisclosureGroup(isExpanded: folder("remote:" + remote.name, default: false)) {
                            ForEach(snapshot.remoteBranches.filter { $0.remote == remote.name }.sorted { $0.name < $1.name }) { branch in
                                SidebarItem(icon: "cloud", iconColor: Color.Vrai.lane(branch.colorIndex), label: branch.name, help: branch.fullName, trailing: SidebarChecks.glyph(window, branch.tip))
                                    .simultaneousGesture(TapGesture(count: 2).onEnded { window.sync.checkOut(remote: branch) })
                                    .contextMenu { RemoteBranchMenu(remote: branch, window: window) }
                                    .tag("remote:" + branch.fullName)
                            }
                        } label: {
                            row
                        }
                        .selectionDisabled()
                    } else {
                        row
                            .selectionDisabled()
                    }
                }
            }
        }
    }

    func folder(_ key: String, default value: Bool) -> Binding<Bool> {
        Binding(get: { window.expandedFolders[key] ?? value }, set: { window.expandedFolders[key] = $0 })
    }

    @ViewBuilder var tags: some View {
        if let snapshot, !snapshot.tags.isEmpty {
            SidebarSection(title: String(localized: "Tags", bundle: .module), key: "tags", count: snapshot.tags.count, defaultOpen: false, action: (icon: "plus", label: String(localized: "New tag", bundle: .module)), perform: { window.sync.newTag() }) {
                ForEach(snapshot.tags.sorted { $0.name.compare($1.name, options: .numeric) == .orderedDescending }.prefix(500)) { tag in
                    SidebarItem(icon: "tag", label: tag.name, detail: tag.annotated ? nil : String(localized: "lightweight", bundle: .module))
                        .contextMenu { TagMenu(tag: tag, window: window) }
                        .tag("tag:" + tag.name)
                }
            }
        }
    }

    @ViewBuilder var worktrees: some View {
        if let snapshot, snapshot.worktrees.count > 1 {
            SidebarSection(title: String(localized: "Worktrees", bundle: .module), key: "worktrees", count: snapshot.worktrees.count, defaultOpen: false, action: (icon: "plus", label: String(localized: "Add worktree", bundle: .module)), perform: { PlacesActions.openAddWorktree(window) }) {
                ForEach(snapshot.worktrees) { worktree in
                    SidebarItem(icon: "rectangle.on.rectangle", label: URL(filePath: worktree.path).lastPathComponent, detail: worktree.branch ?? String(localized: "detached", bundle: .module), help: worktree.path, trailing: worktree.locked ? AnyView(Image(systemName: "lock").foregroundStyle(.secondary)) : nil)
                        .contextMenu { WorktreeMenu(worktree: worktree, window: window, opener: PlacesOpener(app: app, openWindow: openWindow)) }
                        .tag(PlacesActions.worktreeKey(worktree.path))
                }
            }
        }
    }

    @ViewBuilder var submodules: some View {
        if let snapshot, !snapshot.submodules.isEmpty {
            SidebarSection(title: String(localized: "Submodules", bundle: .module), key: "submodules", count: snapshot.submodules.count, defaultOpen: false, action: (icon: "plus", label: String(localized: "Add submodule", bundle: .module)), perform: { PlacesActions.openAddSubmodule(window) }) {
                ForEach(snapshot.submodules) { module in
                    SidebarItem(icon: "shippingbox", label: URL(filePath: module.path).lastPathComponent, help: module.path, trailing: Self.submoduleBadge(module))
                        .contextMenu { SubmoduleMenu(module: module, window: window, opener: PlacesOpener(app: app, openWindow: openWindow)) }
                        .tag(PlacesActions.submoduleKey(module.path))
                }
            }
        }
    }
}

enum SidebarKey {
    static func view(_ view: RepositoryView) -> String { "view:" + view.rawValue }

    static func parseView(_ key: String) -> RepositoryView? {
        guard key.hasPrefix("view:") else { return nil }
        return RepositoryView(rawValue: String(key.dropFirst("view:".count)))
    }
}

extension SidebarView {
    static func submoduleBadge(_ module: Submodule) -> AnyView? {
        switch module.state {
        case .ahead: AnyView(Badge(text: String(localized: "\(module.ahead) new", bundle: .module), tone: .warning))
        case .uninitialized: AnyView(Badge(text: String(localized: "off", bundle: .module), outline: true))
        default: nil
        }
    }
}

struct BranchTree {
    final class Node {
        var key: String
        var label: String
        var dirs: [String: Node] = [:]
        var leaves: [String] = []

        init(key: String, label: String) {
            self.key = key
            self.label = label
        }
    }

    let root = Node(key: "", label: "")

    init(names: [String]) {
        for name in names {
            let parts = name.split(separator: "/").map(String.init)
            var node = root
            if parts.count > 1 {
                for index in 0..<(parts.count - 1) {
                    let key = parts[0...index].joined(separator: "/") + "/"
                    if let existing = node.dirs[key] {
                        node = existing
                    } else {
                        let created = Node(key: key, label: parts[index])
                        node.dirs[key] = created
                        node = created
                    }
                }
            }
            node.leaves.append(name)
        }
    }
}

struct BranchTreeView: View {
    let node: BranchTree.Node
    let snapshot: RepositorySnapshot
    @Environment(WindowModel.self) private var window

    var body: some View {
        ForEach(node.leaves, id: \.self) { name in
            if let branch = snapshot.branches.first(where: { $0.name == name }) {
                branchRow(branch)
            }
        }
        ForEach(node.dirs.values.sorted { $0.key < $1.key }, id: \.key) { child in
            DisclosureGroup(isExpanded: Binding(get: { window.expandedFolders[child.key] ?? true }, set: { window.expandedFolders[child.key] = $0 })) {
                BranchTreeView(node: child, snapshot: snapshot)
            } label: {
                SidebarItem(icon: "folder", label: child.label, muted: true)
            }
            .selectionDisabled()
        }
    }

    func branchRow(_ branch: Branch) -> some View {
        let current = snapshot.head == .branch(branch.name)
        var trailing: AnyView?
        if branch.ahead > 0 || branch.behind > 0 {
            trailing = AnyView(AheadBehind(ahead: branch.ahead, behind: branch.behind))
        } else if branch.upstreamGone, let upstream = branch.upstream {
            trailing = AnyView(Badge(text: String(localized: "gone", bundle: .module), tone: .warning).help(String(localized: "Its upstream \(upstream) is gone", bundle: .module)))
        }
        if branch.upstream != nil, branch.ahead == 0, !branch.upstreamGone, let glyph = SidebarChecks.glyph(window, branch.tip) {
            trailing = trailing.map { existing in AnyView(HStack(spacing: Vrai.Space.s6) { existing; glyph }) } ?? glyph
        }
        return SidebarItem(
            icon: "arrow.triangle.branch",
            iconColor: Color.Vrai.lane(branch.colorIndex),
            label: branch.name.contains("/") ? (branch.name.split(separator: "/").last.map(String.init) ?? branch.name) : branch.name,
            current: current,
            help: current ? String(localized: "\(branch.name), checked out", bundle: .module) : branch.name,
            trailing: trailing
        )
        .simultaneousGesture(TapGesture(count: 2).onEnded { window.sync.switchTo(branch.name) })
        .contextMenu { BranchMenu(branch: branch, window: window) }
        .modifier(RewriteBranchDrop(branch: branch, current: current, window: window))
        .tag("branch:" + branch.name)
    }
}

struct SidebarSection<Content: View>: View {
    let title: String
    let key: String
    var count: Int?
    var collapsible = true
    var defaultOpen = true
    var action: (icon: String, label: String)?
    var perform: (@MainActor () -> Void)?
    @ViewBuilder let content: () -> Content
    @Environment(WindowModel.self) private var window
    @State private var hovering = false

    var body: some View {
        if collapsible {
            Section(isExpanded: Binding(get: { window.expandedSections[key] ?? defaultOpen }, set: { window.expandedSections[key] = $0 })) {
                content()
            } header: {
                header
            }
        } else {
            Section {
                content()
            } header: {
                header
            }
        }
    }

    var header: some View {
        HStack(spacing: Vrai.Space.s6) {
            Text(title)
                .lineLimit(1)
            if let count {
                Text(String(count))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if let action, let perform {
                Button(action: perform) {
                    Image(systemName: action.icon)
                }
                .buttonStyle(.borderless)
                .help(action.label)
                .accessibilityLabel(action.label)
                .opacity(hovering ? 1 : 0)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("sidebar-section-" + key)
        .id(SidebarAnchor(key: key))
    }
}

struct SidebarAnchor: Hashable {
    static let revealed = ["worktrees", "submodules"]
    let key: String
}

@MainActor
enum SidebarChecks {
    static func glyph(_ window: WindowModel, _ tip: OID) -> AnyView? {
        guard window.preferences.checks, let state = window.checks.state(of: tip) else { return nil }
        return AnyView(ChecksGlyph(state: state).help(ChecksCopy.state(state)))
    }
}

struct SidebarItem: View {
    let icon: String
    var iconColor: Color?
    let label: String
    var detail: String?
    var count: Int?
    var tone: Tone?
    var current = false
    var muted = false
    var help: String?
    var trailing: AnyView?
    @Environment(\.backgroundProminence) private var prominence
    @Environment(\.appearsActive) private var active

    init(icon: String, iconColor: Color? = nil, label: String, detail: String? = nil, count: Int? = nil, tone: Tone? = nil, current: Bool = false, muted: Bool = false, help: String? = nil, trailing: AnyView? = nil) {
        self.icon = icon
        self.iconColor = iconColor
        self.label = label
        self.detail = detail
        self.count = count
        self.tone = tone
        self.current = current
        self.muted = muted
        self.help = help
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: Vrai.Space.s6) {
            Label {
                Text(label)
                    .fontWeight(current ? .semibold : nil)
                    .foregroundStyle(muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
            } icon: {
                if prominence == .increased {
                    Image(systemName: icon)
                } else if let color = tone?.color ?? iconColor {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                } else {
                    Image(systemName: icon)
                        .foregroundStyle(active ? AnyShapeStyle(Color.Vrai.accent) : AnyShapeStyle(.secondary))
                }
            }
            Spacer(minLength: 0)
            if let detail {
                Text(detail)
                    .font(Font.Vrai.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: Vrai.Size.sidebar * 0.4, alignment: .trailing)
                    .fixedSize(horizontal: true, vertical: false)
            }
            if let trailing { trailing }
        }
        .badge(count ?? 0)
        .help(help ?? label)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(Text(verbatim: count.map { $0 == 0 ? "" : String($0) } ?? ""))
    }
}

struct RepositorySwitcher: View {
    @Environment(WindowModel.self) private var window

    var body: some View {
        Button {
            window.toggleSwitcher()
        } label: {
            HStack(spacing: Vrai.Space.s8) {
                RoundedRectangle(cornerRadius: Vrai.Radius.sm, style: .continuous)
                    .fill(Color.Vrai.lane(0))
                    .frame(width: Vrai.Space.s24, height: Vrai.Space.s24)
                    .overlay {
                        Text(String(window.repositoryName.prefix(1)).uppercased())
                            .font(Font.Vrai.headline)
                            .foregroundStyle(Color.Vrai.onLane)
                    }
                VStack(alignment: .leading, spacing: 0) {
                    Text(window.repositoryName)
                        .font(Font.Vrai.headline)
                        .foregroundStyle(Color.Vrai.text)
                        .lineLimit(1)
                    Text(PathText.abbreviated(window.reference.path))
                        .font(Font.Vrai.caption)
                        .foregroundStyle(Color.Vrai.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Symbol("chevron.up.chevron.down", font: Font.Vrai.caption)
                    .foregroundStyle(Color.Vrai.textTertiary)
            }
            .padding(.horizontal, Vrai.Space.s6)
            .padding(.vertical, Vrai.Space.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: Vrai.Radius.md, selected: window.switcher.open, selectedFill: Color.Vrai.fillActive, hoverFill: Color.Vrai.fillHover)
        .help(window.reference.path)
        .accessibilityLabel(window.repositoryName)
        .accessibilityHint(Text("Switch repository", bundle: .module))
        .accessibilityIdentifier("sidebar-repository")
    }
}
