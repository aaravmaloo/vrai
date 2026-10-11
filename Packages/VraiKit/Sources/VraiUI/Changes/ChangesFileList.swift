import SwiftUI
import VraiCore
import VraiGit

struct ChangesFileList: View {
    let groups: ChangeGroups
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(\.widthClass) private var widthClass
    @FocusState private var focused: Bool

    var body: some View {
        let changes = window.changes
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(ChangeGroups.Kind.allCases, id: \.self) { kind in
                        let files = groups.files(kind)
                        if !files.isEmpty {
                            ChangesGroupHeader(title: title(kind), count: files.count)
                                .accessibilityIdentifier("changes-group-" + kind.rawValue)
                            ForEach(files) { file in
                                let pick = ChangesPick(path: file.path, side: ChangeGroups.side(of: kind), conflict: kind == .conflicts)
                                ChangeFileRow(
                                    file: file,
                                    kind: kind,
                                    selected: changes.pick == pick,
                                    onToggle: { window.toggleStage(file) },
                                    onDiscard: { window.confirmDiscard([file.path]) }
                                )
                                .id(pick)
                                .onTapGesture {
                                    focused = true
                                    changes.select(pick, store: store, narrow: widthClass.isNarrow)
                                }
                                .contextMenu { WorkingFileMenu(file: file, window: window) }
                                .accessibilityAction { changes.select(pick, store: store, narrow: widthClass.isNarrow) }
                                .accessibilityIdentifier("change-row-" + kind.rawValue + "-" + file.path)
                            }
                        }
                    }
                }
                .padding(.horizontal, Vrai.Space.s4)
                .padding(.top, Vrai.Space.s4)
                .padding(.bottom, Vrai.Space.s8)
            }
            .onChange(of: changes.pick) { _, pick in
                guard let pick else { return }
                proxy.scrollTo(pick)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onChange(of: changes.listFocusRequest) { _, _ in focused = true }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.space) {
            window.toggleSelectionStaging()
            return .handled
        }
        .onKeyPress(.delete) { discardSelected() }
        .onKeyPress(.deleteForward) { discardSelected() }
        .onKeyPress(.return) {
            guard widthClass.isNarrow, changes.pick != nil else { return .ignored }
            changes.narrowDetail = true
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Changed files", bundle: .module))
        .accessibilityIdentifier("changes-list")
    }

    func title(_ kind: ChangeGroups.Kind) -> String {
        switch kind {
        case .conflicts: String(localized: "Conflicts", bundle: .module)
        case .staged: String(localized: "Staged", bundle: .module)
        case .unstaged: String(localized: "Unstaged", bundle: .module)
        case .untracked: String(localized: "Untracked", bundle: .module)
        }
    }

    func move(_ step: Int) -> KeyPress.Result {
        let changes = window.changes
        let picks = groups.picks
        guard !picks.isEmpty else { return .ignored }
        let index = changes.pick.flatMap { picks.firstIndex(of: $0) } ?? (step > 0 ? -1 : picks.count)
        let next = picks[max(0, min(picks.count - 1, index + step))]
        changes.select(next, store: store, narrow: false)
        return .handled
    }

    func discardSelected() -> KeyPress.Result {
        guard let pick = window.changes.pick, !pick.conflict else { return .ignored }
        window.confirmDiscard([pick.path])
        return .handled
    }
}

struct ChangeFileRow: View {
    let file: WorkingFile
    let kind: ChangeGroups.Kind
    let selected: Bool
    let onToggle: () -> Void
    let onDiscard: () -> Void
    @State private var hovering = false
    @Environment(\.captureMode) private var capture

    var body: some View {
        let conflict = kind == .conflicts
        let status = conflict ? FileStatus.conflicted : ChangeGroups.statusLetter(file, side: ChangeGroups.side(of: kind))
        let parts = PathParts.split(file.path)
        let showActions = hovering && !capture && !conflict
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
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
                }
                Text(parts.name)
                    .font(Font.Vrai.body)
                    .foregroundStyle(conflict ? Color.Vrai.statusConflicted : Color.Vrai.text)
                    .lineLimit(1)
                    .layoutPriority(1)
                if !parts.directory.isEmpty {
                    Text(String(parts.directory.dropLast()))
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(file.oldPath.map { $0 + " \u{2192} " + file.path } ?? file.path)
            if showActions {
                IconButton(icon: "arrow.uturn.backward", label: String(localized: "Discard changes to \(parts.name)", bundle: .module), small: true, action: onDiscard)
            } else if file.isBinary {
                Text("Binary", bundle: .module)
                    .font(Font.Vrai.caption)
                    .foregroundStyle(Color.Vrai.textTertiary)
            } else if !conflict, file.additions + file.deletions > 0 {
                DiffStat(additions: file.additions, deletions: file.deletions)
            }
        }
        .padding(.leading, Vrai.Space.s6)
        .padding(.trailing, Vrai.Space.s8)
        .frame(height: Vrai.Size.row)
        .background(background, in: RoundedRectangle(cornerRadius: Vrai.Radius.sm, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(accessibilityText(status: status)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    var background: Color {
        if selected { return Color.Vrai.accentSoft }
        return hovering && !capture ? Color.Vrai.fill : Color.clear
    }

    func accessibilityText(status: FileStatus) -> String {
        FileStatusTile(status: status).label + ", " + file.path
    }
}
