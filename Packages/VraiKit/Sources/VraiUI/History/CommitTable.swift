import AppKit
import SwiftUI
import VraiCore
import VraiGit

struct CommitTableRow: Equatable {
    var target: CommitSelection
    var commit: Commit?
    var graph: GraphRow
    var lanes: Int
    var height: CGFloat
    var refs: [RefPillModel]
    var selected: Bool
    var focused: Bool
    var dim: Bool
    var query: String
    var columns: CommitColumns
    var signature: SignatureState
    var files: Int
    var expert: Bool
}

struct CommitTableState {
    var history: HistoryState
    var refs: [OID: [RefPillModel]]
    var selection: CommitSelection?
    var focused: Bool
    var filter: CommitFilter
    var columns: CommitColumns
    var height: CGFloat
    var expert: Bool
    var files: Int
    var scrollRequest: ScrollRequest?
    var signatures: [OID: SignatureState]

    var offset: Int { history.wipRow == nil ? 0 : 1 }
    var count: Int { history.commits.count + offset }

    func target(at index: Int) -> CommitSelection? {
        if history.wipRow != nil, index == 0 { return .wip }
        let position = index - offset
        guard history.commits.indices.contains(position) else { return nil }
        return .commit(history.commits[position].id)
    }

    func index(of target: CommitSelection) -> Int? {
        switch target {
        case .wip: history.wipRow == nil ? nil : 0
        case .commit(let id): history.index[id].map { $0 + offset }
        }
    }

    func row(at index: Int) -> CommitTableRow? {
        if let wip = history.wipRow, index == 0 {
            return CommitTableRow(target: .wip, commit: nil, graph: wip, lanes: history.lanes, height: height, refs: [], selected: selection == .wip, focused: focused, dim: false, query: "", columns: columns, signature: .unchecked, files: files, expert: expert)
        }
        let position = index - offset
        guard history.commits.indices.contains(position), history.rows.indices.contains(position) else { return nil }
        let commit = history.commits[position]
        return CommitTableRow(
            target: .commit(commit.id),
            commit: commit,
            graph: history.rows[position],
            lanes: history.lanes,
            height: height,
            refs: refs[commit.id] ?? [],
            selected: selection == .commit(commit.id),
            focused: focused,
            dim: filter.isActive && !filter.matches(commit),
            query: filter.query,
            columns: columns,
            signature: signatures[commit.id] ?? commit.signature,
            files: 0,
            expert: expert
        )
    }
}

