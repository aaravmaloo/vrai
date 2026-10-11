import SwiftUI
import VraiCore
import VraiGit

struct HistoryView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(Preferences.self) private var preferences
    @Environment(\.widthClass) private var widthClass

    var body: some View {
        let showInspector = preferences.inspector && store.selection?.commitID != nil && widthClass == .wide
        HStack(spacing: 0) {
            main
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showInspector {
                InspectorView()
                    .frame(width: Vrai.Size.inspector)
                    .hairline(.leading)
            }
        }
        .background(Color.Vrai.bg)
    }

    @ViewBuilder var main: some View {
        let history = store.history
        let isEmpty = history.phase == .loaded && history.commits.isEmpty && history.wipRow == nil
        if case .failed(let error) = history.phase, history.commits.isEmpty {
            EmptyStateView(icon: "exclamationmark.triangle", title: String(localized: "History didn't load", bundle: .module), message: ErrorCopy(error).message) {
                VraiButton(title: String(localized: "Try again", bundle: .module), icon: "arrow.clockwise", variant: .primary) {
                    Task { await store.reloadHistory() }
                }
            }
        } else if isEmpty, store.wipFiles.isEmpty {
            emptyState
        } else if widthClass == .compact {
            if window.pane == .detail {
                DetailPane()
            } else {
                VStack(spacing: 0) {
                    HistoryBar()
                    CommitList()
                }
            }
        } else {
            VStack(spacing: 0) {
                HistoryBar()
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        CommitList()
                            .frame(height: max(Vrai.Space.s64, geometry.size.height * 0.52))
                        DetailPane()
                            .frame(maxHeight: .infinity)
                            .hairline(.top)
                    }
                }
            }
        }
    }

    var emptyState: some View {
        let name = window.repositoryName
        let dirty = store.snapshot?.working.isEmpty == false
        return EmptyStateView(
            icon: "clock.arrow.circlepath",
            title: String(localized: "No commits yet", bundle: .module),
            message: dirty ? String(localized: "Stage the files in Changes, write a summary and commit. The graph starts there.", bundle: .module) : String(localized: "Add files to \(name) and they appear in Changes.", bundle: .module)
        ) {
            if dirty {
                VraiButton(title: String(localized: "Make the first commit", bundle: .module), icon: "square.and.pencil", variant: .primary) {
                    window.show(.changes)
                }
            }
        }
    }
}

