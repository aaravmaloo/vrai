import AppKit
import LocalAuthentication
import LocalAuthenticationEmbeddedUI
import SwiftUI
import VraiCore

struct NotchShape: Shape {
    var ear: CGFloat
    var radius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(ear, radius) }
        set {
            ear = newValue.first
            radius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(radius, (rect.height - ear) / 2, (rect.width - ear * 2) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + ear, y: rect.minY + ear), control: CGPoint(x: rect.minX + ear, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + ear, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + ear + radius, y: rect.maxY), control: CGPoint(x: rect.minX + ear, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - ear - radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - ear, y: rect.maxY - radius), control: CGPoint(x: rect.maxX - ear, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - ear, y: rect.minY + ear))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - ear, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

enum IslandStyle {
    static let drop = Animation.spring(response: 0.42, dampingFraction: 0.7)
    static let grow = Animation.spring(response: 0.6, dampingFraction: 0.68)
    static let morph = Animation.spring(response: 0.5, dampingFraction: 0.74)
    static let shrink = Animation.spring(response: 0.45, dampingFraction: 0.86)
    static let calm = Animation.Vrai.standardFast
    static let compactRadius = Vrai.Radius.lg - Vrai.Space.s2
    static let expandedRadius = Vrai.Radius.window + Vrai.Space.s8
    static let glyph = Vrai.Size.iconSm
    static let largeGlyph = Vrai.Size.iconLg + Vrai.Space.s10
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.42)
    static let fill = Color.white.opacity(0.13)
    static let fillStrong = Color.white.opacity(0.24)
    static let fillPressed = Color.white.opacity(0.32)
    static let rowLimit = 5
    static let green = Color(nsColor: .systemGreen)
    static let red = Color(nsColor: .systemRed)
    static let orange = Color(nsColor: .systemOrange)
    static let yellow = Color(nsColor: .systemYellow)
    static let pink = Color(nsColor: .systemPink)
    static let blue = Color(nsColor: .systemBlue)

    @MainActor static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || AccessibilityOverrides.reduceMotion
    }

    @MainActor static func animation(_ animation: Animation) -> Animation {
        reduceMotion ? calm : animation
    }

    static func color(_ tone: Tone?) -> Color {
        switch tone {
        case .success?: green
        case .danger?: red
        case .warning?: yellow
        case .accent?, .info?: blue
        case .neutral?, nil: primaryText
        }
    }

    static func badge(_ symbol: String, fill: Color) -> some View {
        Image(systemName: symbol)
            .resizable()
            .symbolRenderingMode(.palette)
            .foregroundStyle(primaryText, fill)
    }
}

struct BlurFade: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .blur(radius: on ? 0 : Vrai.Space.s8)
            .scaleEffect(on ? 1 : 0.92, anchor: .top)
    }
}

extension AnyTransition {
    static var island: AnyTransition {
        .modifier(active: BlurFade(on: false), identity: BlurFade(on: true))
    }
}

enum IslandStage: Equatable {
    case hidden
    case compact
    case expanded
}

struct IslandRoot: View {
    let center: IslandCenter

    var body: some View {
        ZStack(alignment: .top) {
            if let activity = center.shown {
                IslandBody(activity: activity, stage: center.stage, metrics: center.metrics, waiting: max(0, center.activities.count - 1)) { action in
                    center.perform(action, in: activity)
                }
                .onTapGesture { if !center.hoverOpens { center.peek() } }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(IslandBody.space)) } action: { center.frame = $0 }
                .onDisappear { center.frame = .zero }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(.named(IslandBody.space))
        .environment(\.colorScheme, .dark)
        .vraiAccessibility()
    }
}

struct IslandBody: View {
    nonisolated static let space = "island-panel"

    let activity: IslandActivity
    let stage: IslandStage
    let metrics: IslandMetrics
    let waiting: Int
    let perform: (IslandAction) -> Void

    var width: CGFloat {
        switch stage {
        case .hidden: metrics.notch ? metrics.notchWidth + IslandMetrics.ear * 2 : metrics.compactWidth * 0.5
        case .compact: metrics.compactWidth
        case .expanded: metrics.expandedWidth
        }
    }