struct CommitTable<Row: View>: NSViewRepresentable {
    let state: CommitTableState
    let content: (CommitTableRow) -> Row
    let onRowShown: (Int, CommitTableState) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: Vrai.Space.s8, right: 0)
        let table = CommitTableView()
        table.headerView = nil
        table.backgroundColor = .clear
        table.style = .plain
        table.selectionHighlightStyle = .none
        table.allowsEmptySelection = true
        table.allowsColumnSelection = false
        table.allowsTypeSelect = false
        table.intercellSpacing = .zero
        table.gridStyleMask = []
        table.focusRingType = .none
        table.usesAutomaticRowHeights = false
        table.rowHeight = state.height
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let column = NSTableColumn(identifier: CommitTableView.column)
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        scroll.documentView = table
        context.coordinator.table = table
        if PerfLog.isEnabled {
            let monitor = FrameMonitorView(name: "scroll")
            monitor.scrollView = scroll
            scroll.addSubview(monitor)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(state: state, environment: context.environment, content: { AnyView(content($0)) }, shown: onRowShown)
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.table = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var table: CommitTableView?
        private var state: CommitTableState?
        private var environment = EnvironmentValues()
        private var content: ((CommitTableRow) -> AnyView)?
        private var shown: ((Int, CommitTableState) -> Void)?
        private var firstID: CommitSelection?
        private var lastID: CommitSelection?
        private var rowCount = 0
        private var handledScroll: Int?
        private var lastSelection: CommitSelection?
        private var appearance: AppearanceKey?

        struct AppearanceKey: Equatable {
            var scheme: ColorScheme
            var contrast: ColorSchemeContrast
            var reduceMotion: Bool
            var size: DynamicTypeSize
        }

        func update(state: CommitTableState, environment: EnvironmentValues, content: @escaping (CommitTableRow) -> AnyView, shown: @escaping (Int, CommitTableState) -> Void) {
            guard let table else { return }
            let previous = self.state
            self.state = state
            self.environment = environment
            self.content = content
            self.shown = shown
            let key = AppearanceKey(scheme: environment.colorScheme, contrast: environment.colorSchemeContrast, reduceMotion: environment.accessibilityReduceMotion, size: environment.dynamicTypeSize)
            let restyle = key != appearance
            appearance = key
            if table.rowHeight != state.height {
                table.rowHeight = state.height
            }
            let first = state.count > 0 ? state.target(at: 0) : nil
            let anchorKept = rowCount > 0 && first == firstID && state.count >= rowCount && state.target(at: rowCount - 1) == lastID
            if previous == nil || !anchorKept {
                rowCount = state.count
                table.reloadData()
            } else if state.count != rowCount {
                rowCount = state.count
                table.noteNumberOfRowsChanged()
                refreshVisible(force: restyle)
            } else {
                refreshVisible(force: restyle)
            }
            firstID = first
            lastID = state.count > 0 ? state.target(at: state.count - 1) : nil
            if let request = state.scrollRequest, request.sequence != handledScroll {
                handledScroll = request.sequence
                DispatchQueue.main.async { self.scroll(to: request.target, center: true) }
            } else if state.selection != lastSelection, state.focused, let selection = state.selection {
                scroll(to: selection, center: false)
            }
            lastSelection = state.selection
        }

        func scroll(to target: CommitSelection, center: Bool) {
            guard let table, let state, let index = state.index(of: target), let scroll = table.enclosingScrollView else { return }
            table.layoutSubtreeIfNeeded()
            guard center else {
                table.scrollRowToVisible(index)
                return
            }
            let rect = table.rect(ofRow: index)
            let visible = scroll.contentView.bounds.height
            let maxY = max(0, table.bounds.height - visible + scroll.contentInsets.bottom)
            let y = min(max(0, rect.midY - visible / 2), maxY)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        private func refreshVisible(force: Bool) {
            guard let table else { return }
            table.enumerateAvailableRowViews { rowView, row in
                guard let cell = rowView.view(atColumn: 0) as? CommitCellView else { return }
                self.configure(cell, row: row, force: force)
            }
        }

        private func configure(_ cell: CommitCellView, row: Int, force: Bool) {
            guard let state, let content, let model = state.row(at: row) else { return }
            if !force, cell.model == model { return }
            cell.model = model
            cell.host.rootView = AnyView(content(model).ignoresSafeArea().environment(\.self, environment))
            shown?(row, state)
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rowCount
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let cell = tableView.makeView(withIdentifier: CommitCellView.identifier, owner: nil) as? CommitCellView ?? CommitCellView()
            configure(cell, row: row, force: false)
            return cell
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            false
        }

        func selectionShouldChange(in tableView: NSTableView) -> Bool {
            false
        }
    }
}

final class CommitTableView: NSTableView {
    static let column = NSUserInterfaceItemIdentifier("commit")

    override var acceptsFirstResponder: Bool { false }

    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        true
    }
}

final class CommitCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("commit-cell")

    let host = NSHostingView(rootView: AnyView(EmptyView()))
    var model: CommitTableRow?

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = true
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        placeHost()
    }

    override func layout() {
        super.layout()
        placeHost()
    }

    private func placeHost() {
        let frame = NSRect(x: Vrai.Space.s4, y: 0, width: max(0, bounds.width - Vrai.Space.s4 * 2), height: bounds.height)
        if host.frame != frame { host.frame = frame }
    }
}
