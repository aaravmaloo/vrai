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
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        workspace
                        branches
                        remotes
                        tags
                        worktrees
                        submodules
                    }
                    .padding(.horizontal, Vrai.Space.s4)
                    .padding(.bottom, Vrai.Space.s8)
                }
                .scrollIndicators(.automatic)
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

    var historySelected: Bool { store.view == .history && store.sidebarSelection == nil }

    @ViewBuilder var workspace: some View {
        SidebarSection(title: String(localized: "Workspace", bundle: .module), key: "workspace", collapsible: false) {
            SidebarItem(icon: "clock.arrow.circlepath", label: String(localized: "History", bundle: .module), selected: historySelected) {
                store.sidebarSelection = nil
                window.show(.history)
            }
            SidebarItem(icon: "square.and.pencil", label: String(localized: "Changes", bundle: .module), count: snapshot?.working.count, tone: snapshot?.conflicts.isEmpty == false ? .danger : nil, selected: store.view == .changes) {
                window.show(.changes)
            }
            SidebarItem(icon: "tray.full", label: String(localized: "Stashes", bundle: .module), count: snapshot?.stashes.count, selected: store.view == .stashes) {
                window.show(.stashes)
            }
            if preferences.expert {
                SidebarItem(icon: "clock", label: String(localized: "Reflog", bundle: .module), selected: store.view == .reflog) { window.show(.reflog) }
                SidebarItem(icon: "point.3.connected.trianglepath.dotted", label: String(localized: "Refs", bundle: .module), selected: store.view == .refs) { window.show(.refs) }
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
                    SidebarItem(icon: "mappin.and.ellipse", label: String(localized: "HEAD at \(id.short)", bundle: .module), tone: .warning, current: true, selected: store.sidebarSelection == "head", help: String(localized: "Detached HEAD", bundle: .module)) {
                        pick("head", ref: "HEAD")
                    }
                }
                if case .unborn(let name) = snapshot.head {
                    SidebarItem(icon: "arrow.triangle.branch", iconColor: Color.Vrai.lane(0), label: name, detail: String(localized: "no commits yet", bundle: .module), current: true, muted: true)
                }
                BranchTreeView(node: tree.root, depth: 0, snapshot: snapshot, pick: pick)
            }
        }
    }

    @ViewBuilder var remotes: some View {
        if let snapshot, !snapshot.remotes.isEmpty {
            SidebarSection(title: String(localized: "Remotes", bundle: .module), key: "remotes", count: snapshot.remotes.count, action: (icon: "plus", label: String(localized: "Add remote", bundle: .module)), perform: { window.sync.addRemote() }) {
                ForEach(snapshot.remotes) { remote in
                    let showBranches = preferences.showRemotes
                    let open = showBranches && (window.expandedFolders["remote:" + remote.name] ?? false)
                    SidebarItem(icon: "network", label: remote.name, detail: PathText.remoteDetail(remote.fetchURL), expanded: showBranches ? open : nil, help: remote.fetchURL, trailing: SyncSidebar.badge(for: remote, snapshot: snapshot)) {
                        if showBranches { window.expandedFolders["remote:" + remote.name] = !open }
                    }
                    .simultaneousGesture(TapGesture(count: 2).onEnded { window.sync.editRemote(remote.name) })
                    .contextMenu { RemoteMenu(remote: remote, window: window) }
                    if open {
                        ForEach(snapshot.remoteBranches.filter { $0.remote == remote.name }.sorted { $0.name < $1.name }) { branch in
                            SidebarItem(icon: "cloud", iconColor: Color.Vrai.lane(branch.colorIndex), label: branch.name, depth: 1, selected: store.sidebarSelection == "remote:" + branch.fullName, help: branch.fullName) {
                                pick("remote:" + branch.fullName, ref: branch.fullName)
                            }
                            .simultaneousGesture(TapGesture(count: 2).onEnded { window.sync.checkOut(remote: branch) })
                            .contextMenu { RemoteBranchMenu(remote: branch, window: window) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder var tags: some View {
        if let snapshot, !snapshot.tags.isEmpty {
            SidebarSection(title: String(localized: "Tags", bundle: .module), key: "tags", count: snapshot.tags.count, defaultOpen: false, action: (icon: "plus", label: String(localized: "New tag", bundle: .module)), perform: { window.sync.newTag() }) {
                ForEach(snapshot.tags.sorted { $0.name.compare($1.name, options: .numeric) == .orderedDescending }.prefix(500)) { tag in
                    SidebarItem(icon: "tag", label: tag.name, detail: tag.annotated ? nil : String(localized: "lightweight", bundle: .module), selected: store.sidebarSelection == "tag:" + tag.name) {
                        pick("tag:" + tag.name, ref: tag.name)
                    }
                    .contextMenu { TagMenu(tag: tag, window: window) }
                }
            }
        }
    }

    @ViewBuilder var worktrees: some View {
        if let snapshot, snapshot.worktrees.count > 1 {
            SidebarSection(title: String(localized: "Worktrees", bundle: .module), key: "worktrees", count: snapshot.worktrees.count, defaultOpen: false, action: (icon: "plus", label: String(localized: "Add worktree", bundle: .module)), perform: { PlacesActions.openAddWorktree(window) }) {
                ForEach(snapshot.worktrees) { worktree in
                    SidebarItem(icon: "rectangle.on.rectangle", label: URL(filePath: worktree.path).lastPathComponent, detail: worktree.branch ?? String(localized: "detached", bundle: .module), selected: PlacesActions.selectedWorktree(store) == worktree.path, help: worktree.path, trailing: worktree.locked ? AnyView(Symbol("lock", font: Font.Vrai.callout).foregroundStyle(Color.Vrai.textTertiary)) : nil) { PlacesActions.showWorktree(window, path: worktree.path) }
                        .contextMenu { WorktreeMenu(worktree: worktree, window: window, opener: PlacesOpener(app: app, openWindow: openWindow)) }
                }
            }
        }
    }

    @ViewBuilder var submodules: some View {
        if let snapshot, !snapshot.submodules.isEmpty {
            SidebarSection(title: String(localized: "Submodules", bundle: .module), key: "submodules", count: snapshot.submodules.count, defaultOpen: false, action: (icon: "plus", label: String(localized: "Add submodule", bundle: .module)), perform: { PlacesActions.openAddSubmodule(window) }) {
                ForEach(snapshot.submodules) { module in
                    SidebarItem(icon: "shippingbox", label: URL(filePath: module.path).lastPathComponent, selected: PlacesActions.selectedSubmodule(store) == module.path, help: module.path, trailing: Self.submoduleBadge(module)) { PlacesActions.showSubmodule(window, path: module.path) }
                        .contextMenu { SubmoduleMenu(module: module, window: window, opener: PlacesOpener(app: app, openWindow: openWindow)) }
                }
            }
        }
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
    let depth: Int
    let snapshot: RepositorySnapshot
    let pick: (String, String) -> Void
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window

    var body: some View {
        ForEach(node.leaves, id: \.self) { name in
            if let branch = snapshot.branches.first(where: { $0.name == name }) {
                branchRow(branch)
            }
        }
        ForEach(node.dirs.values.sorted { $0.key < $1.key }, id: \.key) { child in
            let open = window.expandedFolders[child.key] ?? true
            SidebarItem(icon: "folder", label: child.label, depth: depth, expanded: open, muted: true) {
                window.expandedFolders[child.key] = !open
            }
            if open {
                BranchTreeView(node: child, depth: depth + 1, snapshot: snapshot, pick: pick)
            }
        }
    }

    func branchRow(_ branch: Branch) -> some View {
        let current = snapshot.head == .branch(branch.name)
        let key = "branch:" + branch.name
        var trailing: AnyView?
        if branch.ahead > 0 || branch.behind > 0 {
            trailing = AnyView(AheadBehind(ahead: branch.ahead, behind: branch.behind))
        } else if branch.upstreamGone, let upstream = branch.upstream {
            trailing = AnyView(Badge(text: String(localized: "gone", bundle: .module), tone: .warning).help(String(localized: "Its upstream \(upstream) is gone", bundle: .module)))
        }
        return SidebarItem(
            icon: "arrow.triangle.branch",
            iconColor: Color.Vrai.lane(branch.colorIndex),
            label: depth > 0 ? (branch.name.split(separator: "/").last.map(String.init) ?? branch.name) : branch.name,
            depth: depth,
            current: current,
            selected: store.sidebarSelection == key,
            help: current ? String(localized: "\(branch.name), checked out", bundle: .module) : branch.name,
            trailing: trailing
        ) {
            pick(key, branch.name)
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { window.sync.switchTo(branch.name) })
        .contextMenu { BranchMenu(branch: branch, window: window) }
        .modifier(RewriteBranchDrop(branch: branch, current: current, window: window))
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
        let open = !collapsible || (window.expandedSections[key] ?? defaultOpen)
        VStack(alignment: .leading, spacing: Metrics.hairline) {
            HStack(spacing: Vrai.Space.s4) {
                Button {
                    if collapsible { window.expandedSections[key] = !open }
                } label: {
                    HStack(spacing: Vrai.Space.s6) {
                        Text(title)
                            .font(Font.Vrai.captionStrong)
                            .lineLimit(1)
                        if let count {
                            Text(String(count))
                                .font(Font.Vrai.caption)
                                .monospacedDigit()
                                .opacity(0.8)
                        }
                        if collapsible {
                            Symbol("chevron.right", font: Font.Vrai.caption)
                                .rotationEffect(.degrees(open ? 90 : 0))
                                .opacity(!open || hovering ? 1 : 0)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(collapsible ? (open ? Text("Expanded", bundle: .module) : Text("Collapsed", bundle: .module)) : Text(verbatim: ""))
                .accessibilityIdentifier("sidebar-section-" + key)
                if let action {
                    IconButton(icon: action.icon, label: action.label, small: true) { perform?() }
                        .disabled(perform == nil)
                        .opacity(hovering ? 1 : 0)
                }
            }
            .padding(.leading, Vrai.Space.s10)
            .padding(.trailing, Vrai.Space.s6)
            .frame(height: Vrai.Space.s24)
            .onHover { hovering = $0 }
            if open {
                content()
            }
        }
        .padding(.top, Vrai.Space.s10)
        .id(SidebarAnchor(key: key))
    }
}

struct SidebarAnchor: Hashable {
    static let revealed = ["worktrees", "submodules"]
    let key: String
}

struct SidebarItem: View {
    let icon: String
    var iconColor: Color?
    let label: String
    var detail: String?
    var count: Int?
    var depth = 0
    var expanded: Bool?
    var tone: Tone?
    var current = false
    var muted = false
    var selected = false
    var help: String?
    var trailing: AnyView?
    var action: () -> Void = {}
    @Environment(Preferences.self) private var preferences

    init(icon: String, iconColor: Color? = nil, label: String, detail: String? = nil, count: Int? = nil, depth: Int = 0, expanded: Bool? = nil, tone: Tone? = nil, current: Bool = false, muted: Bool = false, selected: Bool = false, help: String? = nil, trailing: AnyView? = nil, action: @escaping () -> Void = {}) {
        self.icon = icon
        self.iconColor = iconColor
        self.label = label
        self.detail = detail
        self.count = count
        self.depth = depth
        self.expanded = expanded
        self.tone = tone
        self.current = current
        self.muted = muted
        self.selected = selected
        self.help = help
        self.trailing = trailing
        self.action = action
    }

    var rowHeight: CGFloat {
        switch preferences.density {
        case .compact: Vrai.Size.rowCompact
        case .regular: Vrai.Size.row
        case .comfortable: Vrai.Size.rowComfortable
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Vrai.Space.s6) {
                ZStack {
                    if let expanded {
                        Symbol("chevron.right", font: Font.Vrai.caption)
                            .foregroundStyle(Color.Vrai.textTertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                }
                .frame(width: Vrai.Space.s12)
                Symbol(icon, font: Font.Vrai.title3)
                    .foregroundStyle(tone?.color ?? iconColor ?? Color.Vrai.accentText)
                    .frame(width: Vrai.Space.s20)
                Text(label)
                    .font(current ? Font.Vrai.headline : Font.Vrai.body)
                    .foregroundStyle(muted ? Color.Vrai.textTertiary : Color.Vrai.text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let detail {
                    Text(detail)
                        .font(Font.Vrai.caption)
                        .foregroundStyle(Color.Vrai.textTertiary)
                        .lineLimit(1)
                        .frame(maxWidth: Vrai.Size.sidebar * 0.4, alignment: .trailing)
                        .fixedSize(horizontal: true, vertical: false)
                }
                if let trailing { trailing }
                if let count, count != 0 {
                    Text(String(count))
                        .font(Font.Vrai.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.Vrai.textTertiary)
                }
            }
            .padding(.leading, Vrai.Space.s2 + CGFloat(depth) * Vrai.Space.s16)
            .padding(.trailing, Vrai.Space.s8)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: Vrai.Radius.md, selected: selected, selectedFill: Color.Vrai.accentSoftStrong)
        .help(help ?? label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(expanded.map { $0 ? Text("Expanded", bundle: .module) : Text("Collapsed", bundle: .module) } ?? Text(verbatim: count.map { $0 == 0 ? "" : String($0) } ?? ""))
    }
}

struct RepositorySwitcher: View {
    @Environment(WindowModel.self) private var window
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu {
            Section(String(localized: "Recent repositories", bundle: .module)) {
                ForEach(app.recents) { recent in
                    Button {
                        openWindow(value: app.request(RepositoryReference(path: recent.path)))
                    } label: {
                        Label(recent.name, systemImage: "folder")
                    }
                }
            }
            Divider()
            Button {
                AppSheets.present(.open, window: window, app: app, openWindow: openWindow)
            } label: {
                Label(String(localized: "Open\u{2026}", bundle: .module), systemImage: "folder")
            }
            Button {
                AppSheets.present(.clone(url: nil), window: window, app: app, openWindow: openWindow)
            } label: { Label(String(localized: "Clone\u{2026}", bundle: .module), systemImage: "square.and.arrow.down") }
            Button {
                AppSheets.present(.newRepository(folder: nil), window: window, app: app, openWindow: openWindow)
            } label: { Label(String(localized: "New repository\u{2026}", bundle: .module), systemImage: "folder.badge.plus") }
            Divider()
            Button {
                openWindow(id: "welcome")
            } label: {
                Label(String(localized: "Welcome window", bundle: .module), systemImage: "macwindow")
            }
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
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .hoverHighlight(radius: Vrai.Radius.md, hoverFill: Color.Vrai.fillHover)
        .help(window.reference.path)
    }
}
