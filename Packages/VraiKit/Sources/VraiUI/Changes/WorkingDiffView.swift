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

    var body: some View {
        let metrics = DiffMetrics(codeSize: codeSize)
        let language = SyntaxHighlighter.language(for: diff.path)
        GeometryReader { geometry in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(Array(diff.hunks.enumerated()), id: \.offset) { index, hunk in
                        Section {
                            if mode == .split {
                                ForEach(Array(IndexedSplitRow.rows(hunk).enumerated()), id: \.offset) { _, row in
                                    SelectableSplitLine(row: row, hunk: index, language: language, whitespace: whitespace, metrics: metrics, selectable: selectable, selection: selection, onClick: click)
                                        .onHover { if $0 { hoveredHunk = index } }
                                }
                            } else {
                                ForEach(Array(hunk.lines.enumerated()), id: \.offset) { offset, line in
                                    let id = LineID(hunk: index, line: offset)
                                    SelectableUnifiedLine(line: line, id: id, language: language, wrap: wrap, whitespace: whitespace, metrics: metrics, selectable: selectable && (line.kind == .add || line.kind == .del), selected: selection?.contains(id) ?? false, onClick: click)
                                        .frame(minWidth: geometry.size.width, alignment: .leading)
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
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
            }
            .onHover { if !$0 { hoveredHunk = nil } }
        }
        .background(Color.Vrai.bg)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Diff", bundle: .module))
        .accessibilityIdentifier("changes-diff")
    }

    func click(_ id: LineID) {
        let flags = NSEvent.modifierFlags
        window.changes.click(id, extending: flags.contains(.shift), toggling: flags.contains(.command))
        window.changes.listFocusRequest += 1
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
            if !first { Rectangle().fill(Color.Vrai.separator).frame(height: Metrics.hairline) }
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
    let selected: Bool
    let onClick: (LineID) -> Void
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(gutterLabel)
            .accessibilityAddTraits(selectable ? [.isButton] : [])
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("gutter-\(id.hunk)-\(id.line)")
            .accessibilityAction { if selectable { onClick(id) } }
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
    let onClick: (LineID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            side(row.old, old: true)
            Rectangle().fill(Color.Vrai.separator).frame(width: Metrics.hairline)
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
                    .accessibilityAddTraits(selectable && change ? [.isButton] : [])
                    .accessibilityIdentifier("gutter-\(hunk)-\(entry.index)")
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
