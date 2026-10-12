import AppKit
import SwiftUI
import VraiCore
import VraiGit

struct WorkingDiffView: View {
    let diff: FileDiff
    let side: LineSelection.Side
    let selectable: Bool
    let selection: LineSelection?
    var mode: Preferences.DiffMode = .unified
    var wrap = false
    var whitespace = false
    var codeSize = DiffMetrics.defaultSize
    @Environment(WindowModel.self) private var window
    @State private var hoveredHunk: Int?
    @State private var scrollTarget: LineID?
    @State private var frames = LineFrames()
    @State private var dragging: LineDrag?
    @FocusState private var focused: Bool

    var body: some View {
        let metrics = DiffMetrics(codeSize: codeSize)
        let language = SyntaxHighlighter.language(for: diff.path)
        GeometryReader { geometry in
            ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(Array(diff.hunks.enumerated()), id: \.offset) { index, hunk in
                        Section {
                            if mode == .split {
                                ForEach(Array(IndexedSplitRow.rows(hunk).enumerated()), id: \.offset) { _, row in
                                    SelectableSplitLine(row: row, hunk: index, language: language, whitespace: whitespace, metrics: metrics, selectable: selectable, selection: selection, frames: frames, onClick: click, onDrag: drag, onDragEnd: endDrag)
                                        .onHover { if $0 { hoveredHunk = index } }
                                }
                            } else {
                                ForEach(Array(hunk.lines.enumerated()), id: \.offset) { offset, line in
                                    let id = LineID(hunk: index, line: offset)
                                    SelectableUnifiedLine(line: line, id: id, language: language, wrap: wrap, whitespace: whitespace, metrics: metrics, selectable: selectable && (line.kind == .add || line.kind == .del), draggable: selectable, selected: selection?.contains(id) ?? false, frames: frames, onClick: click, onDrag: drag, onDragEnd: endDrag)
                                        .frame(minWidth: geometry.size.width, alignment: .leading)
                                        .id(id)
                                        .onHover { if $0 { hoveredHunk = index } }
                                }
                            }
                        } header: {
                            WorkingHunkHeader(
                                hunk: hunk,
                                index: index,
                                first: index == 0,
                                side: side,
                                selectedHere: selectable ? (selection?.count(inHunk: index) ?? 0) : 0,
                                visible: hoveredHunk == index
                            )
                            .frame(minWidth: geometry.size.width, alignment: .leading)
                            .onHover { if $0 { hoveredHunk = index } }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Lines", bundle: .module))
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                .coordinateSpace(.named(LineFrames.space))
            }
            .onHover { if !$0 { hoveredHunk = nil } }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                proxy.scrollTo(target)
            }
            }
        }
        .background(Color.Vrai.bg)
        .focusable(selectable)
        .focusEffectDisabled()
        .focused($focused)
        .onChange(of: window.changes.diffFocusRequest) { _, _ in
            guard selectable else { return }
            focused = true
            if selection == nil { _ = step(1, extending: false) }
        }
        .onKeyPress(keys: [.downArrow, .upArrow], phases: [.down, .repeat]) { press in
            step(press.key == .downArrow ? 1 : -1, extending: press.modifiers.contains(.shift))
        }
        .onKeyPress(.space) {
            window.toggleSelectionStaging()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            window.changes.listFocusRequest += 1
            return .handled
        }
        .onKeyPress(.escape) {
            guard selection != nil else { return .ignored }
            window.changes.clearLines()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Diff", bundle: .module))
        .accessibilityIdentifier("changes-diff")
    }

    var changedLines: [LineID] {
        diff.hunks.indices.flatMap { hunk in
            diff.hunks[hunk].lines.indices.compactMap { line in
                let kind = diff.hunks[hunk].lines[line].kind
                return kind == .add || kind == .del ? LineID(hunk: hunk, line: line) : nil
            }
        }
    }

