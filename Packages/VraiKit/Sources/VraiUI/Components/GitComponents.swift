import AppKit
import SwiftUI
import VraiCore
import VraiGit

struct RefPillModel: Hashable, Sendable, Identifiable {
    enum Kind: Hashable, Sendable {
        case branch
        case remote
        case tag
        case head
        case good
        case bad
        case skip
    }

    var kind: Kind
    var name: String
    var lane: Int = 0
    var current = false
    var upstream: String?

    var id: String { "\(kind):\(name)" }

    var symbol: String? {
        switch kind {
        case .branch: nil
        case .remote: "cloud"
        case .tag: "tag"
        case .head: "mappin.and.ellipse"
        case .good: "checkmark.circle"
        case .bad: "xmark.circle.fill"
        case .skip: "forward.end"
        }
    }

    var accessibilityText: String {
        switch kind {
        case .branch: current ? String(localized: "branch \(name), checked out", bundle: .module) : String(localized: "branch \(name)", bundle: .module)
        case .remote: String(localized: "remote branch \(name)", bundle: .module)
        case .tag: String(localized: "tag \(name)", bundle: .module)
        case .head: name
        case .good, .bad, .skip: name
        }
    }
}

struct RefPill: View {
    let model: RefPillModel
    var small = true

    var body: some View {
        let lane = Color.Vrai.lane(model.lane)
        HStack(spacing: small ? Vrai.Space.s2 : Vrai.Space.s4) {
            if model.current, model.kind == .branch {
                Circle()
                    .fill(Color.Vrai.onLane)
                    .frame(width: Vrai.Space.s6, height: Vrai.Space.s6)
                    .padding(.trailing, Vrai.Space.s2)
            }
            if let symbol = model.symbol {
                Symbol(symbol, font: small ? Font.Vrai.caption : Font.Vrai.callout)
                    .foregroundStyle(model.kind == .tag ? Color.Vrai.textSecondary : foreground(lane))
            }
            Text(model.name)
                .font(Font.Vrai.captionStrong)
                .lineLimit(1)
                .truncationMode(.tail)
            if model.upstream != nil {
                Symbol("cloud", font: small ? Font.Vrai.caption : Font.Vrai.callout)
                    .opacity(0.85)
            }
        }
        .foregroundStyle(foreground(lane))
        .padding(.horizontal, small ? Vrai.Space.s6 : Vrai.Space.s8)
        .frame(height: small ? Metrics.pillSmall : Vrai.Size.pill)
        .background(background(lane), in: Capsule())
        .overlay { border(lane) }
        .frame(maxWidth: Vrai.Size.menu, alignment: .leading)
        .help(model.current ? String(localized: "\(model.name), checked out", bundle: .module) : model.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityText)
        .accessibilityAddTraits(.isStaticText)
    }

    func foreground(_ lane: Color) -> Color {
        switch model.kind {
        case .branch: Color.Vrai.onLane
        case .remote: lane
        case .tag: Color.Vrai.text
        case .head: Color.Vrai.accentText
        case .good: Color.Vrai.success
        case .bad: Color.Vrai.danger
        case .skip: Color.Vrai.textSecondary
        }
    }

    func background(_ lane: Color) -> Color {
        switch model.kind {
        case .branch: lane
        case .remote: lane.opacity(0.1)
        case .tag, .skip: Color.Vrai.fillActive
        case .head: Color.Vrai.accentSoft
        case .good: Color.Vrai.successSoft
        case .bad: Color.Vrai.dangerSoft
        }
    }

    @ViewBuilder func border(_ lane: Color) -> some View {
        switch model.kind {
        case .remote: Capsule().strokeBorder(lane.opacity(0.4), lineWidth: Metrics.hairline)
        case .head: Capsule().strokeBorder(Color.Vrai.accent, lineWidth: Metrics.hairline)
        default: EmptyView()
        }
    }
}

struct PillRow: Layout {
    var spacing: CGFloat = Vrai.Space.s4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let natural = subviews.map { $0.sizeThatFits(.unspecified) }
        let total = natural.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, subviews.count - 1))
        let height = natural.map(\.height).max() ?? 0
        guard let width = proposal.width else { return CGSize(width: total, height: height) }
        return CGSize(width: min(total, width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let natural = subviews.map { $0.sizeThatFits(.unspecified) }
        let total = natural.reduce(0) { $0 + $1.width }
        let gaps = spacing * CGFloat(max(0, subviews.count - 1))
        let available = max(0, bounds.width - gaps)
        let scale = total > available && total > 0 ? available / total : 1
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            let width = natural[index].width * scale
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: width, height: natural[index].height))
            x += width + spacing
        }
    }
}

