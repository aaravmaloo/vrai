import SwiftUI
import VraiCore
import VraiGit

struct ReflogView: View {
    enum Tab: Hashable {
        case reflog
        case undo
    }

    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(\.vraiNow) private var now
    @Environment(\.expert) private var expert
    @State private var tab: Tab = .reflog
    @State private var ref = "HEAD"
    @State private var selected = 0
    @State private var showDetail = false
    @State private var entries: PlacesLoad<[ReflogEntry]> = .loading
    @State private var undo: [UndoEntry]?
    @State private var attempt = 0

    struct LoadKey: Hashable {
        var ref: String
        var head: OID?
        var branch: String?
        var tips: [OID]
        var stashes: Int
        var attempt: Int
    }

    var body: some View {
        PlacesPane(showDetail: showDetail, backLabel: String(localized: "Reflog", bundle: .module), back: { showDetail = false }) {
            list
        } detail: {
            detail
        }
        .task(id: key) { await load() }
        .task(id: UndoKey(head: store.snapshot?.headOID, stashes: store.snapshot?.stashes.count ?? 0, tab: tab)) { await loadUndo() }
        .accessibilityIdentifier("reflog-view")
    }

    struct UndoKey: Hashable {
        var head: OID?
        var stashes: Int
        var tab: Tab
    }

    var key: LoadKey {
        let snapshot = store.snapshot
        return LoadKey(ref: ref, head: snapshot?.headOID, branch: snapshot?.head.branchName, tips: snapshot?.branches.map(\.tip) ?? [], stashes: snapshot?.stashes.count ?? 0, attempt: attempt)
    }

    func load() async {
        do {
            let loaded = try await store.reflog(ref: ref)
            entries = .loaded(loaded)
            if selected >= loaded.count { selected = 0 }
        } catch let error as GitError {
            entries = .failed(error)
        } catch {
            entries = .failed(GitError(.unknown(exit: -1, stderr: String(describing: error))))
        }
    }

    func loadUndo() async {
        guard tab == .undo else { return }
        undo = (try? await store.undoHistory()) ?? []
    }

    var refName: String {
        ref == "HEAD" ? "HEAD" : ref
    }

