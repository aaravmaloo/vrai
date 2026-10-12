import SwiftUI
import VraiCore

enum ButtonVariant {
    case primary
    case secondary
    case plain
    case danger
}

enum ButtonSize {
    case small
    case regular
    case large

    var height: CGFloat {
        switch self {
        case .small: Vrai.Size.controlSm
        case .regular: Vrai.Size.control
        case .large: Vrai.Size.controlLg
        }
    }

    var padding: CGFloat {
        switch self {
        case .small: Vrai.Space.s8
        case .regular: Vrai.Space.s12
        case .large: Vrai.Space.s20
        }
    }

    var gap: CGFloat {
        switch self {
        case .small: Vrai.Space.s4
        case .regular: Vrai.Space.s6
        case .large: Vrai.Space.s8
        }
    }

    var radius: CGFloat {
        switch self {
        case .small: Vrai.Radius.sm
        case .regular: Vrai.Radius.md
        case .large: Vrai.Radius.full
        }
    }

    var font: Font {
        switch self {
        case .small: Font.Vrai.callout
        case .regular: Font.Vrai.body
        case .large: Font.Vrai.headline
        }
    }

    var iconFont: Font {
        switch self {
        case .small: Font.Vrai.callout
        case .regular: Font.Vrai.body
        case .large: Font.Vrai.title3
        }
    }
}

struct VraiButtonStyle: ButtonStyle {
    var variant: ButtonVariant = .secondary
    var size: ButtonSize = .regular
    var full = false

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, variant: variant, size: size, full: full)
    }

    struct StyledButton: View {
        let configuration: Configuration
        let variant: ButtonVariant
        let size: ButtonSize
        let full: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(size.font)
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, size.padding)
                .frame(maxWidth: full ? .infinity : nil)
                .frame(height: size.height)
                .background(background, in: RoundedRectangle(cornerRadius: size.radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: size.radius, style: .continuous)
                        .strokeBorder(border, lineWidth: Metrics.hairline)
                }
                .contentShape(RoundedRectangle(cornerRadius: size.radius, style: .continuous))
                .onHover { hovering = $0 }
        }

        var foreground: Color {
            guard enabled else { return Color.Vrai.textDisabled }
            switch variant {
            case .primary: return Color.Vrai.onAccent
            case .danger: return Color.Vrai.onDanger
            case .secondary, .plain: return Color.Vrai.text
            }
        }

        var background: Color {
            let pressed = configuration.isPressed
            switch variant {
            case .primary:
                guard enabled else { return Color.Vrai.fillActive }
                return pressed ? Color.Vrai.accentActive : (hovering ? Color.Vrai.accentHover : Color.Vrai.accent)
            case .danger:
                guard enabled else { return Color.Vrai.fillActive }
                return Color.Vrai.danger
            case .secondary:
                guard enabled else { return Color.clear }
                return pressed ? Color.Vrai.fillActive : (hovering ? Color.Vrai.fill : Color.Vrai.surfaceRaised)
            case .plain:
                guard enabled else { return Color.clear }
                return pressed ? Color.Vrai.fillActive : (hovering ? Color.Vrai.fillHover : Color.clear)
            }
        }

        var border: Color {
            switch variant {
            case .secondary: enabled ? Color.Vrai.Contrast.border : Color.Vrai.Contrast.separator
            default: Color.clear
            }
        }
    }
}

struct VraiButton: View {
    let title: String
    var icon: String?
    var variant: ButtonVariant = .secondary
    var size: ButtonSize = .regular
    var shortcut: String?
    var full = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: size.gap) {
                if let icon { Symbol(icon, font: size.iconFont) }
                Text(title)
                if let shortcut {
                    Text(shortcut)
                        .opacity(0.72)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(VraiButtonStyle(variant: variant, size: size, full: full))
    }
}

