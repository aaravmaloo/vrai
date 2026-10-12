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
    @State private var frames = FileFrames()
    @State private var dragging: FileDrag?

    var body: some View {
        let changes = window.changes
        let order = groups.picks
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
                                    selected: changes.isSelected(pick),
                                    onToggle: { window.toggleStage(file) },
                                    onDiscard: { window.confirmDiscard([file.path]) }
                                )
                                .id(pick)
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(FileFrames.space)) } action: { frames.record(pick, $0) }
                                .onTapGesture {
                                    focused = true
                                    click(pick, order: order)
                                }
                                .contextMenu {
                                    if changes.isMultiple, changes.selected.contains(pick) {
                                        WorkingSelectionMenu(picks: FilePicks.ordered(changes.selected, in: order), window: window)
                                    } else {
                                        WorkingFileMenu(file: file, window: window)
                                    }
                                }
                                .accessibilityAction { changes.select(pick, store: store, narrow: widthClass.isNarrow) }
                                .accessibilityIdentifier("change-row-" + kind.rawValue + "-" + file.path)
                            }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Changed files", bundle: .module))
                .coordinateSpace(.named(FileFrames.space))
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .named(FileFrames.space))
                        .onChanged { value in drag(value, order: order) }
                        .onEnded { _ in dragging = nil }
                )
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
        .onAppear {
            guard window.changes.focusRequest == window.changes.focusHandled else { return }
            Task { @MainActor in focused = true }
        }
        .onKeyPress(keys: [.downArrow, .upArrow]) { press in
            move(press.key == .downArrow ? 1 : -1, extend: press.modifiers.contains(.shift))
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

    func click(_ pick: ChangesPick, order: [ChangesPick]) {
        let changes = window.changes
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) {
            changes.extend(to: pick, order: order, store: store)
        } else if flags.contains(.command) {
            changes.toggle(pick, order: order, store: store)
        } else {
            changes.select(pick, store: store, narrow: widthClass.isNarrow)
        }
    }

    func drag(_ value: DragGesture.Value, order: [ChangesPick]) {
        let changes = window.changes
        if dragging == nil {
            frames.keep(order)
            guard let start = frames.pick(at: value.startLocation.y) else { return }
            focused = true
            dragging = FileDrag(start: start, base: NSEvent.modifierFlags.contains(.command) ? (changes.isMultiple ? changes.selected : Set(changes.pick.map { [$0] } ?? [])) : [])
        }
        guard let drag = dragging, let target = frames.pick(at: value.location.y) else { return }
        changes.drag(from: drag.start, to: target, order: order, keeping: drag.base, store: store)
    }

    func move(_ step: Int, extend: Bool) -> KeyPress.Result {
        let changes = window.changes
        let picks = groups.picks
        guard !picks.isEmpty else { return .ignored }
        let index = changes.pick.flatMap { picks.firstIndex(of: $0) } ?? (step > 0 ? -1 : picks.count)
        let next = picks[max(0, min(picks.count - 1, index + step))]
        if extend {
            changes.extend(to: next, order: picks, store: store)
        } else {
            changes.select(next, store: store, narrow: false)
        }
        return .handled
    }

    func discardSelected() -> KeyPress.Result {
        let paths = window.selectedPaths()
        guard !paths.isEmpty else { return .ignored }
        window.confirmDiscard(paths)
        return .handled
    }
}

struct FileDrag {
    let start: ChangesPick
    let base: Set<ChangesPick>
}

final class FileFrames {
    static let space = "changes-file-rows"
    private var frames: [ChangesPick: ClosedRange<CGFloat>] = [:]

    func record(_ pick: ChangesPick, _ frame: CGRect) {
        guard frame.height > 0 else { return }
        frames[pick] = frame.minY...frame.maxY
    }

    func keep(_ order: [ChangesPick]) {
        let live = Set(order)
        frames = frames.filter { live.contains($0.key) }
    }

    func pick(at y: CGFloat) -> ChangesPick? {
        if let hit = frames.first(where: { $0.value.contains(y) }) { return hit.key }
        return frames.min { distance($0.value, y) < distance($1.value, y) }?.key
    }

    private func distance(_ range: ClosedRange<CGFloat>, _ y: CGFloat) -> CGFloat {
        y < range.lowerBound ? range.lowerBound - y : y - range.upperBound
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
        .accessibilityActions {
            if !conflict {
                Button(String(localized: "Discard changes to \(parts.name)", bundle: .module), action: onDiscard)
            }
        }
    }

    var background: Color {
        if selected { return Color.Vrai.accentSoft }
        return hovering && !capture ? Color.Vrai.fill : Color.clear
    }

    func accessibilityText(status: FileStatus) -> String {
        FileStatusTile(status: status).label + ", " + file.path
    }
}