struct HistoryBar: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(\.widthClass) private var widthClass

    var body: some View {
        @Bindable var window = window
        let history = store.history
        HStack(spacing: Vrai.Space.s8) {
            SearchField(text: $window.query, placeholder: String(localized: "Filter by subject, author or hash", bundle: .module), focusRequest: $window.focusFilter)
                .frame(maxWidth: widthClass.isNarrow ? .infinity : Vrai.Size.field)
            if !widthClass.isNarrow {
                SelectMenu(title: scopeTitle, icon: nil) {
                    Picker(selection: Binding(get: { store.scope }, set: { store.setScope($0) })) {
                        Text("All branches", bundle: .module).tag(HistoryScope.all)
                        Text("Current branch", bundle: .module).tag(HistoryScope.current)
                        ForEach(otherBranches, id: \.self) { name in
                            Text(name).tag(HistoryScope.ref(name))
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                }
                .help(String(localized: "Branches shown", bundle: .module))
                SelectMenu(title: window.author ?? String(localized: "All authors", bundle: .module), icon: "person.2") {
                    Picker(selection: $window.author) {
                        Text("All authors", bundle: .module).tag(String?.none)
                        ForEach(history.authors, id: \.name) { author in
                            Text(author.name).tag(String?.some(author.name))
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                }
                .help(String(localized: "Author", bundle: .module))
                Spacer(minLength: 0)
                Text(countText)
                    .font(Font.Vrai.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, Vrai.Space.s12)
        .frame(height: Metrics.barHeight)
        .hairline(.bottom)
    }

    var otherBranches: [String] {
        let current = store.snapshot?.head.branchName
        return (store.snapshot?.branches.map(\.name) ?? []).filter { $0 != current }.sorted()
    }

    var scopeTitle: String {
        switch store.scope {
        case .all: String(localized: "All branches", bundle: .module)
        case .current: String(localized: "Current branch", bundle: .module)
        case .ref(let name): name
        }
    }

    var countText: String {
        let history = store.history
        let total = history.totalCount ?? history.commits.count
        let filtering = !window.query.trimmingCharacters(in: .whitespaces).isEmpty || window.author != nil
        guard filtering else { return n(total, "commit") }
        let filter = CommitFilter(query: window.query, author: window.author)
        let shown = history.commits.count { filter.matches($0) }
        return String(localized: "\(shown) of \(n(total, "commit"))", bundle: .module)
    }
}

struct SelectMenu<Content: View>: View {
    let title: String
    let icon: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu(content: content) {
            HStack(spacing: Vrai.Space.s6) {
                if let icon { Symbol(icon, font: Font.Vrai.callout) }
                Text(title).lineLimit(1)
                Symbol("chevron.up.chevron.down", font: Font.Vrai.overline)
                    .foregroundStyle(Color.Vrai.textTertiary)
            }
            .font(Font.Vrai.body)
            .foregroundStyle(Color.Vrai.text)
            .padding(.leading, Vrai.Space.s8)
            .padding(.trailing, Vrai.Space.s4)
            .frame(height: Vrai.Size.controlSm)
            .background(Color.Vrai.surfaceRaised, in: RoundedRectangle(cornerRadius: Vrai.Radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Vrai.Radius.sm, style: .continuous).strokeBorder(Color.Vrai.border, lineWidth: Metrics.hairline))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct CommitFilter {
    let query: String
    let author: String?

    init(query: String, author: String?) {
        self.query = query.trimmingCharacters(in: .whitespaces).lowercased()
        self.author = author
    }

    var isActive: Bool { !query.isEmpty || author != nil }

    func matches(_ commit: Commit) -> Bool {
        if let author, commit.authorName != author { return false }
        guard !query.isEmpty else { return true }
        return commit.subject.lowercased().contains(query) || commit.id.rawValue.hasPrefix(query) || commit.authorName.lowercased().contains(query)
    }
}

struct CommitList: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(Preferences.self) private var preferences
    @Environment(\.widthClass) private var widthClass
    @FocusState private var focused: Bool
    @State private var bisectSkipped: [OID] = []

    var rowHeight: CGFloat {
        switch preferences.density {
        case .compact: Vrai.Size.rowCompact
        case .regular: Vrai.Size.row
        case .comfortable: Vrai.Size.rowComfortable
        }
    }

    var body: some View {
        let history = store.history
        let refs = store.snapshot.map { RefPills.byCommit($0, skipped: bisectSkipped) } ?? [:]
        let columns: CommitColumns = widthClass.isNarrow ? [.date] : .all
        let showHeader = widthClass >= .regular
        let filter = CommitFilter(query: window.query, author: window.author)
        let selection = store.selection
        let lanes = history.lanes
        let height = rowHeight
        let isFocused = focused || window.listFocused
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0, pinnedViews: showHeader ? [.sectionHeaders] : []) {
                    Section {
                        if let wip = history.wipRow {
                            WipRowView(row: wip, lanes: lanes, height: height, files: store.snapshot?.working.count ?? 0, selected: selection == .wip, focused: isFocused, columns: columns)
                                .id(CommitSelection.wip)
                                .onTapGesture { choose(.wip) }
                                .simultaneousGesture(TapGesture(count: 2).onEnded { window.show(.changes) })
                                .contextMenu { WipMenu(window: window) }
                        }
                        ForEach(history.commits) { commit in
                            let index = history.index[commit.id] ?? 0
                            CommitRowView(
                                commit: commit,
                                row: history.rows[index],
                                lanes: lanes,
                                height: height,
                                refs: refs[commit.id] ?? [],
                                selected: selection == .commit(commit.id),
                                focused: isFocused,
                                dim: filter.isActive && !filter.matches(commit),
                                query: filter.query,
                                columns: columns,
                                signature: store.signature(of: commit)
                            )
                            .id(CommitSelection.commit(commit.id))
                            .onTapGesture { choose(.commit(commit.id)) }
                            .simultaneousGesture(TapGesture(count: 2).onEnded { confirmCheckout(commit) })
                            .contextMenu { CommitMenu(id: commit.id, window: window) }
                            .modifier(RewriteCommitDrag(commit: commit))
                            .onAppear {
                                store.requestSignatures(for: [commit.id])
                                if index >= history.commits.count - 200 {
                                    Task { await store.loadMoreHistory() }
                                }
                            }
                        }
                    } header: {
                        if showHeader {
                            HistoryHeader(graphWidth: GraphCell.width(lanes: lanes), columns: columns)
                        }
                    }
                }
                .padding(.horizontal, Vrai.Space.s4)
                .padding(.bottom, Vrai.Space.s8)
            }
            .onChange(of: store.scrollRequest) { _, request in
                guard let request else { return }
                withAnimation(nil) { proxy.scrollTo(request.target, anchor: .center) }
            }
            .onAppear {
                if let request = store.scrollRequest {
                    proxy.scrollTo(request.target, anchor: .center)
                }
            }
            .onChange(of: store.selection) { _, selection in
                guard let selection, focused else { return }
                proxy.scrollTo(selection)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear {
            focused = true
            window.listFocused = true
        }
        .onChange(of: focused) { _, value in window.listFocused = value }
        .onMoveCommand { direction in
            switch direction {
            case .up: move(-1)
            case .down: move(1)
            default: break
            }
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "jk")) { press in
            move(press.characters == "j" ? 1 : -1)
            return .handled
        }
        .onKeyPress(.return) {
            if store.selection == .wip { window.show(.changes) } else if widthClass == .compact { window.pane = .detail }
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Commits", bundle: .module))
        .accessibilityIdentifier("commits")
        .task(id: store.snapshot?.state) { bisectSkipped = await BisectMarks.skipped(store) }
    }

    func choose(_ selection: CommitSelection) {
        focused = true
        window.select(selection)
    }

    func move(_ delta: Int) {
        let history = store.history
        let filter = CommitFilter(query: window.query, author: window.author)
        var order: [CommitSelection] = history.wipRow != nil ? [.wip] : []
        order += history.commits.filter { !filter.isActive || filter.matches($0) }.map { .commit($0.id) }
        guard !order.isEmpty else { return }
        let current = store.selection.flatMap { order.firstIndex(of: $0) }
        let next = max(0, min(order.count - 1, (current ?? (delta > 0 ? -1 : 0)) + delta))
        store.select(order[next])
    }

    func confirmCheckout(_ commit: Commit) {
        window.sync.confirmDetach(commit.id, subject: commit.subject)
    }
}