    var radius: CGFloat {
        switch stage {
        case .hidden, .compact: metrics.notch ? IslandStyle.compactRadius : metrics.height / 2
        case .expanded: IslandStyle.expandedRadius
        }
    }

    var body: some View {
        let shape = NotchShape(ear: IslandMetrics.ear, radius: radius)
        VStack(spacing: 0) {
            ZStack {
                top
                    .id(activity.id)
                    .transition(.island)
            }
            .modifier(BlurFade(on: stage != .hidden))
            if stage == .expanded {
                ZStack {
                    IslandDetail(activity: activity, perform: perform)
                        .id(activity.id)
                        .transition(.island)
                }
                .transition(.island)
            }
        }
        .padding(.horizontal, IslandMetrics.ear)
        .frame(width: width, alignment: .top)
        .frame(height: stage == .hidden ? metrics.height : nil, alignment: .top)
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .opacity(stage == .hidden && !metrics.notch ? 0 : 1)
        .contentShape(shape)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("island")
        .accessibilityLabel(Text(activity.title))
    }

    var top: some View {
        HStack(spacing: Vrai.Space.s6) {
            if stage == .expanded {
                if let source = activity.source {
                    Text(source)
                        .font(Font.Vrai.captionStrong)
                        .foregroundStyle(IslandStyle.tertiaryText)
                        .lineLimit(1)
                        .padding(.leading, Vrai.Space.s6)
                }
            } else {
                IslandGlyph(activity: activity, size: IslandStyle.glyph)
                    .frame(width: Vrai.Size.icon, height: Vrai.Size.icon)
            }
            Spacer(minLength: metrics.notch ? metrics.notchWidth : 0)
            if stage != .expanded {
                trailing
                    .frame(width: Vrai.Size.icon, height: Vrai.Size.icon)
            }
        }
        .padding(.horizontal, Vrai.Space.s10)
        .frame(height: metrics.height)
    }

    @ViewBuilder var trailing: some View {
        let tint = IslandStyle.color(activity.tint)
        if let progress = activity.progress {
            ProgressRing(progress: progress, tint: tint, line: IslandStyle.glyph / 7)
                .frame(width: IslandStyle.glyph, height: IslandStyle.glyph)
                .accessibilityValue(Text(activity.badge ?? ""))
        } else if let symbol = activity.accessory ?? (activity.phase == .info || activity.phase == .paused ? nil : activity.icon) {
            Image(systemName: symbol)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: IslandStyle.glyph, height: IslandStyle.glyph)
                .foregroundStyle(activity.accessory != nil ? tint : IslandStyle.secondaryText)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
        }
    }
}

