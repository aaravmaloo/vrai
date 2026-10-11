import SwiftUI
import VraiCore
import VraiGit

struct WorktreesView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var showDetail = false

    var body: some View {
        let worktrees = store.snapshot?.worktrees ?? []
        let selected = selection(in: worktrees)
        PlacesPane(showDetail: showDetail, backLabel: String(localized: "Worktrees", bundle: .module), back: { showDetail = false }) {
            VStack(spacing: 0) {
                PlacesListHeader(title: String(localized: "Worktrees", bundle: .module), caption: String(localized: "Branches checked out side by side", bundle: .module)) {
                    IconButton(icon: "plus", label: String(localized: "Add worktree", bundle: .module)) {
                        PlacesActions.openAddWorktree(window)
                    }
                    .accessibilityIdentifier("worktree-add")
                }
                PlacesList(label: String(localized: "Worktrees", bundle: .module)) {
                    ForEach(worktrees) { worktree in
                        PlacesRow(
                            icon: "rectangle.on.rectangle",
                            title: Self.title(worktree),
                            subtitle: PathText.abbreviated(worktree.path),
                            selected: worktree.path == selected?.path,
                            identifier: "worktree-row-" + PlacesCopy.name(worktree.path),
                            action: {
                                store.sidebarSelection = PlacesActions.worktreeKey(worktree.path)
                                showDetail = true
                            },
                            trailing: { WorktreePill(worktree: worktree) }
                        )
                        .contextMenu { WorktreeMenu(worktree: worktree, window: window, opener: PlacesOpener(app: app, openWindow: openWindow)) }
                    }
                }
            }
        } detail: {
            if let selected {
                WorktreeDetail(worktree: selected, opener: PlacesOpener(app: app, openWindow: openWindow))
                    .id(selected.path)
            } else {
                PlacesEmpty(icon: "rectangle.on.rectangle", title: String(localized: "No worktree selected", bundle: .module), small: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("worktrees-view")
    }

    func selection(in worktrees: [Worktree]) -> Worktree? {
        if let key = store.sidebarSelection, key.hasPrefix("worktree:") {
            let path = String(key.dropFirst("worktree:".count))
            if let match = worktrees.first(where: { $0.path == path }) { return match }
        }
        return worktrees.first
    }

    static func title(_ worktree: Worktree) -> String {
        let name = PlacesCopy.name(worktree.path)
        return worktree.isMain ? String(localized: "\(name) (main)", bundle: .module) : name
    }
}

struct WorktreePill: View {
    let worktree: Worktree
    @Environment(RepositoryStore.self) private var store
    @Environment(\.expert) private var expert

    var body: some View {
        if let branch = worktree.branch {
            RefPill(model: RefPillModel(kind: .branch, name: branch, lane: store.snapshot?.branches.first { $0.name == branch }?.colorIndex ?? 0))
        } else if let head = worktree.detachedAt ?? worktree.head {
            RefPill(model: RefPillModel(kind: .head, name: head.short(expert: expert)))
        }
    }
}

struct WorktreeDetail: View {
    let worktree: Worktree
    let opener: PlacesOpener
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(\.expert) private var expert
    @State private var counted: Int?
    @State private var checked = false

    struct CountKey: Hashable {
        var worktree: Worktree
        var head: OID?
    }

    var body: some View {
        let name = PlacesCopy.name(worktree.path)
        let missing = worktree.prunable != nil
        PlacesDetail(identifier: "worktree-detail") {
            PlacesTitle(title: name) {
                if missing { Badge(text: String(localized: "Folder is gone", bundle: .module), tone: .danger) }
                if worktree.locked { Badge(text: String(localized: "Locked", bundle: .module), tone: .warning) }
                if worktree.isMain { Badge(text: String(localized: "Main worktree", bundle: .module)) }
            }
            KeyValueGrid {
                KeyValueRow(key: String(localized: "Path", bundle: .module)) {
                    Text(PathText.abbreviated(worktree.path))
                        .font(Font.Vrai.codeSmall)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                KeyValueRow(key: String(localized: "Checked out", bundle: .module)) {
                    if let branch = worktree.branch {
                        HStack { WorktreePill(worktree: worktree) }
                            .accessibilityLabel(branch)
                    } else if let head = worktree.detachedAt ?? worktree.head {
                        Text("\(head.short(expert: expert)) (detached)", bundle: .module)
                            .font(Font.Vrai.codeSmall)
                    } else {
                        Text("Nothing yet", bundle: .module)
                    }
                }
                KeyValueRow(key: String(localized: "Changes", bundle: .module)) {
                    Text(changes)
                }
                if worktree.locked {
                    KeyValueRow(key: String(localized: "Lock reason", bundle: .module)) {
                        Text(worktree.lockReason ?? String(localized: "Locked", bundle: .module))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if missing {
                RewriteCallout(tone: .warning, title: String(localized: "This worktree's folder is gone", bundle: .module), message: String(localized: "git still lists it. Prune removes what git kept about it; its branch stays.", bundle: .module))
            }
            PlacesActionsRow {
                VraiButton(title: String(localized: "Open in new window", bundle: .module), icon: "macwindow", variant: .primary) {
                    opener.open(worktree.path, window: window)
                }
                .disabled(worktree.isMain || missing)
                .accessibilityIdentifier("worktree-open")
                VraiButton(title: String(localized: "Reveal in Finder", bundle: .module), icon: "folder") {
                    PlacesActions.revealToast(window, path: worktree.path)
                }
                .disabled(missing)
                .accessibilityIdentifier("worktree-reveal")
                if !worktree.isMain {
                    PlacesBusyButton(title: worktree.locked ? String(localized: "Unlock", bundle: .module) : String(localized: "Lock", bundle: .module), icon: "lock", busy: store.busy.contains("lockWorktree"), identifier: "worktree-lock") {
                        PlacesActions.setLocked(window, worktree: worktree, locked: !worktree.locked)
                    }
                    if missing, expert {
                        VraiButton(title: String(localized: "Prune", bundle: .module), icon: "trash", variant: .plain) {
                            PlacesActions.prune(window)
                        }
                    } else {
                        PlacesBusyButton(title: String(localized: "Remove\u{2026}", bundle: .module), icon: "trash", variant: .plain, busy: store.busy.contains("removeWorktree"), identifier: "worktree-remove") {
                            PlacesActions.confirmRemoveWorktree(window, worktree: worktree)
                        }
                        .disabled(worktree.locked)
                    }
                }
            }
            if expert {
                RewriteCommandPreview(command: worktree.isMain ? PlacesCommands.listWorktrees : store.lockWorktreeCommand(path: worktree.path, locked: !worktree.locked))
            }
        }
        .task(id: CountKey(worktree: worktree, head: store.snapshot?.headOID)) {
            guard !worktree.isMain, worktree.prunable == nil else { return }
            counted = await store.worktreeChanges(path: worktree.path)
            checked = true
        }
    }

    var changes: String {
        if worktree.prunable != nil { return String(localized: "Unknown", bundle: .module) }
        guard let count = worktree.isMain ? store.snapshot?.working.count : (counted ?? worktree.changes) else {
            return checked ? String(localized: "Unknown", bundle: .module) : String(localized: "Checking\u{2026}", bundle: .module)
        }
        return count > 0 ? n(count, "uncommitted change") : String(localized: "Clean", bundle: .module)
    }
}

struct WorktreeMenu: View {
    let worktree: Worktree
    let window: WindowModel
    let opener: PlacesOpener?

    var body: some View {
        let missing = worktree.prunable != nil
        MenuItem(title: String(localized: "Open in new window", bundle: .module), icon: "macwindow", enabled: !worktree.isMain && !missing && opener != nil) {
            opener?.open(worktree.path, window: window)
        }
        MenuItem(title: String(localized: "Reveal in Finder", bundle: .module), icon: "folder", enabled: !missing) {
            PlacesActions.revealToast(window, path: worktree.path)
        }
        MenuItem(title: String(localized: "Show details", bundle: .module), icon: "info.circle", enabled: true) {
            PlacesActions.showWorktree(window, path: worktree.path)
        }
        if !worktree.isMain {
            Divider()
            MenuItem(title: worktree.locked ? String(localized: "Unlock", bundle: .module) : String(localized: "Lock", bundle: .module), icon: "lock", enabled: true) {
                PlacesActions.setLocked(window, worktree: worktree, locked: !worktree.locked)
            }
            MenuItem(title: String(localized: "Remove\u{2026}", bundle: .module), icon: "trash", enabled: !worktree.locked, destructive: true) {
                PlacesActions.confirmRemoveWorktree(window, worktree: worktree)
            }
        }
        Divider()
        MenuItem(title: String(localized: "Copy path", bundle: .module), icon: "doc.on.doc", enabled: true) {
            window.copy(worktree.path, label: String(localized: "path", bundle: .module))
        }
        if window.preferences.expert {
            MenuItem(title: String(localized: "Prune stale worktrees", bundle: .module), icon: "trash", enabled: true) {
                PlacesActions.prune(window)
            }
        }
    }
}