    func step(_ delta: Int, extending: Bool) -> KeyPress.Result {
        guard selectable else { return .ignored }
        let order = changedLines
        guard !order.isEmpty else { return .ignored }
        let current = selection?.anchor.flatMap { order.firstIndex(of: $0) }
        let next = current.map { max(0, min(order.count - 1, $0 + delta)) } ?? (delta > 0 ? 0 : order.count - 1)
        guard next != current else { return .handled }
        window.changes.click(order[next], extending: extending, toggling: false)
        scrollTarget = order[next]
        return .handled
    }

    func click(_ id: LineID) {
        let flags = NSEvent.modifierFlags
        window.changes.click(id, extending: flags.contains(.shift), toggling: flags.contains(.command))
        window.changes.listFocusRequest += 1
    }

    func drag(_ start: LineID, _ location: CGPoint) {
        guard selectable else { return }
        if dragging == nil {
            let keep = NSEvent.modifierFlags.contains(.command) ? (selection?.lines ?? []) : []
            dragging = LineDrag(start: start, base: keep)
        }
        guard let dragging, let target = frames.line(at: location.y, from: dragging.start) else { return }
        window.changes.drag(from: dragging.start, to: target, keeping: dragging.base)
    }

    func endDrag() {
        guard dragging != nil else { return }
        dragging = nil
        window.changes.listFocusRequest += 1
    }
}

enum LineHint {
    static var text: String { String(localized: "Click to pick lines, Shift-click to extend", bundle: .module) }
}

struct LineDrag {
    let start: LineID
    let base: Set<LineID>
}

final class LineFrames {
    static let space = "changes-diff-lines"
    private var frames: [LineID: ClosedRange<CGFloat>] = [:]

    func record(_ ids: [LineID], _ frame: CGRect) {
        guard frame.height > 0 else { return }
        for id in ids { frames[id] = frame.minY...frame.maxY }
    }

    func line(at y: CGFloat, from start: LineID) -> LineID? {
        let downward = frames[start].map { y >= $0.lowerBound } ?? true
        let hits = frames.filter { $0.value.contains(y) }.map(\.key)
        if let hit = downward ? hits.max() : hits.min() { return hit }
        let nearest = frames.min { distance($0.value, y) < distance($1.value, y) }
        return nearest?.key
    }

    private func distance(_ range: ClosedRange<CGFloat>, _ y: CGFloat) -> CGFloat {
        y < range.lowerBound ? range.lowerBound - y : y - range.upperBound
    }
}

struct GutterDrag: ViewModifier {
    let enabled: Bool
    let ids: [LineID]
    let frames: LineFrames
    let onDrag: (LineID, CGPoint) -> Void
    let onDragEnd: () -> Void

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(LineFrames.space)) } action: { frames.record(ids, $0) }
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .named(LineFrames.space))
                    .onChanged { value in
                        guard enabled, let start = ids.first else { return }
                        onDrag(start, value.location)
                    }
                    .onEnded { _ in onDragEnd() },
                including: enabled ? .all : .subviews
            )
    }
}

struct WorkingHunkHeader: View {
    let hunk: Hunk
    let index: Int
    let first: Bool
    let side: LineSelection.Side
    let selectedHere: Int
    let visible: Bool
    @Environment(WindowModel.self) private var window

