import AppKit
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

    var gap: CGFloat {
        switch self {
        case .small: Vrai.Space.s4
        case .regular: Vrai.Space.s6
        case .large: Vrai.Space.s8
        }
    }

    var control: ControlSize {
        switch self {
        case .small: .small
        case .regular: .regular
        case .large: .large
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

struct VraiButtonStyle: PrimitiveButtonStyle {
    var variant: ButtonVariant = .secondary
    var size: ButtonSize = .regular
    var full = false

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        let button = Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .lineLimit(1)
                .frame(maxWidth: full ? .infinity : nil)
        }
        .controlSize(size.control)
        switch variant {
        case .primary: button.buttonStyle(.glassProminent)
        case .danger: button.buttonStyle(.glassProminent).tint(Color.Vrai.danger)
        case .secondary: button.buttonStyle(.glass)
        case .plain: button.buttonStyle(.borderless)
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

struct IconButtonStyle: PrimitiveButtonStyle {
    var small = false
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        let size = small ? Vrai.Size.controlSm : Vrai.Size.control
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .frame(minWidth: size, minHeight: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .controlSize(small ? .small : .regular)
        .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
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
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .controlSize(small ? .small : .regular)
        .foregroundStyle(.secondary)
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
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        HStack(spacing: Vrai.Space.s6) {
            if ahead > 0 {
                HStack(spacing: Metrics.hairline) {
                    Symbol("arrow.up", font: Font.Vrai.overline)
                    Text(String(ahead))
                }
                .foregroundStyle(prominence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.Vrai.accentText))
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

struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var small = true
    var focusRequest: Binding<Bool>?

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.controlSize = small ? .small : .regular
        field.font = .systemFont(ofSize: NSFont.systemFontSize(for: field.controlSize))
        field.sendsSearchStringImmediately = true
        field.setAccessibilityLabel(placeholder)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
        if let focusRequest, focusRequest.wrappedValue {
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
                focusRequest.wrappedValue = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
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
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            if let message { Text(message) }
        } actions: {
            actions()
        }
        .controlSize(small ? .small : .regular)
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
        Picker(selection: $selection) {
            ForEach(items) { item in
                segment(item)
                    .help(item.label)
                    .tag(item.value)
            }
        } label: {
            EmptyView()
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(small ? .small : .regular)
        .fixedSize()
    }

    @ViewBuilder func segment(_ item: SegmentItem<Value>) -> some View {
        if let icon = item.icon, let title = item.title {
            Label(title, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .accessibilityLabel(item.label)
        } else if let icon = item.icon {
            Image(systemName: icon)
                .accessibilityLabel(item.label)
        } else {
            Text(item.title ?? item.label)
                .accessibilityLabel(item.label)
        }
    }
}
