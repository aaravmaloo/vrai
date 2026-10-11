import SwiftUI
import VraiCore
import VraiGit

public enum Tone: Sendable, Hashable {
    case neutral
    case accent
    case info
    case success
    case warning
    case danger

    var color: Color {
        switch self {
        case .neutral: Color.Vrai.textSecondary
        case .accent, .info: Color.Vrai.accentText
        case .success: Color.Vrai.success
        case .warning: Color.Vrai.warning
        case .danger: Color.Vrai.danger
        }
    }

    var soft: Color {
        switch self {
        case .neutral: Color.Vrai.bgSubtle
        case .accent, .info: Color.Vrai.accentSoft
        case .success: Color.Vrai.successSoft
        case .warning: Color.Vrai.warningSoft
        case .danger: Color.Vrai.dangerSoft
        }
    }

    var symbol: String {
        switch self {
        case .info, .neutral, .accent: "info.circle"
        case .success: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        case .danger: "exclamationmark.octagon"
        }
    }
}

enum Metrics {
    static let hairline = Vrai.Size.line / 2
    static let overlineTracking = Vrai.Size.line * 0.3
    static let pillSmall = Vrai.Space.s16
    static let nodeRadius = Vrai.Size.node / 2
    static let mergeRadius = Vrai.Size.node / 2 - Vrai.Size.line / 8
    static let haloRadius = Vrai.Space.s8
    static let thinStroke = Vrai.Size.line * 0.75
    static let codeColumn = "8888"
    static let refsShare = 0.6
    static let refsShareNarrow = 0.42
    static let bodyMaxHeight = Vrai.Space.s64 + Vrai.Space.s24
    static let emptyIcon = Vrai.Space.s64 + Vrai.Space.s8
    static let emptyIconSmall = Vrai.Space.s48
    static let kvKey = Vrai.Space.s64 + Vrai.Space.s16
    static let kvKeyNarrow = Vrai.Space.s64
    static let barHeight = Vrai.Size.control + Vrai.Space.s16
    static let paneBarHeight = Vrai.Size.control + Vrai.Space.s8
    static let hunkHeight = Vrai.Size.control + Vrai.Space.s4
    static let toolbarButton = Vrai.Size.toolbarItem - Vrai.Space.s4
    static let toolbarButtonMin = Vrai.Size.toolbarItem + Vrai.Space.s4
    static let bannerHeight = Vrai.Size.control + Vrai.Space.s16
    static let narrowFiles = Vrai.Space.s64 * 2.5
    static let mediumFiles = Vrai.Size.filelist - Vrai.Space.s64
    static let switchWidth = Vrai.Space.s24
    static let toastMax = Vrai.Size.sheet - Vrai.Space.s40
    static let loadingMeta = Vrai.Space.s64
    static let welcomeMark = Vrai.Space.s64 + Vrai.Space.s16
    static let headlineLine = Vrai.Space.s16 + Vrai.Space.s2
    static let calloutLine = Vrai.Space.s16
    static let compactTitle = Vrai.Space.s64 + Vrai.Space.s48
}

public enum WidthClass: Int, Comparable, Sendable {
    case compact
    case narrow
    case medium
    case regular
    case wide

    public static func < (lhs: WidthClass, rhs: WidthClass) -> Bool { lhs.rawValue < rhs.rawValue }

    public static let compactBelow = Vrai.Size.sheet - Vrai.Space.s40
    public static let narrowBelow = Vrai.Size.sheetWide
    public static let mediumBelow = Vrai.Size.sheetWide + Vrai.Space.s64 * 3
    public static let wideFrom = Vrai.Size.sidebar + Vrai.Size.inspector + Vrai.Size.sheet

    public init(width: CGFloat) {
        if width < Self.compactBelow { self = .compact }
        else if width < Self.narrowBelow { self = .narrow }
        else if width < Self.mediumBelow { self = .medium }
        else if width < Self.wideFrom { self = .regular }
        else { self = .wide }
    }

