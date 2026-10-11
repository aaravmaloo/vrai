import SwiftUI
import VraiCore
import VraiGit

enum CodeRenderer {
    static func color(_ kind: HighlightToken.Kind?) -> Color? {
        switch kind {
        case .keyword: Color.Vrai.syntaxKeyword
        case .string: Color.Vrai.syntaxString
        case .number: Color.Vrai.syntaxNumber
        case .comment: Color.Vrai.syntaxComment
        case .type: Color.Vrai.syntaxType
        case .function: Color.Vrai.syntaxFunction
        case .attribute: Color.Vrai.syntaxAttribute
        case nil: nil
        }
    }

    static func attributed(_ text: String, language: String, words: [Range<Int>] = [], wordColor: Color? = nil, whitespace: Bool = false) -> AttributedString {
        if text.isEmpty { return AttributedString(" ") }
        var kinds: [HighlightToken.Kind?] = []
        var characters: [Character] = []
        for token in SyntaxHighlighter.highlight(text, language: language) {
            for character in token.text {
                characters.append(character)
                kinds.append(token.kind)
            }
        }
        var inWord = Array(repeating: false, count: characters.count)
        for range in words {
            for offset in range where offset >= 0 && offset < inWord.count { inWord[offset] = true }
        }
        var out = AttributedString()
        var run = ""
        var runKind: HighlightToken.Kind?
        var runWord = false
        var runSpace = false
        func flush() {
            guard !run.isEmpty else { return }
            var piece = AttributedString(run)
            if runSpace {
                piece.foregroundColor = Color.Vrai.textDisabled
            } else if let color = color(runKind) {
                piece.foregroundColor = color
            }
            if runWord, let wordColor { piece.backgroundColor = wordColor }
            out.append(piece)
            run = ""
        }
        for (index, character) in characters.enumerated() {
            let isSpace = whitespace && (character == " " || character == "\t")
            let shown: String = isSpace ? (character == "\t" ? "\u{2192}   " : "\u{00B7}") : String(character)
            if kinds[index] != runKind || inWord[index] != runWord || isSpace != runSpace {
                flush()
                runKind = kinds[index]
                runWord = inWord[index]
                runSpace = isSpace
            }
            run += shown
        }
        flush()
        return out
    }
}

struct DiffMetrics {
    let codeSize: Int

    var codeFont: Font {
        codeSize == Self.defaultSize ? Font.Vrai.code : Font.system(size: CGFloat(codeSize), design: .monospaced)
    }

    var numberFont: Font {
        codeSize == Self.defaultSize ? Font.Vrai.codeSmall : Font.system(size: CGFloat(codeSize - 1), design: .monospaced)
    }

    var lineHeight: CGFloat { CGFloat(codeSize) * 1.5 + Metrics.hairline * 2 }

    static let defaultSize = 12
}

struct LineNumber: View {
    let number: Int?
    let font: Font

    var body: some View {
        Text(verbatim: Metrics.codeColumn)
            .font(font)
            .hidden()
            .overlay(alignment: .trailing) {
                if let number {
                    Text(verbatim: String(number))
                        .font(font)
                        .monospacedDigit()
                        .foregroundStyle(Color.Vrai.textTertiary)
                }
            }
            .padding(.leading, Vrai.Space.s4)
            .padding(.trailing, Vrai.Space.s8)
    }
}

struct DiffView: View {
    let diff: FileDiff
    var mode: Preferences.DiffMode = .unified
    var wrap = false
    var whitespace = false
    var codeSize = DiffMetrics.defaultSize
    var onExpand: (() -> Void)?

    var body: some View {
        let metrics = DiffMetrics(codeSize: codeSize)
        let language = SyntaxHighlighter.language(for: diff.path)
        GeometryReader { geometry in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(Array(diff.hunks.enumerated()), id: \.offset) { index, hunk in
                        let hidden = hiddenLines(before: index)
                        if hidden > 0, let onExpand {
                            ExpandRow(count: hidden, action: onExpand)
                                .frame(minWidth: geometry.size.width, alignment: .leading)
                        }
                        Section {
                            if mode == .split {
                                ForEach(Array(SplitRow.rows(hunk).enumerated()), id: \.offset) { _, row in
                                    SplitLineView(row: row, language: language, whitespace: whitespace, metrics: metrics)
                                }
                            } else {
                                ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                                    UnifiedLineView(line: line, language: language, wrap: wrap, whitespace: whitespace, metrics: metrics)
                                        .frame(minWidth: geometry.size.width, alignment: .leading)
                                }
                            }
                        } header: {
                            HunkHeaderView(hunk: hunk, first: index == 0)
                                .frame(minWidth: geometry.size.width, alignment: .leading)
                        }
                    }
                }
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
            }
        }
        .background(Color.Vrai.bg)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Diff", bundle: .module))
    }

    func hiddenLines(before index: Int) -> Int {
        let hunk = diff.hunks[index]
        guard hunk.oldStart > 0 else { return 0 }
        if index == 0 { return max(0, hunk.oldStart - 1) }
        let previous = diff.hunks[index - 1]
        return max(0, hunk.oldStart - (previous.oldStart + previous.oldCount))
    }
}

