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
    var layout: CommitColumnLayout
    var checks: CheckState?
}

struct CommitColumnLayout: Equatable {
    static let inset = Vrai.Space.s2

    var leading: CGFloat
    var graph: CGFloat
    var author: CGFloat
    var date: CGFloat
    var hash: CGFloat

    @MainActor static func standalone(lanes: Int) -> CommitColumnLayout {
        CommitColumnLayout(leading: Vrai.Space.s4, graph: GraphCell.width(lanes: lanes), author: Vrai.Size.colAuthor, date: Vrai.Size.colDate, hash: Vrai.Size.colHash)
    }
}

enum CommitTableColumn: String, CaseIterable {
    case graph
    case subject
    case author
    case date
    case hash

    var identifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier(rawValue) }

    var title: String {
        switch self {
        case .graph: String(localized: "Graph", bundle: .module)
        case .subject: String(localized: "Description", bundle: .module)
        case .author: String(localized: "Author", bundle: .module)
        case .date: String(localized: "Date", bundle: .module)
        case .hash: String(localized: "Commit", bundle: .module)
        }
    }

    @MainActor var width: CGFloat {
        switch self {
        case .graph: GraphCell.width(lanes: 1)
        case .subject: Vrai.Size.sheet
        case .author: Vrai.Size.colAuthor
        case .date: Vrai.Size.colDate
        case .hash: Vrai.Size.colHash
        }
    }

    @MainActor var minWidth: CGFloat {
        switch self {
        case .graph: GraphCell.width(lanes: 1)
        case .subject: Vrai.Size.colAuthor
        case .author, .date, .hash: Vrai.Space.s48
        }
    }

    var maxWidth: CGFloat {
        switch self {
        case .graph, .subject: .greatestFiniteMagnitude
        case .author: Vrai.Size.colAuthor * 2
        case .date, .hash: Vrai.Size.colAuthor + Vrai.Space.s40
        }
    }

    var resizing: NSTableColumn.ResizingOptions {
        switch self {
        case .graph: []
        case .subject: .autoresizingMask
        case .author, .date, .hash: .userResizingMask
        }
    }

    func shown(_ columns: CommitColumns) -> Bool {
        switch self {
        case .graph, .subject: true
        case .author: columns.contains(.author)
        case .date: columns.contains(.date)
        case .hash: columns.contains(.hash)
        }
    }
}

struct CommitTableState {
    var history: HistoryState
    var refs: [OID: [RefPillModel]]
    var selection: CommitSelection?
    var focused: Bool
    var active: Bool
    var filter: CommitFilter
    var columns: CommitColumns
    var header: Bool
    var height: CGFloat
    var expert: Bool
    var files: Int
    var scrollRequest: ScrollRequest?
    var signatures: [OID: SignatureState]
    var checks: [OID: CheckState] = [:]

    var offset: Int { history.wipRow == nil ? 0 : 1 }
    var count: Int { history.commits.count + offset }
    var emphasized: Bool { focused && active }

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