    var body: some View {
        let staged = side == .staged
        let shown = visible || selectedHere > 0
        HStack(spacing: Vrai.Space.s8) {
            Text(hunk.header)
                .font(Font.Vrai.codeSmall)
                .foregroundStyle(Color.Vrai.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityActions {
                    Button(staged ? String(localized: "Unstage hunk", bundle: .module) : String(localized: "Stage hunk", bundle: .module)) {
                        window.hunkAction(staged ? .unstage : .stage, hunk: index)
                    }
                    if !staged {
                        Button(String(localized: "Discard hunk", bundle: .module)) {
                            window.hunkAction(.discard, hunk: index)
                        }
                    }
                }
            HStack(spacing: Vrai.Space.s4) {
                if selectedHere > 0 {
                    VraiButton(title: staged ? String(localized: "Unstage \(n(selectedHere, "line"))", bundle: .module) : String(localized: "Stage \(n(selectedHere, "line"))", bundle: .module), icon: staged ? "minus" : "plus", variant: .primary, size: .small) {
                        window.applySelectedLines(staged ? .unstage : .stage, hunk: index)
                    }
                    .accessibilityIdentifier("hunk-\(index)-lines")
                    if !staged {
                        VraiButton(title: String(localized: "Discard", bundle: .module), icon: "arrow.uturn.backward", variant: .plain, size: .small) {
                            window.applySelectedLines(.discard, hunk: index)
                        }
                        .accessibilityIdentifier("hunk-\(index)-discard-lines")
                    }
                } else {
                    VraiButton(title: staged ? String(localized: "Unstage hunk", bundle: .module) : String(localized: "Stage hunk", bundle: .module), icon: staged ? "minus" : "plus", size: .small) {
                        window.hunkAction(staged ? .unstage : .stage, hunk: index)
                    }
                    .accessibilityIdentifier("hunk-\(index)-stage")
                    if !staged {
                        VraiButton(title: String(localized: "Discard", bundle: .module), icon: "arrow.uturn.backward", variant: .plain, size: .small) {
                            window.hunkAction(.discard, hunk: index)
                        }
                        .accessibilityIdentifier("hunk-\(index)-discard")
                    }
                }
            }
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .animation(Animation.Vrai.standardFast, value: shown)
        }
        .padding(.leading, Vrai.Space.s12)
        .padding(.trailing, Vrai.Space.s8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Metrics.hunkHeight)
        .background(Color.Vrai.diffHunkBg)
        .background(Color.Vrai.bg)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(Color.Vrai.Contrast.separator).frame(height: Metrics.hairline) }
        }
        .hairline(.bottom)
        .accessibilityElement(children: .contain)
    }
}

struct GutterNumber: View {
    let number: Int?
    let font: Font
    let color: Color

    var body: some View {
        Text(verbatim: Metrics.codeColumn)
            .font(font)
            .hidden()
            .overlay(alignment: .trailing) {
                if let number {
                    Text(verbatim: String(number))
                        .font(font)
                        .monospacedDigit()
                        .foregroundStyle(color)
                }
            }
            .padding(.leading, Vrai.Space.s4)
            .padding(.trailing, Vrai.Space.s8)
    }
}