struct IconButtonStyle: ButtonStyle {
    var small = false
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, small: small, active: active)
    }

    struct StyledBody: View {
        let configuration: Configuration
        let small: Bool
        let active: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            let size = small ? Vrai.Size.controlSm : Vrai.Size.control
            let radius = small ? Vrai.Radius.sm : Vrai.Radius.md
            configuration.label
                .font(small ? Font.Vrai.callout : Font.Vrai.body)
                .foregroundStyle(!enabled ? Color.Vrai.textDisabled : active ? Color.Vrai.accentText : (hovering ? Color.Vrai.text : Color.Vrai.textSecondary))
                .frame(width: size, height: size)
                .background(active ? Color.Vrai.accentSoft : configuration.isPressed ? Color.Vrai.fillActive : (hovering && enabled ? Color.Vrai.fillHover : Color.clear), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

struct IconButton: View {
    let icon: String
    let label: String
    var small = false
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
        }
        .buttonStyle(IconButtonStyle(small: small, active: active))
        .help(label)
        .accessibilityLabel(label)
    }
}

struct IconMenu<Content: View>: View {
    let icon: String
    let label: String
    var small = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu(content: content) {
            Image(systemName: icon)
                .font(small ? Font.Vrai.callout : Font.Vrai.body)
                .foregroundStyle(Color.Vrai.textSecondary)
                .frame(width: small ? Vrai.Size.controlSm : Vrai.Size.control, height: small ? Vrai.Size.controlSm : Vrai.Size.control)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(IconButtonStyle(small: small))
        .menuIndicator(.hidden)
        .fixedSize()
        .help(label)
        .accessibilityLabel(label)
    }
}

struct Badge: View {
    let text: String
    var tone: Tone = .neutral
    var outline = false

    var body: some View {
        Text(text)
            .font(Font.Vrai.captionStrong)
            .monospacedDigit()
            .foregroundStyle(outline ? Color.Vrai.textSecondary : (tone == .neutral ? Color.Vrai.textSecondary : tone.color))
            .padding(.horizontal, Vrai.Space.s6)
            .frame(height: Vrai.Space.s16)
            .background(outline ? Color.clear : (tone == .neutral ? Color.Vrai.fillActive : tone.soft), in: Capsule())
            .overlay {
                if outline { Capsule().strokeBorder(Color.Vrai.Contrast.borderStrong, lineWidth: Metrics.hairline) }
            }
    }
}

struct AheadBehind: View {
    let ahead: Int
    let behind: Int

    var body: some View {
        HStack(spacing: Vrai.Space.s6) {
            if ahead > 0 {
                HStack(spacing: Metrics.hairline) {
                    Symbol("arrow.up", font: Font.Vrai.overline)
                    Text(String(ahead))
                }
                .foregroundStyle(Color.Vrai.accentText)
            }
            if behind > 0 {
                HStack(spacing: Metrics.hairline) {
                    Symbol("arrow.down", font: Font.Vrai.overline)
                    Text(String(behind))
                }
            }
        }
        .font(Font.Vrai.caption)
        .monospacedDigit()
        .foregroundStyle(Color.Vrai.textTertiary)
        .help(Self.help(ahead: ahead, behind: behind))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.help(ahead: ahead, behind: behind))
        .accessibilityAddTraits(.isStaticText)
    }

    static func help(ahead: Int, behind: Int) -> String {
        var parts: [String] = []
        if ahead > 0 { parts.append(String(localized: "\(n(ahead, "commit")) to push", bundle: .module)) }
        if behind > 0 { parts.append(String(localized: "\(n(behind, "commit")) to pull", bundle: .module)) }
        return parts.joined(separator: ", ")
    }
}

struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    var small = true
    var focusRequest: Binding<Bool>?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Vrai.Space.s6) {
            Symbol("magnifyingglass", font: small ? Font.Vrai.callout : Font.Vrai.body)
                .foregroundStyle(Color.Vrai.textTertiary)
            TextField(text: $text) {
                Text(placeholder).foregroundStyle(Color.Vrai.textTertiary)
            }
            .textFieldStyle(.plain)
            .font(Font.Vrai.body)
            .focused($focused)
            .onChange(of: focusRequest?.wrappedValue ?? false, initial: true) { _, value in
                guard value else { return }
                focused = true
                focusRequest?.wrappedValue = false
            }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Symbol("xmark.circle.fill", font: Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear", bundle: .module))
            }
        }
        .padding(.horizontal, small ? Vrai.Space.s8 : Vrai.Space.s10)
        .frame(height: small ? Vrai.Size.controlSm : Vrai.Size.control)
        .background(Color.Vrai.fill, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.Vrai.Contrast.border, lineWidth: Metrics.hairline))
        .accessibilityLabel(placeholder)
    }
}