struct SubjectRole: LayoutValueKey {
    static let defaultValue = 1
}

struct SubjectLayout: Layout {
    var spacing: CGFloat = Vrai.Space.s8
    var share: CGFloat = Metrics.refsShare

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let height = sizes.map(\.height).max() ?? 0
        let natural = sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, subviews.count - 1))
        return CGSize(width: proposal.width ?? natural, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let refs = subviews.first { $0[SubjectRole.self] == 0 }
        let text = subviews.first { $0[SubjectRole.self] == 1 }
        let trailing = subviews.first { $0[SubjectRole.self] == 2 }
        let gaps = spacing * CGFloat(max(0, subviews.count - 1))
        let trailingWidth = trailing?.sizeThatFits(.unspecified).width ?? 0
        let refsWidth = min(refs?.sizeThatFits(.unspecified).width ?? 0, bounds.width * share)
        let textNatural = text?.sizeThatFits(.unspecified).width ?? 0
        let textWidth = min(textNatural, max(0, bounds.width - refsWidth - trailingWidth - gaps))
        var x = bounds.minX
        if let refs {
            refs.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: refsWidth, height: nil))
            x += refsWidth + spacing
        }
        if let text {
            text.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: textWidth, height: nil))
            x += textWidth + spacing
        }
        if let trailing {
            trailing.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: .unspecified)
        }
    }
}

struct HashButton: View {
    let id: OID
    var length = 7
    var full = false
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        Button {
            Clipboard.copy(id.rawValue)
            toasts.show(Toast(message: String(localized: "Copied \(id.rawValue)", bundle: .module), icon: "doc.on.doc", timeout: Toast.brief))
        } label: {
            Text(full ? id.rawValue : String(id.rawValue.prefix(length)))
                .font(Font.Vrai.codeSmall)
                .padding(.horizontal, Vrai.Space.s4)
                .frame(height: Vrai.Space.s20)
        }
        .buttonStyle(HashButtonStyle())
        .help(String(localized: "Copy \(id.rawValue)", bundle: .module))
    }
}

struct HashButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration)
    }

    struct StyledBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(hovering ? Color.Vrai.text : Color.Vrai.textTertiary)
                .background(hovering ? Color.Vrai.fillHover : Color.clear, in: RoundedRectangle(cornerRadius: Vrai.Radius.xs, style: .continuous))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

enum Clipboard {
    @MainActor static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct SignatureBadge: View {
    let state: SignatureState
    var signer: String?
    var keyType = "SSH"
    var compact = false

    var body: some View {
        HStack(spacing: Vrai.Space.s4) {
            Symbol(symbol, font: Font.Vrai.callout)
            if !compact {
                Text(label).font(Font.Vrai.captionStrong)
            }
        }
        .foregroundStyle(tone.color)
        .help(title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isStaticText)
    }

    var symbol: String {
        switch state {
        case .verified: "checkmark.seal"
        case .bad: "xmark.seal"
        case .unknownKey: "checkmark.seal"
        case .unsigned, .unchecked: "signature"
        }
    }

    var tone: Tone {
        switch state {
        case .verified: .success
        case .bad: .danger
        case .unknownKey: .warning
        case .unsigned, .unchecked: .neutral
        }
    }

    var label: String {
        switch state {
        case .verified: String(localized: "Verified", bundle: .module)
        case .bad: String(localized: "Bad signature", bundle: .module)
        case .unknownKey: String(localized: "Unknown key", bundle: .module)
        case .unsigned, .unchecked: String(localized: "Not signed", bundle: .module)
        }
    }

    var title: String {
        switch state {
        case .verified: String(localized: "Signed with \(keyType) by \(signer ?? String(localized: "a trusted key", bundle: .module))", bundle: .module)
        case .bad: String(localized: "The signature does not match the commit", bundle: .module)
        case .unknownKey: String(localized: "Signed with \(keyType) key not in your allowed signers", bundle: .module)
        case .unsigned, .unchecked: String(localized: "This commit is not signed", bundle: .module)
        }
    }
}

struct FileStatusTile: View {
    let status: FileStatus

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Vrai.Radius.xs, style: .continuous)
                .fill(color.opacity(0.12))
                .background(Color.Vrai.bg, in: RoundedRectangle(cornerRadius: Vrai.Radius.xs, style: .continuous))
            if status == .conflicted {
                Symbol("exclamationmark.triangle.fill", font: Font.Vrai.overline)
            } else {
                Text(status.letter).font(Font.Vrai.overline)
            }
        }
        .foregroundStyle(color)
        .frame(width: Vrai.Space.s16, height: Vrai.Space.s16)
        .help(label)
        .accessibilityLabel(label)
    }

    var color: Color {
        switch status {
        case .added: Color.Vrai.statusAdded
        case .modified, .typeChanged: Color.Vrai.statusModified
        case .deleted: Color.Vrai.statusDeleted
        case .renamed, .copied: Color.Vrai.statusRenamed
        case .untracked: Color.Vrai.statusUntracked
        case .conflicted: Color.Vrai.statusConflicted
        }
    }

    var label: String {
        switch status {
        case .added: String(localized: "Added", bundle: .module)
        case .modified: String(localized: "Modified", bundle: .module)
        case .deleted: String(localized: "Deleted", bundle: .module)
        case .renamed: String(localized: "Renamed", bundle: .module)
        case .copied: String(localized: "Copied", bundle: .module)
        case .untracked: String(localized: "Untracked", bundle: .module)
        case .conflicted: String(localized: "Conflicted", bundle: .module)
        case .typeChanged: String(localized: "Type changed", bundle: .module)
        }
    }
}