struct IslandDetail: View {
    let activity: IslandActivity
    let perform: (IslandAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Vrai.Space.s10) {
            HStack(alignment: .center, spacing: Vrai.Space.s12) {
                if activity.phase == .authenticating, let context = activity.context {
                    TouchIDGlyph(context: context)
                        .frame(width: IslandStyle.largeGlyph, height: IslandStyle.largeGlyph)
                        .accessibilityLabel(Text("Touch ID", bundle: .module))
                } else {
                    IslandGlyph(activity: activity, size: IslandStyle.largeGlyph)
                        .frame(width: IslandStyle.largeGlyph, height: IslandStyle.largeGlyph)
                }
                VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                    Text(activity.title)
                        .font(Font.Vrai.title3)
                        .foregroundStyle(IslandStyle.primaryText)
                        .lineLimit(2)
                        .accessibilityIdentifier("island.title")
                    if let detail = activity.detail {
                        Text(detail)
                            .font(Font.Vrai.callout)
                            .foregroundStyle(IslandStyle.secondaryText)
                            .lineLimit(3)
                            .accessibilityIdentifier("island.detail")
                    }
                    if activity.phase == .authenticating {
                        Text("Touch ID to confirm, or press Esc to cancel.", bundle: .module)
                            .font(Font.Vrai.caption)
                            .foregroundStyle(IslandStyle.tertiaryText)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if let progress = activity.progress, activity.phase == .running {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(IslandStyle.primaryText)
                    .controlSize(.small)
            }
            if !activity.rows.isEmpty {
                VStack(alignment: .leading, spacing: Vrai.Space.s4) {
                    ForEach(activity.rows.prefix(IslandStyle.rowLimit)) { row in
                        HStack(spacing: Vrai.Space.s8) {
                            ChecksGlyph(state: row.state, size: Vrai.Size.iconSm - Vrai.Space.s4, vivid: true)
                                .frame(width: Vrai.Size.iconSm)
                            Text(row.title)
                                .font(Font.Vrai.callout)
                                .foregroundStyle(IslandStyle.primaryText)
                                .lineLimit(1)
                            Spacer(minLength: Vrai.Space.s8)
                            if let detail = row.detail {
                                Text(detail)
                                    .font(Font.Vrai.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(IslandStyle.tertiaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                    if activity.rows.count > IslandStyle.rowLimit {
                        Text("\(activity.rows.count - IslandStyle.rowLimit) more", bundle: .module)
                            .font(Font.Vrai.caption)
                            .foregroundStyle(IslandStyle.tertiaryText)
                    }
                }
                .padding(.leading, IslandStyle.largeGlyph + Vrai.Space.s12)
            }
            if !activity.actions.isEmpty {
                HStack(spacing: Vrai.Space.s8) {
                    Spacer(minLength: 0)
                    ForEach(activity.actions) { action in
                        Button {
                            perform(action)
                        } label: {
                            Text(action.title)
                        }
                        .buttonStyle(IslandButtonStyle(prominent: action.prominent))
                        .accessibilityIdentifier("island.action." + action.title)
                    }
                }
            }
        }
        .padding(.horizontal, Vrai.Space.s16)
        .padding(.top, Vrai.Space.s4)
        .padding(.bottom, Vrai.Space.s16)
    }
}

struct IslandButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.Vrai.captionStrong)
            .foregroundStyle(IslandStyle.primaryText)
            .padding(.horizontal, Vrai.Space.s12)
            .frame(height: Vrai.Size.controlSm + Vrai.Space.s2)
            .background {
                Capsule().fill(configuration.isPressed ? IslandStyle.fillPressed : (prominent ? IslandStyle.fillStrong : IslandStyle.fill))
            }
            .contentShape(Capsule())
    }
}

struct IslandGlyph: View {
    let activity: IslandActivity
    let size: CGFloat

    var body: some View {
        Group {
            switch activity.phase {
            case .running:
                if let progress = activity.progress {
                    ProgressRing(progress: progress, tint: IslandStyle.color(activity.tint), line: size / 8)
                } else {
                    IslandSpinner(tint: IslandStyle.color(activity.tint), line: size / 8)
                }
            case .success, .authenticated:
                IslandStyle.badge("checkmark.circle.fill", fill: IslandStyle.green)
                    .symbolEffect(.bounce, value: activity.id)
            case .failure:
                IslandStyle.badge("xmark.circle.fill", fill: IslandStyle.red)
                    .symbolEffect(.bounce, value: activity.id)
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill")
                    .resizable()
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.black, IslandStyle.yellow)
            case .info, .paused:
                Image(systemName: activity.icon ?? "info.circle")
                    .resizable()
                    .foregroundStyle(IslandStyle.color(activity.tint))
                    .symbolEffect(.pulse, isActive: activity.phase == .paused)
            case .authenticating:
                Image(systemName: "touchid")
                    .resizable()
                    .foregroundStyle(IslandStyle.pink)
                    .symbolEffect(.pulse)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ProgressRing: View {
    let progress: Double
    let tint: Color
    let line: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(IslandStyle.fill, lineWidth: line)
            Circle()
                .trim(from: 0, to: max(0.04, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Animation.Vrai.standardBase, value: progress)
        }
        .padding(line / 2)
    }
}

struct IslandSpinner: View {
    let tint: Color
    let line: CGFloat
    @Environment(\.vraiReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let turn = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(reduceMotion ? 0 : turn * 360))
                .padding(line / 2)
        }
    }
}

struct TouchIDGlyph: NSViewRepresentable {
    let context: LAContext

    func makeNSView(context: Context) -> LAAuthenticationView {
        LAAuthenticationView(context: self.context, controlSize: .large)
    }

    func updateNSView(_ view: LAAuthenticationView, context: Context) {}
}
