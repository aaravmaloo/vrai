import AppKit
import SwiftUI
import VraiCore
import VraiGit

struct ChangesFileList: View {
    let groups: ChangeGroups
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(\.widthClass) private var widthClass
    @FocusState private var focused: Bool
    @State private var resync = false

    var body: some View {
        let changes = window.changes
        ScrollViewReader { proxy in
            List(selection: selection) {
                ForEach(ChangeGroups.Kind.allCases, id: \.self) { kind in
                    let rows = ChangeRow.rows(kind, in: groups)
                    if !rows.isEmpty {
                        Section {
                            ForEach(rows) { row in
                                ChangeFileRow(
                                    file: row.file,
                                    kind: kind,
                                    selected: changes.isSelected(row.pick),
                                    onToggle: { window.toggleStage(row.file) },
                                    onDiscard: { window.confirmDiscard([row.file.path]) }
                                )
                                .tag(row.pick)
                                .modifier(NarrowClick(active: widthClass.isNarrow) { reopen(row.pick) })
                                .accessibilityAction { changes.select(row.pick, store: store, narrow: widthClass.isNarrow) }
                                .accessibilityIdentifier("change-row-" + kind.rawValue + "-" + row.file.path)
                            }
                        } header: {
                            ChangesGroupHeader(title: title(kind), count: rows.count)
                                .accessibilityIdentifier("changes-group-" + kind.rawValue)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: ChangesPick.self) { picks in
                menu(picks)
            } primaryAction: { picks in
                open(picks)
            }
            .focused($focused)
            .focusEffectDisabled()
            .onChange(of: changes.listFocusRequest) { _, _ in focused = true }
            .onChange(of: changes.pick) { _, pick in
                guard let pick else { return }
                proxy.scrollTo(pick)
            }
            .onAppear {
                guard window.changes.focusRequest == window.changes.focusHandled else { return }
                Task { @MainActor in focused = true }
            }
            .onKeyPress(.space) {
                window.toggleSelectionStaging()
                return .handled
            }
            .onKeyPress(.rightArrow) {
                guard let pick = changes.pick, !pick.conflict, !changes.isMultiple, changes.isLineLevel else { return .ignored }
                changes.diffFocusRequest += 1
                return .handled
            }
            .onKeyPress(.return) {
                guard widthClass.isNarrow, changes.pick != nil else { return .ignored }
                changes.narrowDetail = true
                return .handled
            }
            .onDeleteCommand {
                let paths = window.selectedPaths()
                guard !paths.isEmpty else { return }
                window.confirmDiscard(paths)
            }
            .accessibilityLabel(Text("Changed files", bundle: .module))
            .accessibilityIdentifier("changes-list")
        }
    }

    var current: Set<ChangesPick> {
        let changes = window.changes
        return changes.isMultiple ? changes.selected : Set(changes.pick.map { [$0] } ?? [])
    }

    var selection: Binding<Set<ChangesPick>> {
        Binding(get: { resync ? [] : current }, set: { choose($0) })
    }

    func choose(_ proposed: Set<ChangesPick>) {
        let changes = window.changes
        let order = groups.picks
        let next = Set(FilePicks.ordered(proposed, in: order))
        let now = current
        if next.isEmpty {
            resync = true
            Task { @MainActor in resync = false }
            return
        }
        guard next != now else { return }
        if next.count == 1, let only = next.first {
            changes.select(only, store: store, narrow: widthClass.isNarrow && Self.clicked)
            return
        }
        guard let lead = FilePicks.lead(of: next, after: now, pick: changes.pick, in: order) else { return }
        changes.setSelection(next, lead: lead, store: store)
    }

    static var clicked: Bool {
        guard let type = NSApp.currentEvent?.type else { return false }
        return type == .leftMouseDown || type == .leftMouseUp
    }

    func reopen(_ pick: ChangesPick) {
        guard NSEvent.modifierFlags.intersection([.shift, .command]).isEmpty else { return }
        window.changes.select(pick, store: store, narrow: true)
    }

    func open(_ picks: Set<ChangesPick>) {
        guard widthClass.isNarrow, picks.count == 1, let pick = picks.first else { return }
        window.changes.select(pick, store: store, narrow: true)
    }

    @ViewBuilder func menu(_ picks: Set<ChangesPick>) -> some View {
        if picks.count > 1 {
            WorkingSelectionMenu(picks: FilePicks.ordered(picks, in: groups.picks), window: window)
        } else if let pick = picks.first, let file = store.snapshot?.working.first(where: { $0.path == pick.path }) {
            WorkingFileMenu(file: file, window: window)
        }
    }

    func title(_ kind: ChangeGroups.Kind) -> String {
        switch kind {
        case .conflicts: String(localized: "Conflicts", bundle: .module)
        case .staged: String(localized: "Staged", bundle: .module)
        case .unstaged: String(localized: "Unstaged", bundle: .module)
        case .untracked: String(localized: "Untracked", bundle: .module)
        }
    }
}

struct NarrowClick: ViewModifier {
    let active: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if active {
            content.simultaneousGesture(TapGesture().onEnded(action))
        } else {
            content
        }
    }
}

struct ChangeRow: Identifiable {
    let file: WorkingFile
    let pick: ChangesPick

    var id: ChangesPick { pick }

    static func rows(_ kind: ChangeGroups.Kind, in groups: ChangeGroups) -> [ChangeRow] {
        groups.files(kind).map { file in
            ChangeRow(file: file, pick: ChangesPick(path: file.path, side: ChangeGroups.side(of: kind), conflict: kind == .conflicts))
        }
    }
}

extension FilePicks {
    static func lead(of next: Set<ChangesPick>, after current: Set<ChangesPick>, pick: ChangesPick?, in order: [ChangesPick]) -> ChangesPick? {
        let origin = pick.flatMap { order.firstIndex(of: $0) } ?? 0
        let distance = { (candidate: ChangesPick) in abs((order.firstIndex(of: candidate) ?? origin) - origin) }
        let added = ordered(next.subtracting(current), in: order)
        if !added.isEmpty { return added.max { distance($0) < distance($1) } }
        if let pick, next.contains(pick) { return pick }
        return ordered(next, in: order).min { distance($0) < distance($1) }
    }
}

struct ChangeFileRow: View {
    let file: WorkingFile
    let kind: ChangeGroups.Kind
    let selected: Bool
    let onToggle: () -> Void
    let onDiscard: () -> Void
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        let conflict = kind == .conflicts
        let status = conflict ? FileStatus.conflicted : ChangeGroups.statusLetter(file, side: ChangeGroups.side(of: kind))
        let parts = PathParts.split(file.path)
        let emphasized = prominence == .increased
        HStack(spacing: Vrai.Space.s8) {
            if !conflict {
                StageCheckbox(state: file.staged, label: file.staged == .full ? String(localized: "Unstage \(parts.name)", bundle: .module) : String(localized: "Stage \(parts.name)", bundle: .module), action: onToggle)
                    .accessibilityIdentifier("stage-" + kind.rawValue + "-" + file.path)
            }
            FileStatusTile(status: status)
            HStack(alignment: .firstTextBaseline, spacing: Vrai.Space.s6) {
                if let oldPath = file.oldPath, status == .renamed || status == .copied {
                    HStack(spacing: Vrai.Space.s2) {
                        Text(PathParts.split(oldPath).name)
                        Symbol("arrow.right", font: Font.Vrai.overline)
                    }
                    .font(Font.Vrai.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                }
                Text(parts.name)
                    .foregroundStyle(conflict && !emphasized ? AnyShapeStyle(Color.Vrai.statusConflicted) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .layoutPriority(1)
                if !parts.directory.isEmpty {
                    Text(String(parts.directory.dropLast()))
                        .font(Font.Vrai.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(file.oldPath.map { $0 + " \u{2192} " + file.path } ?? file.path)
            if file.isBinary {
                Text("Binary", bundle: .module)
                    .font(Font.Vrai.caption)
                    .foregroundStyle(.secondary)
            } else if !conflict, file.additions + file.deletions > 0 {
                if emphasized {
                    HStack(spacing: Vrai.Space.s6) {
                        if file.additions > 0 { Text(verbatim: "+\(file.additions)") }
                        if file.deletions > 0 { Text(verbatim: "\u{2212}\(file.deletions)") }
                    }
                    .font(Font.Vrai.caption)
                    .monospacedDigit()
                    .fixedSize()
                } else {
                    DiffStat(additions: file.additions, deletions: file.deletions)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(FileStatusTile(status: status).label + ", " + file.path))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityActions {
            if !conflict {
                Button(String(localized: "Discard changes to \(parts.name)", bundle: .module), action: onDiscard)
            }
        }
    }
}