    func row(at index: Int, layout: CommitColumnLayout) -> CommitTableRow? {
        if let wip = history.wipRow, index == 0 {
            let selected = selection == .wip
            return CommitTableRow(target: .wip, commit: nil, graph: wip, lanes: history.lanes, height: height, refs: [], selected: selected, focused: selected && emphasized, dim: false, query: "", columns: columns, signature: .unchecked, files: files, expert: expert, layout: layout)
        }
        let position = index - offset
        guard history.commits.indices.contains(position), history.rows.indices.contains(position) else { return nil }
        let commit = history.commits[position]
        let selected = selection == .commit(commit.id)
        return CommitTableRow(
            target: .commit(commit.id),
            commit: commit,
            graph: history.rows[position],
            lanes: history.lanes,
            height: height,
            refs: refs[commit.id] ?? [],
            selected: selected,
            focused: selected && emphasized,
            dim: filter.isActive && !filter.matches(commit),
            query: filter.query,
            columns: columns,
            signature: signatures[commit.id] ?? commit.signature,
            files: 0,
            expert: expert,
            layout: layout,
            checks: checks[commit.id]
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
        let header = NSTableHeaderView()
        table.headerView = state.header ? header : nil
        table.backgroundColor = .clear
        table.style = .inset
        table.selectionHighlightStyle = .regular
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.allowsColumnSelection = false
        table.allowsColumnReordering = false
        table.allowsColumnResizing = true
        table.allowsTypeSelect = false
        table.intercellSpacing = .zero
        table.gridStyleMask = []
        table.focusRingType = .none
        table.usesAutomaticRowHeights = false
        table.rowHeight = state.height
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        for kind in CommitTableColumn.allCases {
            let column = NSTableColumn(identifier: kind.identifier)
            column.title = kind.title
            column.minWidth = kind.minWidth
            column.maxWidth = kind.maxWidth
            column.width = kind.width
            column.resizingMask = kind.resizing
            column.isHidden = !kind.shown(state.columns)
            table.addTableColumn(column)
        }
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.setAccessibilityLabel(String(localized: "Commits", bundle: .module))
        scroll.documentView = table
        context.coordinator.table = table
        context.coordinator.header = header
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
        var header: NSTableHeaderView?
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
        private var layout = CommitColumnLayout.standalone(lanes: 1)
        private var measured = false
        private var graphKey: GraphKey?

        struct GraphKey: Equatable {
            var lanes: Int
            var header: Bool
        }

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
            arrange(state)
            let first = state.count > 0 ? state.target(at: 0) : nil
            let anchorKept = rowCount > 0 && first == firstID && state.count >= rowCount && state.target(at: rowCount - 1) == lastID
            if previous == nil || !anchorKept {
                rowCount = state.count
                table.reloadData()
                if measure() { refreshVisible(force: false) }
            } else {
                if state.count != rowCount {
                    rowCount = state.count
                    table.noteNumberOfRowsChanged()
                }
                measure()
                refreshVisible(force: restyle)
            }
            syncSelection()
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

        private func arrange(_ state: CommitTableState) {
            guard let table else { return }
            var changed = false
            var top: CGFloat?
            if (table.headerView != nil) != state.header, let clip = table.enclosingScrollView?.contentView {
                top = clip.bounds.minY + clip.contentInsets.top
                table.headerView = state.header ? header : nil
                changed = true
            }
            for kind in CommitTableColumn.allCases {
                guard let column = table.tableColumn(withIdentifier: kind.identifier) else { continue }
                let hidden = !kind.shown(state.columns)
                if column.isHidden != hidden {
                    column.isHidden = hidden
                    changed = true
                }
            }
            let key = GraphKey(lanes: state.history.lanes, header: state.header)
            if key != graphKey, let column = table.tableColumn(withIdentifier: CommitTableColumn.graph.identifier) {
                graphKey = key
                let title = state.header ? column.headerCell.cellSize.width : 0
                let width = max(GraphCell.width(lanes: key.lanes), title).rounded(.up)
                if column.width != width {
                    column.width = width
                    changed = true
                }
            }
            guard changed else { return }
            table.sizeToFit()
            guard let scroll = table.enclosingScrollView else { return }
            scroll.tile()
            if let top {
                let clip = scroll.contentView
                clip.scroll(to: NSPoint(x: clip.bounds.minX, y: max(-clip.contentInsets.top, top - clip.contentInsets.top)))
                scroll.reflectScrolledClipView(clip)
            }
        }

        @discardableResult private func measure() -> Bool {
            guard let table, table.numberOfRows > 0 else { return false }
            func frame(_ kind: CommitTableColumn) -> NSRect {
                let index = table.column(withIdentifier: kind.identifier)
                return index < 0 ? .zero : table.frameOfCell(atColumn: index, row: 0)
            }
            let graph = frame(.graph)
            let next = CommitColumnLayout(leading: graph.minX, graph: graph.width, author: frame(.author).width, date: frame(.date).width, hash: frame(.hash).width)
            measured = true
            guard next != layout else { return false }
            layout = next
            return true
        }

        private func syncSelection() {
            guard let table, let state else { return }
            let wanted = state.selection.flatMap { state.index(of: $0) }.map { IndexSet(integer: $0) } ?? IndexSet()
            if table.selectedRowIndexes != wanted {
                table.selectRowIndexes(wanted, byExtendingSelection: false)
            }
        }

        func scroll(to target: CommitSelection, center: Bool) {
            guard let table, let state, let index = state.index(of: target), let scroll = table.enclosingScrollView else { return }
            table.layoutSubtreeIfNeeded()
            guard center else {
                table.scrollRowToVisible(index)
                return
            }
            let rect = table.rect(ofRow: index)
            let clip = scroll.contentView
            let insets = clip.contentInsets
            let visible = clip.bounds.height - insets.top - insets.bottom
            let minY = -insets.top
            let maxY = max(minY, table.bounds.height - clip.bounds.height + insets.bottom)
            let y = min(max(minY, rect.midY - visible / 2 - insets.top), maxY)
            clip.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        private func refreshVisible(force: Bool) {
            guard let table else { return }
            let emphasized = state?.emphasized ?? false
            table.enumerateAvailableRowViews { rowView, row in
                guard let rowView = rowView as? CommitTableRowView else { return }
                rowView.emphasis = emphasized
                self.configure(rowView, row: row, force: force)
            }
        }

        private func configure(_ rowView: CommitTableRowView, row: Int, force: Bool) {
            guard let state, let content else { return }
            if !measured { measure() }
            guard let model = state.row(at: row, layout: layout) else { return }
            if !force, rowView.model == model { return }
            rowView.model = model
            rowView.host.rootView = AnyView(content(model).ignoresSafeArea().environment(\.self, environment))
            rowView.host.setAccessibilityLabel(model.commit.map { $0.subject + ", " + $0.authorName } ?? String(localized: "Uncommitted changes", bundle: .module))
            shown?(row, state)
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rowCount
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rowView = tableView.makeView(withIdentifier: CommitTableRowView.identifier, owner: nil) as? CommitTableRowView ?? CommitTableRowView()
            rowView.emphasis = state?.emphasized ?? false
            configure(rowView, row: row, force: false)
            return rowView
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            nil
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            false
        }

        func selectionShouldChange(in tableView: NSTableView) -> Bool {
            false
        }

        func tableViewColumnDidResize(_ notification: Notification) {
            if measure() { refreshVisible(force: false) }
        }
    }
}

final class CommitTableView: NSTableView {
    override var acceptsFirstResponder: Bool { false }

    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        true
    }
}

final class CommitTableRowView: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("commit-row")

    let host = NSHostingView(rootView: AnyView(EmptyView()))
    var model: CommitTableRow?
    var emphasis = false {
        didSet {
            if super.isEmphasized != emphasis { super.isEmphasized = emphasis }
        }
    }

    override var isEmphasized: Bool {
        get { super.isEmphasized }
        set { if super.isEmphasized != emphasis { super.isEmphasized = emphasis } }
    }

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
        if host.frame != bounds { host.frame = bounds }
    }
}