struct DiffStat: View {
    let additions: Int
    let deletions: Int
    var bar = false

    var body: some View {
        HStack(spacing: Vrai.Space.s6) {
            if additions > 0 { Text("+\(additions)").foregroundStyle(Color.Vrai.success) }
            if deletions > 0 { Text("\u{2212}\(deletions)").foregroundStyle(Color.Vrai.danger) }
            if bar, additions + deletions > 0 {
                let filled = Int((Double(additions) / Double(additions + deletions) * 5).rounded())
                HStack(spacing: Metrics.hairline) {
                    ForEach(0..<5, id: \.self) { index in
                        RoundedRectangle(cornerRadius: Metrics.hairline, style: .continuous)
                            .fill(index < filled ? Color.Vrai.success : Color.Vrai.danger)
                            .frame(width: Vrai.Space.s6, height: Vrai.Space.s6)
                    }
                }
            }
        }
        .font(Font.Vrai.caption)
        .monospacedDigit()
        .fixedSize()
        .help(String(localized: "\(n(additions, "addition")), \(n(deletions, "deletion"))", bundle: .module))
    }
}

struct FileRowView: View {
    let path: String
    var oldPath: String?
    let status: FileStatus
    var additions: Int?
    var deletions: Int?
    var binary = false
    var selected = false
    var focused = true