struct SelectableUnifiedLine: View {
    let line: DiffLine
    let id: LineID
    let language: String
    let wrap: Bool
    let whitespace: Bool
    let metrics: DiffMetrics
    let selectable: Bool
    let draggable: Bool
    let selected: Bool
    let frames: LineFrames
    let onClick: (LineID) -> Void
    let onDrag: (LineID, CGPoint) -> Void
    let onDragEnd: () -> Void
    @State private var hovering = false
    @Environment(\.captureMode) private var capture

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(spacing: 0) {
                GutterNumber(number: line.kind == .add ? nil : line.oldNumber, font: metrics.numberFont, color: numberColor)
                GutterNumber(number: line.kind == .del ? nil : line.newNumber, font: metrics.numberFont, color: numberColor)
                Text(mark)
                    .font(metrics.codeFont)
                    .foregroundStyle(markColor)
                    .frame(width: Vrai.Space.s20)
            }
            .frame(minHeight: metrics.lineHeight, maxHeight: .infinity)
            .background(gutter)
            .contentShape(Rectangle())
            .onTapGesture { if selectable { onClick(id) } }
            .modifier(GutterDrag(enabled: draggable, ids: [id], frames: frames, onDrag: onDrag, onDragEnd: onDragEnd))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(gutterLabel)
            .accessibilityAddTraits(selectable ? [.isButton] : [.isStaticText])
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("gutter-\(id.hunk)-\(id.line)")
            .accessibilityAction { if selectable { onClick(id) } }
            .help(selectable ? LineHint.text : "")
            Text(CodeRenderer.attributed(line.text, language: language, words: line.wordRanges, wordColor: line.kind == .add ? Color.Vrai.diffAddWord : line.kind == .del ? Color.Vrai.diffDelWord : nil, whitespace: whitespace))
                .font(metrics.codeFont)
                .foregroundStyle(line.kind == .noNewline ? Color.Vrai.textTertiary : Color.Vrai.text)
                .lineLimit(wrap ? nil : 1)
                .fixedSize(horizontal: !wrap, vertical: true)
                .padding(.trailing, Vrai.Space.s16)
                .frame(maxWidth: .infinity, minHeight: metrics.lineHeight, alignment: .leading)
                .clipped()
                .accessibilityHidden(true)
        }
        .background(background)
        .overlay(alignment: .leading) {
            if selected {
                Rectangle().fill(Color.Vrai.accent).frame(width: ChangesMetrics.selectionBar)
            }
        }
        .onHover { hovering = selectable && $0 }
    }

    var mark: String {
        switch line.kind {
        case .add: "+"
        case .del: "\u{2212}"
        case .context, .noNewline: ""
        }
    }

    var numberColor: Color {
        selected ? Color.Vrai.accentText : Color.Vrai.textTertiary
    }

    var markColor: Color {
        if selected || (hovering && !capture) { return Color.Vrai.accentText }
        switch line.kind {
        case .add: return Color.Vrai.success
        case .del: return Color.Vrai.danger
        default: return Color.Vrai.textTertiary
        }
    }

    var background: Color {
        switch line.kind {
        case .add: Color.Vrai.diffAddBg
        case .del: Color.Vrai.diffDelBg
        default: Color.clear
        }
    }

    var gutter: Color {
        if selected { return Color.Vrai.accentSoftStrong }
        switch line.kind {
        case .add: return Color.Vrai.diffAddGutter
        case .del: return Color.Vrai.diffDelGutter
        default: return Color.clear
        }
    }

    var gutterLabel: String {
        switch line.kind {
        case .add: String(localized: "Added line \(line.newNumber ?? 0): \(line.text)", bundle: .module)
        case .del: String(localized: "Removed line \(line.oldNumber ?? 0): \(line.text)", bundle: .module)
        case .context: String(localized: "Line \(line.newNumber ?? 0): \(line.text)", bundle: .module)
        default: line.text
        }
    }
}

struct IndexedSplitRow {
    var old: (line: DiffLine, index: Int)?
    var new: (line: DiffLine, index: Int)?
    var context: Bool

    static func rows(_ hunk: Hunk) -> [IndexedSplitRow] {
        var out: [IndexedSplitRow] = []
        let lines = Array(hunk.lines.enumerated()).filter { $0.element.kind != .noNewline }
        var position = 0
        while position < lines.count {
            let (index, line) = lines[position]
            if line.kind == .context {
                out.append(IndexedSplitRow(old: (line, index), new: (line, index), context: true))
                position += 1
                continue
            }
            var dels: [(DiffLine, Int)] = []
            var adds: [(DiffLine, Int)] = []
            while position < lines.count, lines[position].element.kind == .del {
                dels.append((lines[position].element, lines[position].offset))
                position += 1
            }
            while position < lines.count, lines[position].element.kind == .add {
                adds.append((lines[position].element, lines[position].offset))
                position += 1
            }
            for offset in 0..<max(dels.count, adds.count) {
                out.append(IndexedSplitRow(
                    old: offset < dels.count ? (dels[offset].0, dels[offset].1) : nil,
                    new: offset < adds.count ? (adds[offset].0, adds[offset].1) : nil,
                    context: false
                ))
            }
        }
        return out
    }
}