struct ExpandRow: View {
    let count: Int
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Vrai.Space.s6) {
                Symbol("arrow.up.and.down", font: Font.Vrai.callout)
                Text(n(count, "unchanged line"))
                    .font(Font.Vrai.caption)
            }
            .foregroundStyle(hovering ? Color.Vrai.accentText : Color.Vrai.textTertiary)
            .padding(.horizontal, Vrai.Space.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Vrai.Size.controlSm)
            .background(Color.Vrai.bgSunken)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct HunkHeaderView: View {
    let hunk: Hunk
    let first: Bool

    var body: some View {
        Text(hunk.header)
            .font(Font.Vrai.codeSmall)
            .foregroundStyle(Color.Vrai.textTertiary)
            .lineLimit(1)
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
    }
}

struct UnifiedLineView: View {
    let line: DiffLine
    let language: String
    let wrap: Bool
    let whitespace: Bool
    let metrics: DiffMetrics

    var body: some View {
        let background = background
        HStack(alignment: .top, spacing: 0) {
            HStack(spacing: 0) {
                LineNumber(number: line.kind == .add ? nil : line.oldNumber, font: metrics.numberFont)
                LineNumber(number: line.kind == .del ? nil : line.newNumber, font: metrics.numberFont)
                Text(mark)
                    .font(metrics.codeFont)
                    .foregroundStyle(markColor)
                    .frame(width: Vrai.Space.s20)
            }
            .frame(minHeight: metrics.lineHeight)
            .background(gutter)
            Text(CodeRenderer.attributed(line.text, language: language, words: line.wordRanges, wordColor: line.kind == .add ? Color.Vrai.diffAddWord : line.kind == .del ? Color.Vrai.diffDelWord : nil, whitespace: whitespace))
                .font(metrics.codeFont)
                .foregroundStyle(line.kind == .noNewline ? Color.Vrai.textTertiary : Color.Vrai.text)
                .lineLimit(wrap ? nil : 1)
                .fixedSize(horizontal: !wrap, vertical: true)
                .padding(.trailing, Vrai.Space.s16)
                .frame(maxWidth: .infinity, minHeight: metrics.lineHeight, alignment: .leading)
                .clipped()
        }
        .background(background)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    var mark: String {
        switch line.kind {
        case .add: "+"
        case .del: "\u{2212}"
        case .context, .noNewline: ""
        }
    }

    var markColor: Color {
        switch line.kind {
        case .add: Color.Vrai.success
        case .del: Color.Vrai.danger
        default: Color.Vrai.textTertiary
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
        switch line.kind {
        case .add: Color.Vrai.diffAddGutter
        case .del: Color.Vrai.diffDelGutter
        default: Color.clear
        }
    }

    var accessibilityText: String {
        switch line.kind {
        case .add: String(localized: "Added line \(line.newNumber ?? 0): \(line.text)", bundle: .module)
        case .del: String(localized: "Removed line \(line.oldNumber ?? 0): \(line.text)", bundle: .module)
        default: line.text
        }
    }
}

struct SplitRow {
    var old: DiffLine?
    var new: DiffLine?
    var context: Bool

    static func rows(_ hunk: Hunk) -> [SplitRow] {
        var out: [SplitRow] = []
        let lines = hunk.lines.filter { $0.kind != .noNewline }
        var index = 0
        while index < lines.count {
            if lines[index].kind == .context {
                out.append(SplitRow(old: lines[index], new: lines[index], context: true))
                index += 1
                continue
            }
            var dels: [DiffLine] = []
            var adds: [DiffLine] = []
            while index < lines.count, lines[index].kind == .del { dels.append(lines[index]); index += 1 }
            while index < lines.count, lines[index].kind == .add { adds.append(lines[index]); index += 1 }
            for offset in 0..<max(dels.count, adds.count) {
                out.append(SplitRow(old: offset < dels.count ? dels[offset] : nil, new: offset < adds.count ? adds[offset] : nil, context: false))
            }
        }
        return out
    }
}

struct SplitLineView: View {
    let row: SplitRow
    let language: String
    let whitespace: Bool
    let metrics: DiffMetrics

    var body: some View {
        HStack(spacing: 0) {
            side(row.old, old: true)
            Rectangle().fill(Color.Vrai.separator).frame(width: Metrics.hairline)
            side(row.new, old: false)
        }
        .frame(minHeight: metrics.lineHeight)
    }

    @ViewBuilder func side(_ line: DiffLine?, old: Bool) -> some View {
        if let line {
            let change = !row.context
            HStack(spacing: 0) {
                LineNumber(number: old ? line.oldNumber : line.newNumber, font: metrics.numberFont)
                    .frame(maxHeight: .infinity)
                    .background(change ? (old ? Color.Vrai.diffDelGutter : Color.Vrai.diffAddGutter) : Color.clear)
                Text(CodeRenderer.attributed(line.text, language: language, words: change ? line.wordRanges : [], wordColor: old ? Color.Vrai.diffDelWord : Color.Vrai.diffAddWord, whitespace: whitespace))
                    .font(metrics.codeFont)
                    .foregroundStyle(Color.Vrai.text)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
            }
            .background(change ? (old ? Color.Vrai.diffDelBg : Color.Vrai.diffAddBg) : Color.clear)
            .frame(maxWidth: .infinity)
        } else {
            Hatch()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct Hatch: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.Vrai.bgSunken))
            var path = Path()
            let step = Vrai.Space.s6
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            context.stroke(path, with: .color(Color.Vrai.separator), lineWidth: Metrics.hairline)
        }
        .accessibilityHidden(true)
    }
}