    public var isNarrow: Bool { self <= .narrow }
}

struct WidthClassKey: EnvironmentKey {
    static let defaultValue = WidthClass.wide
}

struct NowKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

struct ExpertKey: EnvironmentKey {
    static let defaultValue = false
}

struct CaptureModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var widthClass: WidthClass {
        get { self[WidthClassKey.self] }
        set { self[WidthClassKey.self] = newValue }
    }

    var vraiNow: Date? {
        get { self[NowKey.self] }
        set { self[NowKey.self] = newValue }
    }

    var expert: Bool {
        get { self[ExpertKey.self] }
        set { self[ExpertKey.self] = newValue }
    }

    var captureMode: Bool {
        get { self[CaptureModeKey.self] }
        set { self[CaptureModeKey.self] = newValue }
    }
}

extension View {
    func overline() -> some View {
        font(Font.Vrai.overline).tracking(Metrics.overlineTracking)
    }

    func hairline(_ edge: Edge) -> some View {
        overlay(alignment: edge.alignment) {
            Rectangle()
                .fill(Color.Vrai.separator)
                .frame(width: edge.isHorizontal ? Metrics.hairline : nil, height: edge.isHorizontal ? nil : Metrics.hairline)
        }
    }
}

extension Edge {
    var alignment: Alignment {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    var isHorizontal: Bool { self == .leading || self == .trailing }
}

struct Symbol: View {
    let name: String
    var font: Font = Font.Vrai.body

    init(_ name: String, font: Font = Font.Vrai.body) {
        self.name = name
        self.font = font
    }

    var body: some View {
        Image(systemName: name)
            .font(font)
            .accessibilityHidden(true)
    }
}

struct HoverHighlight: ViewModifier {
    var radius: CGFloat
    var selected: Bool
    var selectedFill: Color
    var hoverFill: Color = Color.Vrai.fill
    @State private var hovering = false
    @Environment(\.captureMode) private var capture

    func body(content: Content) -> some View {
        content
            .background(selected ? selectedFill : (hovering && !capture ? hoverFill : Color.clear), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverHighlight(radius: CGFloat = Vrai.Radius.sm, selected: Bool = false, selectedFill: Color = Color.Vrai.accentSoft, hoverFill: Color = Color.Vrai.fill) -> some View {
        modifier(HoverHighlight(radius: radius, selected: selected, selectedFill: selectedFill, hoverFill: hoverFill))
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = Vrai.Space.s20

    var body: some View {
        Circle()
            .fill(Color.Vrai.fillActive)
            .overlay(Circle().strokeBorder(Color.Vrai.separator, lineWidth: Metrics.hairline))
            .overlay {
                Text(Self.initial(name))
                    .font(Font.Vrai.overline)
                    .foregroundStyle(Color.Vrai.textSecondary)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    static func initial(_ name: String) -> String {
        let letters = name.split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "-" || $0 == "_" }).compactMap(\.first)
        return letters.first.map { String($0).uppercased() } ?? "?"
    }
}

struct Spinner: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .accessibilityLabel(Text("Loading", bundle: .module))
    }
}

extension RelativeDate {
    @MainActor static func text(_ date: Date, now: Date?) -> String {
        ago(date, now: now ?? Date())
    }
}

extension OID {
    func display(expert: Bool) -> String { short(expert: expert) }
}

enum PathText {
    static func abbreviated(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        var trimmed = home
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed.removeLast() }
        if path == trimmed { return "~" }
        if path.hasPrefix(trimmed + "/") { return "~" + path.dropFirst(trimmed.count) }
        return path
    }

    static func remoteDetail(_ url: String) -> String {
        var value = url
        for prefix in ["git@", "https://", "http://", "ssh://", "git://", "file://"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }
        if value.hasSuffix(".git") { value.removeLast(4) }
        if !value.hasPrefix("/"), let colon = value.firstIndex(of: ":") { value.replaceSubrange(colon...colon, with: "/") }
        return abbreviated(value)
    }
}
