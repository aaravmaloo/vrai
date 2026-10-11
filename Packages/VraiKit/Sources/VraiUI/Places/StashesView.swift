import SwiftUI
import VraiCore
import VraiGit

struct StashesView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(\.vraiNow) private var now
    @Environment(\.widthClass) private var widthClass
    @State private var selected = 0
    @State private var showDetail = false

    var body: some View {
        let stashes = store.snapshot?.stashes ?? []
        let working = store.snapshot?.working.count ?? 0
        if stashes.isEmpty {
            EmptyStateView(
                icon: "tray.full",
                title: String(localized: "No stashes", bundle: .module),
                message: String(localized: "Stashing sets your changes aside so you can switch branches with a clean working tree, then bring them back.", bundle: .module)
            ) {
                if working > 0 {
                    VraiButton(title: String(localized: "Stash \(n(working, "change"))", bundle: .module), icon: "tray.and.arrow.down", variant: .primary) {
                        RewriteActions.openStash(window)
                    }
                }
            }
        } else {
            let index = min(selected, stashes.count - 1)
            if widthClass == .compact {
                if showDetail {
                    VStack(spacing: 0) {
                        HStack {
                            Button {
                                showDetail = false
                            } label: {
                                HStack(spacing: Vrai.Space.s4) {
                                    Symbol("chevron.left", font: Font.Vrai.callout)
                                    Text("Stashes", bundle: .module)
                                }
                            }
                            .buttonStyle(VraiButtonStyle(variant: .plain, size: .small))
                            Spacer()
                        }
                        .padding(.horizontal, Vrai.Space.s8)
                        .frame(height: Metrics.paneBarHeight)
                        .hairline(.bottom)
                        StashDetailView(stash: stashes[index])
                    }
                } else {
                    list(stashes, index: index, working: working)
                }
            } else {
                HStack(spacing: 0) {
                    list(stashes, index: index, working: working)
                        .frame(width: widthClass.isNarrow ? Vrai.Size.filelist + Vrai.Space.s8 : Vrai.Size.inspector + Vrai.Space.s40)
                        .hairline(.trailing)
                    StashDetailView(stash: stashes[index])
                        .id(stashes[index].oid)
                }
            }
        }
    }

    func list(_ stashes: [Stash], index: Int, working: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Vrai.Space.s8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Stashes", bundle: .module).font(Font.Vrai.headline)
                    Text(n(stashes.count, "stash", "stashes"))
                        .font(Font.Vrai.caption)
                        .foregroundStyle(Color.Vrai.textSecondary)
                }
                Spacer()
                IconButton(icon: "plus", label: String(localized: "Stash changes", bundle: .module)) {
                    RewriteActions.openStash(window)
                }
                .disabled(working == 0)
            }
            .padding(.vertical, Vrai.Space.s6)
            .padding(.leading, Vrai.Space.s16)
            .padding(.trailing, Vrai.Space.s8)
            .frame(minHeight: Metrics.barHeight)
            .hairline(.bottom)
            ScrollView {
                VStack(spacing: Vrai.Space.s2) {
                    ForEach(Array(stashes.enumerated()), id: \.element.id) { offset, stash in
                        Button {
                            selected = offset
                            showDetail = true
                        } label: {
                            HStack(spacing: Vrai.Space.s10) {
                                Symbol("tray.full", font: Font.Vrai.title3)
                                    .foregroundStyle(Color.Vrai.textTertiary)
                                VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                                    Text(Self.title(stash.message))
                                        .font(Font.Vrai.body)
                                        .foregroundStyle(Color.Vrai.text)
                                        .lineLimit(1)
                                    Text(String(localized: "On \(stash.branch ?? "HEAD"), \(RelativeDate.text(stash.date, now: now))", bundle: .module))
                                        .font(Font.Vrai.caption)
                                        .foregroundStyle(Color.Vrai.textSecondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(stash.selector)
                                    .font(Font.Vrai.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Color.Vrai.textTertiary)
                            }
                            .padding(.horizontal, Vrai.Space.s10)
                            .padding(.vertical, Vrai.Space.s4)
                            .frame(minHeight: Vrai.Size.row + Vrai.Space.s8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .hoverHighlight(radius: Vrai.Radius.sm, selected: offset == index)
                        .contextMenu { StashMenu(stash: stash, window: window) }
                        .accessibilityIdentifier(stash.selector)
                    }
                }
                .padding(Vrai.Space.s6)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Stashes", bundle: .module))
        }
    }

    static func title(_ message: String) -> String {
        guard let match = message.firstMatch(of: /^(?:WIP on|On) [^:]+: (.*)$/) else { return message }
        return String(match.output.1)
    }
}

struct StashDetailView: View {
    let stash: Stash
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(\.vraiNow) private var now
    @State private var detail: StashDetail?
    @State private var failed: GitError?

    var body: some View {
        let busy = store.busy.contains("applyStash") || store.busy.contains("popStash") || store.busy.contains("dropStash")
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Vrai.Space.s6) {
                Text(StashesView.title(stash.message))
                    .font(Font.Vrai.title2)
                    .foregroundStyle(Color.Vrai.text)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Vrai.Space.s12) {
                    Text(stash.selector).font(Font.Vrai.codeSmall)
                    if let base = stash.base {
                        Text("On \(stash.branch ?? "HEAD"), based on \(base.short)", bundle: .module)
                    }
                    Text(RelativeDate.text(stash.date, now: now))
                        .foregroundStyle(Color.Vrai.textTertiary)
                        .help(RelativeDate.full(stash.date))
                    if detail?.untrackedCommit != nil {
                        Badge(text: String(localized: "Includes untracked", bundle: .module))
                    }
                }
                .font(Font.Vrai.callout)
                .foregroundStyle(Color.Vrai.textSecondary)
                .lineLimit(1)
                HStack(spacing: Vrai.Space.s8) {
                    Button {
                        RewriteActions.applyStash(window, index: stash.index, pop: window.optionDown)
                    } label: {
                        HStack(spacing: Vrai.Space.s4) {
                            if store.busy.contains("applyStash") { Spinner() } else { Symbol("tray.and.arrow.up", font: Font.Vrai.callout) }
                            Text("Apply", bundle: .module)
                        }
                    }
                    .buttonStyle(VraiButtonStyle(variant: .primary, size: .small))
                    .accessibilityIdentifier("stash-apply")
                    Button {
                        RewriteActions.applyStash(window, index: stash.index, pop: true)
                    } label: {
                        HStack(spacing: Vrai.Space.s4) {
                            if store.busy.contains("popStash") { Spinner() } else { Symbol("tray.and.arrow.up", font: Font.Vrai.callout) }
                            Text("Pop", bundle: .module)
                        }
                    }
                    .buttonStyle(VraiButtonStyle(variant: .secondary, size: .small))
                    .accessibilityIdentifier("stash-pop")
                    VraiButton(title: String(localized: "New branch", bundle: .module), icon: "arrow.triangle.branch", size: .small) {
                        RewriteActions.openStashBranch(window, index: stash.index)
                    }
                    .accessibilityIdentifier("stash-branch")
                    VraiButton(title: String(localized: "Drop\u{2026}", bundle: .module), icon: "trash", variant: .plain, size: .small) {
                        RewriteActions.confirmDropStash(window, index: stash.index)
                    }
                    .accessibilityIdentifier("stash-drop")
                }
                .disabled(busy)
                .padding(.top, Vrai.Space.s2)
            }
            .padding(.top, Vrai.Space.s12)
            .padding(.horizontal, Vrai.Space.s16)
            .padding(.bottom, Vrai.Space.s10)
            .background(Color.Vrai.bgSubtle)
            .hairline(.bottom)
            if let failed {
                EmptyStateView(icon: "exclamationmark.triangle", title: String(localized: "This stash didn't load", bundle: .module), message: ErrorCopy(failed).message, small: true)
            } else if let detail {
                StashDiffPanel(stash: stash, detail: detail)
            } else {
                Spinner().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: stash.oid) {
            do {
                detail = try await store.stashDetail(index: stash.index)
                failed = nil
            } catch let error as GitError {
                failed = error
            } catch {
                failed = GitError(.unknown(exit: -1, stderr: String(describing: error)))
            }
        }
    }
}

