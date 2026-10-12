import SwiftUI
import VraiCore
import VraiGit

struct ChangesDiffPane: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(Preferences.self) private var preferences
    @Environment(\.widthClass) private var widthClass
    @State private var paneWidth = ChangesMetrics.splitMinimum

    var roomy: Bool { !widthClass.isNarrow && paneWidth >= ChangesMetrics.splitMinimum }

    var body: some View {
        let changes = window.changes
        Group {
            if changes.isMultiple {
                VStack(spacing: 0) {
                    if widthClass.isNarrow { backBar }
                    selectionSummary
                }
            } else if let pick = changes.pick {
                if pick.conflict {
                    VStack(spacing: 0) {
                        if widthClass.isNarrow { backBar }
                        ConflictsPane(path: pick.path)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else if let file = store.snapshot?.working.first(where: { $0.path == pick.path }) {
                    VStack(spacing: 0) {
                        bar(file: file, pick: pick)
                        notes(file: file, pick: pick)
                        content(pick: pick)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    Spinner().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                EmptyStateView(icon: "doc.text", title: String(localized: "Nothing selected", bundle: .module), message: String(localized: "Pick a file to see its diff.", bundle: .module), small: true)
            }
        }
        .background(Color.Vrai.bg)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { paneWidth = $0 }
    }

    var selectionSummary: some View {
        let paths = window.selectedPaths()
        let staging = window.changes.selected.contains { !$0.conflict && $0.side == .unstaged }
        return EmptyStateView(icon: "doc.on.doc", title: String(localized: "\(n(paths.count, "file")) selected", bundle: .module), message: String(localized: "Space stages or unstages them. Delete discards them.", bundle: .module), small: true) {
            HStack(spacing: Vrai.Space.s8) {
                VraiButton(title: staging ? String(localized: "Stage \(n(paths.count, "file"))", bundle: .module) : String(localized: "Unstage \(n(paths.count, "file"))", bundle: .module), icon: staging ? "plus" : "minus", variant: .primary, size: .small) {
                    window.toggleStage(picks: Array(window.changes.selected))
                }
                .accessibilityIdentifier("changes-selection-stage")
                VraiButton(title: String(localized: "Discard\u{2026}", bundle: .module), icon: "arrow.uturn.backward", variant: .secondary, size: .small) {
                    window.confirmDiscard(paths)
                }
                .disabled(paths.isEmpty)
                .accessibilityIdentifier("changes-selection-discard")
            }
        }
        .accessibilityIdentifier("changes-selection-summary")
    }

    var backBar: some View {
        HStack(spacing: Vrai.Space.s8) {
            VraiButton(title: String(localized: "Changes", bundle: .module), icon: "chevron.left", variant: .plain, size: .small) {
                window.changes.narrowDetail = false
            }
            .accessibilityIdentifier("changes-back")
            Spacer(minLength: 0)
        }
        .padding(.leading, Vrai.Space.s12)
        .padding(.trailing, Vrai.Space.s8)
        .frame(height: Metrics.paneBarHeight)
        .hairline(.bottom)
    }

    func bar(file: WorkingFile, pick: ChangesPick) -> some View {
        let changes = window.changes
        return HStack(spacing: Vrai.Space.s8) {
            if widthClass.isNarrow {
                VraiButton(title: String(localized: "Changes", bundle: .module), icon: "chevron.left", variant: .plain, size: .small) {
                    changes.narrowDetail = false
                }
                .fixedSize()
                .accessibilityIdentifier("changes-back")
            }
            PathBar(path: file.path)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                .clipped()
            if let counts = changes.counts {
                SegmentedControl(selection: Binding(get: { pick.side }, set: { side in
                    changes.select(ChangesPick(path: pick.path, side: side), store: store, narrow: false)
                }), items: [
                    SegmentItem(value: LineSelection.Side.unstaged, title: String(localized: "Unstaged \(counts.unstaged)", bundle: .module), label: String(localized: "Unstaged changes", bundle: .module)),
                    SegmentItem(value: LineSelection.Side.staged, title: String(localized: "Staged \(counts.staged)", bundle: .module), label: String(localized: "Staged changes", bundle: .module))
                ])
                .accessibilityLabel(Text("Which changes", bundle: .module))
            }
            if roomy {
                SegmentedControl(selection: Binding(get: { preferences.diffMode }, set: { preferences.diffMode = $0 }), items: [
                    SegmentItem(value: Preferences.DiffMode.unified, icon: "text.alignleft", label: String(localized: "Unified", bundle: .module)),
                    SegmentItem(value: Preferences.DiffMode.split, icon: "rectangle.split.2x1", label: String(localized: "Side by side", bundle: .module))
                ])
            }
            IconMenu(icon: "ellipsis.circle", label: String(localized: "File actions", bundle: .module)) {
                WorkingFileMenu(file: file, window: window)
            }
        }
        .padding(.leading, Vrai.Space.s12)
        .padding(.trailing, Vrai.Space.s8)
        .frame(height: Metrics.paneBarHeight)
        .hairline(.bottom)
    }

    @ViewBuilder func notes(file: WorkingFile, pick: ChangesPick) -> some View {
        let changes = window.changes
        let status = ChangeGroups.statusLetter(file, side: pick.side)
        if file.status == .untracked {
            DiffNote(icon: "info.circle", text: String(localized: "New file that git doesn't track yet. Stage it to include it in the next commit.", bundle: .module))
        } else if status == .deleted, pick.side == .unstaged {
            DiffNote(icon: "info.circle", text: String(localized: "Deleted from the working tree. Stage the deletion to remove it in the next commit.", bundle: .module))
        }
        if let old = file.oldPath, pick.side == .staged {
            let lines = (changes.diff?.additions ?? 0) + (changes.diff?.deletions ?? 0)
            DiffNote(icon: "arrow.right", text: lines > 0
                ? String(localized: "Renamed from \(old), \(n(lines, "line")) changed.", bundle: .module)
                : String(localized: "Renamed from \(old), no content changes.", bundle: .module))
        }
    }

    @ViewBuilder func content(pick: ChangesPick) -> some View {
        let changes = window.changes
        switch changes.diffState {
        case .idle, .loading:
            Spinner().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            EmptyStateView(icon: "exclamationmark.triangle", title: String(localized: "This diff didn't load", bundle: .module), message: ErrorCopy(error).message, small: true)
        case .loaded:
            switch changes.bodyKind {
            case .lines:
                if let diff = changes.diff {
                    WorkingDiffView(
                        diff: diff,
                        side: pick.side,
                        selectable: changes.isLineLevel,
                        selection: changes.lines,
                        mode: roomy ? preferences.diffMode : .unified,
                        wrap: preferences.wrap,
                        whitespace: preferences.whitespace,
                        codeSize: preferences.codeSize
                    )
                }
            case .large(let lines):
                VStack(spacing: 0) {
                    DiffNote(icon: "exclamationmark.triangle", text: String(localized: "This file has \(n(lines, "changed line")), so Vrai shows it as plain text. Stage or discard the whole file.", bundle: .module))
                    if let diff = changes.diff { LargeDiffText(diff: diff) }
                }
            case .binary(let detail):
                EmptyStateView(icon: "doc", title: String(localized: "Binary file, not shown.", bundle: .module), message: detail, small: true)
            case .empty:
                Text(pick.side == .staged ? String(localized: "Nothing staged in this file yet.", bundle: .module) : String(localized: "No unstaged changes in this file.", bundle: .module))
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .padding(Vrai.Space.s40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