struct EmptyStateView<Actions: View>: View {
    let icon: String
    let title: String
    var message: String?
    var small = false
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView(.vertical) { content }
                .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var content: some View {
        VStack(spacing: small ? Vrai.Space.s8 : Vrai.Space.s12) {
            Circle()
                .fill(Color.Vrai.fill)
                .frame(width: small ? Metrics.emptyIconSmall : Metrics.emptyIcon, height: small ? Metrics.emptyIconSmall : Metrics.emptyIcon)
                .overlay {
                    Symbol(icon, font: small ? Font.Vrai.title1 : Font.Vrai.display)
                        .foregroundStyle(Color.Vrai.textTertiary)
                }
                .padding(.bottom, Vrai.Space.s4)
            Text(title)
                .font(small ? Font.Vrai.title3 : Font.Vrai.title1)
                .foregroundStyle(Color.Vrai.text)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(small ? Font.Vrai.callout : Font.Vrai.body)
                    .foregroundStyle(Color.Vrai.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: Vrai.Size.sheet * 0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Vrai.Space.s8) { actions() }
                VStack(spacing: Vrai.Space.s8) { actions() }
            }
            .padding(.top, Vrai.Space.s8)
        }
        .padding(.horizontal, small ? Vrai.Space.s16 : Vrai.Space.s32)
        .padding(.vertical, small ? Vrai.Space.s24 : Vrai.Space.s40)
        .frame(maxWidth: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(icon: String, title: String, message: String? = nil, small: Bool = false) {
        self.init(icon: icon, title: title, message: message, small: small) { EmptyView() }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, min(x - spacing, width))
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        var line: [(LayoutSubview, CGSize, CGFloat)] = []
        func flush() {
            for (subview, size, originX) in line {
                subview.place(at: CGPoint(x: originX, y: y + (lineHeight - size.height) / 2), proposal: ProposedViewSize(width: size.width, height: size.height))
            }
            line.removeAll()
        }
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            size.width = min(size.width, bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX {
                flush()
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            line.append((subview, size, x))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        flush()
    }
}

struct SegmentItem<Value: Hashable>: Identifiable {
    let value: Value
    var icon: String?
    var title: String?
    let label: String

    var id: Value { value }
}

struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let items: [SegmentItem<Value>]
    var small = true

    var body: some View {
        HStack(spacing: Vrai.Space.s2) {
            ForEach(items) { item in
                let on = item.value == selection
                Button {
                    selection = item.value
                } label: {
                    HStack(spacing: Vrai.Space.s6) {
                        if let icon = item.icon { Symbol(icon, font: Font.Vrai.callout) }
                        if let title = item.title { Text(title).font(Font.Vrai.callout) }
                    }
                    .foregroundStyle(on ? Color.Vrai.text : Color.Vrai.textSecondary)
                    .padding(.horizontal, small ? Vrai.Space.s8 : Vrai.Space.s10)
                    .frame(maxHeight: .infinity)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: small ? Vrai.Radius.xs : Vrai.Radius.sm, style: .continuous)
                                .fill(Color.Vrai.surfaceRaised)
                                .overlay(RoundedRectangle(cornerRadius: small ? Vrai.Radius.xs : Vrai.Radius.sm, style: .continuous).strokeBorder(Color.Vrai.Contrast.border, lineWidth: Metrics.hairline / 2))
                                .shadow(color: Color.Vrai.separator, radius: Metrics.hairline, y: Metrics.hairline)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.label)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(Vrai.Space.s2)
        .frame(height: small ? Vrai.Size.controlSm : Vrai.Size.control)
        .background(Color.Vrai.fill, in: RoundedRectangle(cornerRadius: small ? Vrai.Radius.sm : Vrai.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: small ? Vrai.Radius.sm : Vrai.Radius.md, style: .continuous).strokeBorder(Color.Vrai.Contrast.separator, lineWidth: Metrics.hairline))
        .fixedSize()
    }
}