struct StashDiffPanel: View {
    let stash: Stash
    let detail: StashDetail
    @Environment(RepositoryStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(\.widthClass) private var widthClass
    @State private var path: String?
    @State private var patch: FileDiff?
    @State private var loading = true
    @State private var context = RepositoryStore.defaultContext

    var files: [FileEntry] { detail.files.map(FileEntry.init) }

    var body: some View {
        let stacked = widthClass.isNarrow
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            filesPane
                .frame(width: stacked ? nil : (widthClass == .medium ? Metrics.mediumFiles : Vrai.Size.filelist))
                .frame(maxHeight: stacked ? Metrics.narrowFiles : .infinity)
                .fixedSize(horizontal: false, vertical: stacked)
                .hairline(stacked ? .bottom : .trailing)
            diffPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: TaskKey(path: path ?? files.first?.path, context: context)) {
            guard let current = path ?? files.first?.path else { return }
            if path == nil { path = current }
            loading = true
            patch = try? await store.stashDiff(index: stash.index, path: current, detail: detail, context: context)
            loading = false
        }
    }

    struct TaskKey: Hashable {
        var path: String?
        var context: Int
    }

    var filesPane: some View {
        let totals = files.reduce((0, 0)) { ($0.0 + $1.additions, $0.1 + $1.deletions) }
        return VStack(spacing: 0) {
            HStack(spacing: Vrai.Space.s8) {
                Text(String(localized: "\(n(files.count, "file")) changed", bundle: .module))
                    .font(Font.Vrai.captionStrong)
                    .foregroundStyle(Color.Vrai.textSecondary)
                    .lineLimit(1)
                DiffStat(additions: totals.0, deletions: totals.1, bar: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Vrai.Space.s12)
            .frame(height: Metrics.paneBarHeight)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(files) { file in
                        FileRowView(path: file.path, oldPath: file.oldPath, status: file.status, additions: file.additions, deletions: file.deletions, binary: file.binary, selected: file.path == (path ?? files.first?.path))
                            .onTapGesture { select(file.path) }
                            .accessibilityAction { select(file.path) }
                    }
                }
                .padding(.horizontal, Vrai.Space.s4)
                .padding(.bottom, Vrai.Space.s8)
            }
            .accessibilityLabel(Text("Files", bundle: .module))
        }
    }

    func select(_ next: String) {
        guard next != path else { return }
        context = RepositoryStore.defaultContext
        patch = nil
        loading = true
        path = next
    }

    @ViewBuilder var diffPane: some View {
        if let current = path ?? files.first?.path, let file = files.first(where: { $0.path == current }) {
            VStack(spacing: 0) {
                HStack(spacing: Vrai.Space.s8) {
                    PathBar(path: file.path)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()
                    if !widthClass.isNarrow {
                        SegmentedControl(selection: Binding(get: { preferences.diffMode }, set: { preferences.diffMode = $0 }), items: [
                            SegmentItem(value: Preferences.DiffMode.unified, icon: "text.alignleft", label: String(localized: "Unified", bundle: .module)),
                            SegmentItem(value: Preferences.DiffMode.split, icon: "rectangle.split.2x1", label: String(localized: "Side by side", bundle: .module))
                        ])
                    }
                }
                .padding(.leading, Vrai.Space.s12)
                .padding(.trailing, Vrai.Space.s8)
                .frame(height: Metrics.paneBarHeight)
                .hairline(.bottom)
                if let patch, !patch.hunks.isEmpty {
                    DiffView(diff: patch, mode: widthClass.isNarrow ? .unified : preferences.diffMode, wrap: preferences.wrap, whitespace: preferences.whitespace, codeSize: preferences.codeSize) {
                        context += RepositoryStore.contextStep
                    }
                } else if loading {
                    Spinner().frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.Vrai.bg)
                } else {
                    Text(file.binary || patch?.isBinary == true ? String(localized: "Binary file, not shown.", bundle: .module) : String(localized: "No text changes.", bundle: .module))
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.Vrai.bg)
                }
            }
        } else {
            EmptyStateView(icon: "doc.text", title: String(localized: "No file selected", bundle: .module), small: true)
        }
    }
}