    var body: some View {
        let parts = PathParts.split(path)
        HStack(spacing: Vrai.Space.s8) {
            FileStatusTile(status: status)
            HStack(alignment: .firstTextBaseline, spacing: Vrai.Space.s6) {
                if let oldPath {
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
                    .foregroundStyle(status == .conflicted ? Color.Vrai.statusConflicted : Color.Vrai.text)
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
            .help(oldPath.map { $0 + " \u{2192} " + path } ?? path)
            if binary {
                Text("Binary", bundle: .module)
                    .font(Font.Vrai.caption)
                    .foregroundStyle(Color.Vrai.textTertiary)
            } else if additions != nil || deletions != nil {
                DiffStat(additions: additions ?? 0, deletions: deletions ?? 0)
            }
        }
        .padding(.leading, Vrai.Space.s6)
        .padding(.trailing, Vrai.Space.s8)
        .frame(height: Vrai.Size.row)
        .contentShape(Rectangle())
        .hoverHighlight(radius: Vrai.Radius.sm, selected: selected, selectedFill: focused ? Color.Vrai.accentSoft : Color.Vrai.fillActive)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PathBar: View {
    let path: String

    var body: some View {
        let parts = path.split(separator: "/").map(String.init)
        let folders = Array(parts.dropLast())
        let file = parts.last ?? path
        ViewThatFits(in: .horizontal) {
            ForEach(0...folders.count, id: \.self) { dropped in
                PathBarRow(folders: Array(folders.dropFirst(dropped)), elided: dropped > 0, file: file, truncates: false)
                    .fixedSize()
            }
            PathBarRow(folders: [], elided: !folders.isEmpty, file: file, truncates: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(path)
        .accessibilityAddTraits(.isStaticText)
    }
}

struct PathBarRow: View {
    let folders: [String]
    let elided: Bool
    let file: String
    let truncates: Bool

    var body: some View {
        HStack(spacing: Vrai.Space.s2) {
            if elided {
                segment(Text(verbatim: "\u{2026}").font(Font.Vrai.callout).foregroundStyle(Color.Vrai.textSecondary))
                separator
            }
            ForEach(Array(folders.enumerated()), id: \.offset) { _, folder in
                segment(HStack(spacing: Vrai.Space.s4) {
                    Symbol("folder", font: Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textTertiary)
                    Text(folder)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textSecondary)
                        .lineLimit(1)
                })
                separator
            }
            segment(Text(file)
                .font(Font.Vrai.headline)
                .foregroundStyle(Color.Vrai.text)
                .lineLimit(1)
                .truncationMode(.middle))
                .layoutPriority(1)
        }
    }

    func segment(_ content: some View) -> some View {
        content
            .padding(.horizontal, Vrai.Space.s6)
            .frame(height: Vrai.Size.controlSm)
    }

    var separator: some View {
        Symbol("chevron.right", font: Font.Vrai.overline)
            .foregroundStyle(Color.Vrai.textTertiary)
    }
}

struct GraphCell: View {
    let row: GraphRow
    let lanes: Int
    let height: CGFloat
    var isWip = false
    var dim = false

    static func width(lanes: Int) -> CGFloat {
        CGFloat(max(1, lanes)) * Vrai.Size.lane + Vrai.Space.s6 * 2
    }

    var body: some View {
        Canvas { context, size in
            let pad = Vrai.Space.s6
            let lane = Vrai.Size.lane
            func x(_ index: Int) -> CGFloat { pad + CGFloat(index) * lane + lane / 2 }
            let cy = size.height / 2
            let radius = row.isMerge ? Metrics.mergeRadius : Metrics.nodeRadius
            let gap = isWip ? radius + Metrics.hairline : radius
            let style = StrokeStyle(lineWidth: Vrai.Size.line, lineCap: .round)
            func segment(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Path {
                var path = Path()
                path.move(to: CGPoint(x: x1, y: y1))
                if x1 == x2 {
                    path.addLine(to: CGPoint(x: x2, y: y2))
                } else {
                    let mid = (y1 + y2) / 2
                    path.addCurve(to: CGPoint(x: x2, y: y2), control1: CGPoint(x: x1, y: mid), control2: CGPoint(x: x2, y: mid))
                }
                return path
            }
            for segmentInfo in row.top {
                let end = segmentInfo.kind == .pass ? cy : cy - gap
                context.stroke(segment(x(segmentInfo.from), 0, x(segmentInfo.to), end), with: .color(Color.Vrai.lane(segmentInfo.color)), style: style)
            }
            for segmentInfo in row.bottom {
                if segmentInfo.kind == .pass {
                    context.stroke(segment(x(segmentInfo.from), cy, x(segmentInfo.to), size.height), with: .color(Color.Vrai.lane(segmentInfo.color)), style: style)
                } else if isWip {
                    context.stroke(segment(x(segmentInfo.from), cy + gap, x(segmentInfo.to), size.height), with: .color(Color.Vrai.textTertiary), style: StrokeStyle(lineWidth: Vrai.Size.line, lineCap: .round, dash: [Vrai.Size.line, Vrai.Size.line * 1.5]))
                } else {
                    context.stroke(segment(x(segmentInfo.from), cy + gap, x(segmentInfo.to), size.height), with: .color(Color.Vrai.lane(segmentInfo.color)), style: style)
                }
            }
            let center = CGPoint(x: x(row.lane), y: cy)
            func circle(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)) }
            let color = Color.Vrai.lane(row.color)
            if row.isHead, !isWip {
                context.stroke(circle(Metrics.haloRadius), with: .color(color.opacity(0.5)), lineWidth: Metrics.thinStroke)
            }
            if isWip {
                context.stroke(circle(radius), with: .color(Color.Vrai.textTertiary), style: StrokeStyle(lineWidth: Metrics.thinStroke, dash: [Vrai.Size.line, Vrai.Size.line]))
            } else if row.isMerge {
                context.stroke(circle(radius), with: .color(color), lineWidth: Vrai.Size.line)
            } else {
                context.fill(circle(radius), with: .color(color))
            }
        }
        .frame(width: Self.width(lanes: lanes), height: height)
        .opacity(dim ? 0.35 : 1)
        .accessibilityHidden(true)
    }
}
