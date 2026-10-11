import SwiftUI
import VraiCore
import VraiGit

struct RefsView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(\.expert) private var expert
    @Environment(\.widthClass) private var widthClass
    @State private var refs: PlacesLoad<[RefEntry]> = .loading
    @State private var attempt = 0
    @State private var query = ""

    struct LoadKey: Hashable {
        var head: OID?
        var branch: String?
        var tips: [OID]
        var tags: Int
        var remotes: Int
        var stashes: Int
        var attempt: Int
    }

    struct Group: Identifiable {
        var id: String
        var title: String
        var note: String?
        var refs: [RefEntry]
    }

    var body: some View {
        ChangesFittedFrame {
            VStack(alignment: .leading, spacing: 0) {
                header
                switch refs {
                case .loading:
                    Spinner().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let error):
                    PlacesLoadFailed(title: String(localized: "The refs didn't load", bundle: .module), error: error) { attempt += 1 }
                case .loaded(let entries):
                    table(Self.groups(filtered(entries)))
                }
            }
        }
        .background(Color.Vrai.bg)
        .task(id: key) { await load() }
        .accessibilityIdentifier("refs-view")
    }

    var key: LoadKey {
        let snapshot = store.snapshot
        return LoadKey(head: snapshot?.headOID, branch: snapshot?.head.branchName, tips: (snapshot?.branches.map(\.tip) ?? []) + (snapshot?.remoteBranches.map(\.tip) ?? []), tags: snapshot?.tags.count ?? 0, remotes: snapshot?.remotes.count ?? 0, stashes: snapshot?.stashes.count ?? 0, attempt: attempt)
    }

    func load() async {
        do {
            refs = .loaded(try await store.allRefs())
        } catch let error as GitError {
            refs = .failed(error)
        } catch {
            refs = .failed(GitError(.unknown(exit: -1, stderr: String(describing: error))))
        }
    }

    func filtered(_ entries: [RefEntry]) -> [RefEntry] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return entries }
        return entries.filter { $0.name.lowercased().contains(text) || $0.target?.rawValue.hasPrefix(text) == true }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: Vrai.Space.s6) {
            HStack(spacing: Vrai.Space.s12) {
                Text("Refs", bundle: .module)
                    .font(Font.Vrai.title2)
                    .foregroundStyle(Color.Vrai.text)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Vrai.Space.s8)
                if widthClass > .compact {
                    SearchField(text: $query, placeholder: String(localized: "Filter refs", bundle: .module))
                        .frame(maxWidth: Vrai.Size.field - Vrai.Space.s64)
                }
                VraiButton(title: "for-each-ref", icon: "terminal", size: .small) {
                    window.console.open = true
                    let store = self.store
                    Task { _ = try? await store.listRefsInConsole() }
                }
                .help(PlacesCommands.listRefs.display)
                .accessibilityIdentifier("refs-console")
            }
            Text("Every name git keeps for a commit. Branches, remote branches and tags have their own sections in the sidebar; this is all of them, raw.", bundle: .module)
                .font(Font.Vrai.callout)
                .foregroundStyle(Color.Vrai.textSecondary)
                .lineLimit(widthClass == .compact ? 3 : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Vrai.Space.s16)
        .padding(.horizontal, Vrai.Space.s24)
        .padding(.bottom, Vrai.Space.s12)
    }

    func table(_ groups: [Group]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Vrai.Space.s16, pinnedViews: []) {
                if groups.isEmpty {
                    Text("No refs match.", bundle: .module)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textTertiary)
                        .padding(.vertical, Vrai.Space.s12)
                }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: Vrai.Space.s6) {
                        HStack(spacing: Vrai.Space.s6) {
                            Text(group.title)
                                .font(Font.Vrai.codeSmall)
                                .foregroundStyle(Color.Vrai.textSecondary)
                            Text(String(group.refs.count))
                                .font(Font.Vrai.caption)
                                .monospacedDigit()
                                .foregroundStyle(Color.Vrai.textTertiary)
                            if let note = group.note {
                                Text(note)
                                    .font(Font.Vrai.caption)
                                    .foregroundStyle(Color.Vrai.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isHeader)
                        VStack(spacing: 0) {
                            RefTableHead()
                            ForEach(group.refs) { entry in
                                RefTableRow(entry: entry)
                                    .contextMenu { RefMenu(entry: entry, window: window) }
                            }
                        }
                        .background(Color.Vrai.bg, in: RoundedRectangle(cornerRadius: Vrai.Radius.lg, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Vrai.Radius.lg, style: .continuous).strokeBorder(Color.Vrai.separator, lineWidth: Metrics.hairline))
                        .clipShape(RoundedRectangle(cornerRadius: Vrai.Radius.lg, style: .continuous))
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("refs-group-" + group.id)
                }
            }
            .padding(.horizontal, Vrai.Space.s24)
            .padding(.bottom, Vrai.Space.s24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    static func groups(_ entries: [RefEntry]) -> [Group] {
        var order: [String] = []
        var buckets: [String: [RefEntry]] = [:]
        for entry in entries {
            let key = entry.namespace.isEmpty ? "" : entry.namespace
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(entry)
        }
        let preferred = ["", "refs/heads", "refs/remotes", "refs/tags", "refs/stash", "refs/notes", "refs/replace", "refs/bisect", "refs/vrai"]
        let sorted = order.sorted { a, b in
            let ia = preferred.firstIndex(of: a) ?? preferred.count
            let ib = preferred.firstIndex(of: b) ?? preferred.count
            return ia != ib ? ia < ib : a < b
        }
        return sorted.map { key in
            Group(id: key.isEmpty ? "root" : key, title: key.isEmpty ? String(localized: "HEAD and pseudo refs", bundle: .module) : key, note: note(for: key), refs: buckets[key] ?? [])
        }
    }

    static func note(for namespace: String) -> String? {
        switch namespace {
        case "refs/replace": String(localized: "Replacements: git shows the target in place of the original object.", bundle: .module)
        case "refs/vrai": String(localized: "Copies Vrai keeps for Undo history.", bundle: .module)
        case "refs/bisect": String(localized: "Marks from the bisect in progress.", bundle: .module)
        default: nil
        }
    }

    static func kindLabel(_ kind: RefEntry.Kind) -> String {
        switch kind {
        case .symbolic: String(localized: "symbolic", bundle: .module)
        case .pseudo: String(localized: "pseudo", bundle: .module)
        case .branch: String(localized: "branch", bundle: .module)
        case .remote: String(localized: "remote", bundle: .module)
        case .tag: String(localized: "tag", bundle: .module)
        case .annotatedTag: String(localized: "annotated tag", bundle: .module)
        case .stash: String(localized: "stash", bundle: .module)
        case .notes: String(localized: "notes", bundle: .module)
        case .replace: String(localized: "replacement", bundle: .module)
        case .undo: String(localized: "undo copy", bundle: .module)
        case .bisect: String(localized: "bisect", bundle: .module)
        case .other: String(localized: "other", bundle: .module)
        }
    }
}

enum RefColumns {
    static let target = Vrai.Size.colHash + Vrai.Space.s24
    static let kind = Vrai.Size.colDate + Vrai.Space.s16
}

struct RefTableHead: View {
    @Environment(\.widthClass) private var widthClass

    var body: some View {
        HStack(spacing: Vrai.Space.s12) {
            Text("Ref", bundle: .module).frame(maxWidth: .infinity, alignment: .leading)
            Text("Points at", bundle: .module).frame(width: RefColumns.target, alignment: .leading)
            if widthClass > .compact {
                Text("Kind", bundle: .module).frame(width: RefColumns.kind, alignment: .leading)
            }
        }
        .font(Font.Vrai.captionStrong)
        .foregroundStyle(Color.Vrai.textTertiary)
        .lineLimit(1)
        .padding(.horizontal, Vrai.Space.s12)
        .frame(height: Vrai.Space.s24)
        .background(Color.Vrai.bgSubtle)
        .accessibilityHidden(true)
    }
}

struct RefTableRow: View {
    let entry: RefEntry
    @Environment(\.expert) private var expert
    @Environment(\.widthClass) private var widthClass

    var body: some View {
        HStack(spacing: Vrai.Space.s12) {
            Text(entry.name)
                .font(Font.Vrai.codeSmall)
                .foregroundStyle(Color.Vrai.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Text(target)
                .font(Font.Vrai.codeSmall)
                .foregroundStyle(Color.Vrai.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: RefColumns.target, alignment: .leading)
                .help(entry.symbolicTarget ?? entry.target?.rawValue ?? "")
            if widthClass > .compact {
                Text(RefsView.kindLabel(entry.kind))
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .lineLimit(1)
                    .frame(width: RefColumns.kind, alignment: .leading)
            }
        }
        .padding(.horizontal, Vrai.Space.s12)
        .padding(.vertical, Vrai.Space.s6)
        .frame(minHeight: Vrai.Size.row)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.Vrai.separator).frame(height: Metrics.hairline)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.name + ", " + target + ", " + RefsView.kindLabel(entry.kind))
        .accessibilityIdentifier("ref-" + entry.name)
    }

    var target: String {
        if let symbolic = entry.symbolicTarget { return "\u{2192} " + symbolic }
        return entry.target?.short(expert: expert) ?? ""
    }
}

struct RefMenu: View {
    let entry: RefEntry
    let window: WindowModel

    var body: some View {
        MenuItem(title: String(localized: "Copy ref name", bundle: .module), icon: "doc.on.doc", enabled: true) {
            window.copy(entry.name)
        }
        MenuItem(title: String(localized: "Copy hash", bundle: .module), icon: "doc.on.doc", enabled: entry.target != nil) {
            if let target = entry.target { window.copy(target.rawValue, label: String(localized: "full hash", bundle: .module)) }
        }
        MenuItem(title: String(localized: "Show in history", bundle: .module), icon: "clock.arrow.circlepath", enabled: entry.commit != nil) {
            if let commit = entry.commit { PlacesActions.showInHistory(window, id: commit) }
        }
        if entry.kind == .replace {
            Divider()
            MenuItem(title: String(localized: "Remove replacement\u{2026}", bundle: .module), icon: "trash", enabled: true, destructive: true) {
                PlacesActions.confirmRemoveReplacement(window, entry: entry)
            }
        }
    }
}