struct SelectableSplitLine: View {
    let row: IndexedSplitRow
    let hunk: Int
    let language: String
    let whitespace: Bool
    let metrics: DiffMetrics
    let selectable: Bool
    let selection: LineSelection?
    let frames: LineFrames
    let onClick: (LineID) -> Void
    let onDrag: (LineID, CGPoint) -> Void
    let onDragEnd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            side(row.old, old: true)
            Rectangle().fill(Color.Vrai.Contrast.separator).frame(width: Metrics.hairline)
            side(row.new, old: false)
        }
        .frame(minHeight: metrics.lineHeight)
    }

    @ViewBuilder func side(_ entry: (line: DiffLine, index: Int)?, old: Bool) -> some View {
        if let entry {
            let change = !row.context
            let id = LineID(hunk: hunk, line: entry.index)
            let selected = change && (selection?.contains(id) ?? false)
            HStack(spacing: 0) {
                GutterNumber(number: old ? entry.line.oldNumber : entry.line.newNumber, font: metrics.numberFont, color: selected ? Color.Vrai.accentText : Color.Vrai.textTertiary)
                    .frame(maxHeight: .infinity)
                    .background(selected ? Color.Vrai.accentSoftStrong : change ? (old ? Color.Vrai.diffDelGutter : Color.Vrai.diffAddGutter) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { if selectable, change { onClick(id) } }
                    .modifier(GutterDrag(enabled: selectable, ids: [id], frames: frames, onDrag: onDrag, onDragEnd: onDragEnd))
                    .accessibilityAddTraits(selectable && change ? [.isButton] : [.isStaticText])
                    .accessibilityAction { if selectable, change { onClick(id) } }
                    .accessibilityIdentifier("gutter-\(hunk)-\(entry.index)")
                    .help(selectable && change ? LineHint.text : "")
                Text(CodeRenderer.attributed(entry.line.text, language: language, words: change ? entry.line.wordRanges : [], wordColor: old ? Color.Vrai.diffDelWord : Color.Vrai.diffAddWord, whitespace: whitespace))
                    .font(metrics.codeFont)
                    .foregroundStyle(Color.Vrai.text)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
            }
            .background(selected ? Color.Vrai.accentSoftStrong : change ? (old ? Color.Vrai.diffDelBg : Color.Vrai.diffAddBg) : Color.clear)
            .frame(maxWidth: .infinity)
        } else {
            Hatch()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct LargeDiffText: NSViewRepresentable {
    let diff: FileDiff

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false
            text.isSelectable = true
            text.drawsBackground = false
            text.isHorizontallyResizable = true
            text.textContainer?.widthTracksTextView = false
            text.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            text.textContainerInset = NSSize(width: Vrai.Space.s12, height: Vrai.Space.s8)
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let text = nsView.documentView as? NSTextView else { return }
        if context.coordinator.shown == diff { return }
        context.coordinator.shown = diff
        text.textStorage?.setAttributedString(Self.render(diff))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var shown: FileDiff?
    }

    static func render(_ diff: FileDiff) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let font = NSFont.monospacedSystemFont(ofSize: CGFloat(DiffMetrics.defaultSize), weight: .regular)
        let plain: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(Color.Vrai.text)]
        for hunk in diff.hunks {
            out.append(NSAttributedString(string: hunk.header + "\n", attributes: [.font: font, .foregroundColor: NSColor(Color.Vrai.textTertiary), .backgroundColor: NSColor(Color.Vrai.diffHunkBg)]))
            for line in hunk.lines {
                var attributes = plain
                let prefix: String
                switch line.kind {
                case .add:
                    prefix = "+"
                    attributes[.backgroundColor] = NSColor(Color.Vrai.diffAddBg)
                case .del:
                    prefix = "\u{2212}"
                    attributes[.backgroundColor] = NSColor(Color.Vrai.diffDelBg)
                case .context:
                    prefix = " "
                case .noNewline:
                    prefix = ""
                    attributes[.foregroundColor] = NSColor(Color.Vrai.textTertiary)
                }
                out.append(NSAttributedString(string: prefix + line.text + "\n", attributes: attributes))
            }
        }
        return out
    }
}