    @ViewBuilder var list: some View {
        VStack(spacing: 0) {
            PlacesListHeader(
                title: tab == .reflog ? String(localized: "Reflog", bundle: .module) : String(localized: "Undo history", bundle: .module),
                caption: tab == .reflog ? (ref == "HEAD" ? String(localized: "Every move of HEAD, kept 90 days", bundle: .module) : String(localized: "Every move of \(ref), kept 90 days", bundle: .module)) : String(localized: "What Vrai can put back, kept 14 days", bundle: .module)
            ) {
                if tab == .reflog {
                    IconMenu(icon: "line.3.horizontal.decrease", label: String(localized: "Show the reflog of", bundle: .module), small: true) {
                        Picker(String(localized: "Show the reflog of", bundle: .module), selection: Binding(get: { ref }, set: { ref = $0; selected = 0 })) {
                            Text(verbatim: "HEAD").tag("HEAD")
                            ForEach(store.snapshot?.branches.map(\.name).sorted() ?? [], id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }
            }
            HStack {
                SyncForm.Tabs(selection: $tab, items: [
                    SyncForm.Option(value: Tab.reflog, label: String(localized: "Reflog", bundle: .module)),
                    SyncForm.Option(value: Tab.undo, label: String(localized: "Undo history", bundle: .module))
                ], label: String(localized: "Show", bundle: .module))
            }
            .padding(.horizontal, Vrai.Space.s8)
            .padding(.top, Vrai.Space.s8)
            if tab == .reflog {
                reflogRows
            } else {
                undoRows
            }
        }
    }

    @ViewBuilder var reflogRows: some View {
        switch entries {
        case .loading:
            Spinner().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            PlacesLoadFailed(title: String(localized: "The reflog didn't load", bundle: .module), error: error) { attempt += 1 }
        case .loaded(let items):
            if items.isEmpty {
                Text("No reflog entries yet.", bundle: .module)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .padding(Vrai.Space.s12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                PlacesList(label: String(localized: "Reflog", bundle: .module)) {
                    ForEach(Array(items.enumerated()), id: \.offset) { offset, entry in
                        PlacesRow(
                            title: Self.action(entry),
                            subtitle: entry.id.short(expert: expert) + ", " + RelativeDate.text(entry.date, now: now),
                            selected: offset == min(selected, items.count - 1),
                            identifier: entry.selector,
                            action: {
                                selected = offset
                                showDetail = true
                            },
                            leading: {
                                Text(entry.selector)
                                    .font(Font.Vrai.codeSmall)
                                    .foregroundStyle(Color.Vrai.textTertiary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                                    .frame(width: Vrai.Space.s64 + (ref == "HEAD" ? 0 : Vrai.Space.s40), alignment: .leading)
                            },
                            trailing: { EmptyView() }
                        )
                        .contextMenu { ReflogMenu(entry: entry, window: window) }
                    }
                }
            }
        }
    }

    @ViewBuilder var undoRows: some View {
        if let undo {
            if undo.isEmpty {
                Text("Nothing to undo yet.", bundle: .module)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .padding(Vrai.Space.s12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                PlacesList(label: String(localized: "Undo history", bundle: .module)) {
                    ForEach(undo) { entry in
                        UndoHistoryRow(entry: entry, now: now) {
                            window.restoreUndo(entry)
                        }
                    }
                }
            }
        } else {
            Spinner().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder var detail: some View {
        if tab == .undo {
            PlacesEmpty(icon: "arrow.uturn.backward", title: String(localized: "Undo history", bundle: .module), message: String(localized: "Discards, hard resets, deleted branches and dropped stashes land here first. Restore puts them back exactly as they were.", bundle: .module), small: true)
        } else if let items = entries.value, !items.isEmpty {
            let index = min(selected, items.count - 1)
            ReflogDetail(entry: items[index])
                .id(items[index].selector + items[index].id.rawValue)
        } else if case .loading = entries {
            Spinner().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PlacesEmpty(icon: "clock", title: String(localized: "No reflog entries", bundle: .module), small: true)
        }
    }

    static func action(_ entry: ReflogEntry) -> String {
        let text = entry.message.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? String(localized: "(no message)", bundle: .module) : text
    }
}

struct ReflogDetail: View {
    let entry: ReflogEntry
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(\.vraiNow) private var now
    @Environment(\.expert) private var expert
    @State private var commit: Commit?
    @State private var branches: [String]?
    @State private var missing = false

    var body: some View {
        let head = window.headName
        let isHead = entry.id == store.snapshot?.headOID
        PlacesDetail(identifier: "reflog-detail") {
            VStack(alignment: .leading, spacing: Vrai.Space.s6) {
                PlacesTitle(title: entry.selector, mono: false) {
                    HashButton(id: entry.id, length: 10)
                }
                Text(ReflogView.action(entry))
                    .font(Font.Vrai.body)
                    .foregroundStyle(Color.Vrai.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            KeyValueGrid {
                KeyValueRow(key: String(localized: "When", bundle: .module)) {
                    Text(InspectorView.fullDate(entry.date))
                        .help(RelativeDate.text(entry.date, now: now))
                }
                KeyValueRow(key: String(localized: "Commit", bundle: .module)) {
                    if let commit {
                        Text(commit.subject)
                            .foregroundStyle(Color.Vrai.text)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if missing {
                        Text("git no longer has this commit.", bundle: .module)
                            .foregroundStyle(Color.Vrai.textTertiary)
                    } else {
                        Spinner()
                    }
                }
                if let commit {
                    KeyValueRow(key: String(localized: "Author", bundle: .module)) {
                        HStack(spacing: Vrai.Space.s6) {
                            Avatar(name: commit.authorName, size: Vrai.Space.s16)
                            Text(commit.authorName).lineLimit(1)
                        }
                    }
                }
                if let branches {
                    KeyValueRow(key: String(localized: "On", bundle: .module)) {
                        if branches.isEmpty {
                            Text("Not on any branch now. The reflog still keeps it.", bundle: .module)
                                .foregroundStyle(Color.Vrai.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(branches.prefix(4).joined(separator: ", ") + (branches.count > 4 ? String(localized: " and \(branches.count - 4) more", bundle: .module) : ""))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            PlacesActionsRow {
                VraiButton(title: String(localized: "Reset \(head) to here\u{2026}", bundle: .module), icon: "arrow.counterclockwise", variant: .primary) {
                    RewriteActions.openReset(window, target: entry.id, label: entry.selector)
                }
                .disabled(commit == nil || isHead)
                .accessibilityIdentifier("reflog-reset")
                VraiButton(title: String(localized: "New branch here", bundle: .module), icon: "arrow.triangle.branch") {
                    window.sync.newBranch(from: entry.id.rawValue)
                }
                .disabled(commit == nil)
                .accessibilityIdentifier("reflog-branch")
                VraiButton(title: String(localized: "Show in history", bundle: .module), icon: "clock.arrow.circlepath") {
                    PlacesActions.showInHistory(window, id: entry.id)
                }
                .disabled(commit == nil)
                .accessibilityIdentifier("reflog-show")
            }
            RewriteCommandPreview(command: PlacesCommands.restoreReflog(entry.selector))
        }
        .task(id: entry.id) {
            do {
                commit = try await store.commitDetail(id: entry.id).commit
                branches = try? await store.branchesContaining(id: entry.id)
            } catch {
                missing = true
            }
        }
    }
}

struct ReflogMenu: View {
    let entry: ReflogEntry
    let window: WindowModel

    var body: some View {
        MenuItem(title: String(localized: "Reset \(window.headName) to here\u{2026}", bundle: .module), icon: "arrow.counterclockwise", enabled: entry.id != window.store.snapshot?.headOID) {
            RewriteActions.openReset(window, target: entry.id, label: entry.selector)
        }
        MenuItem(title: String(localized: "New branch here\u{2026}", bundle: .module), icon: "arrow.triangle.branch", enabled: true) {
            window.sync.newBranch(from: entry.id.rawValue)
        }
        MenuItem(title: String(localized: "Show in history", bundle: .module), icon: "clock.arrow.circlepath", enabled: true) {
            PlacesActions.showInHistory(window, id: entry.id)
        }
        Divider()
        MenuItem(title: String(localized: "Copy \(entry.selector)", bundle: .module), icon: "doc.on.doc", enabled: true) {
            window.copy(entry.selector)
        }
        AlternateMenuItem(
            primary: MenuItem(title: String(localized: "Copy hash", bundle: .module), icon: "doc.on.doc", enabled: true) { window.copy(entry.id.short(expert: window.preferences.expert)) },
            alternate: MenuItem(title: String(localized: "Copy full hash", bundle: .module), icon: "doc.on.doc", enabled: true) { window.copy(entry.id.rawValue, label: String(localized: "full hash", bundle: .module)) }
        )
    }
}
