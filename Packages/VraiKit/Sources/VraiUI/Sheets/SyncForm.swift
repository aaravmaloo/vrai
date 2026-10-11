import SwiftUI
import VraiCore
import VraiGit

enum SyncForm {}

extension SyncForm {
    struct Sheet<Content: View, Start: View>: View {
        let title: String
        var description: String?
        let icon: String
        var tone: Tone = .neutral
        var width: CGFloat = Vrai.Size.sheet
        let primary: String
        var primaryEnabled = true
        var danger = false
        var busy = false
        let onSubmit: () -> Void
        @ViewBuilder let content: () -> Content
        @ViewBuilder let footerStart: () -> Start
        @Environment(WindowModel.self) private var window
        @State private var headerHeight: CGFloat = 0
        @State private var footerHeight: CGFloat = 0
        @State private var contentHeight: CGFloat = 0

        var room: CGFloat? {
            let total = window.sync.windowHeight
            guard total > 0, headerHeight > 0, footerHeight > 0 else { return nil }
            let chrome = Vrai.Size.toolbar + Vrai.Space.s24 + headerHeight + footerHeight + Vrai.Space.s20 * 2 + Vrai.Space.s16 * 2
            return max(total - chrome, Vrai.Size.controlLg * 3)
        }

        var body: some View {
            let limit = room
            let scrolls = limit.map { contentHeight > $0 } ?? false
            VStack(alignment: .leading, spacing: Vrai.Space.s16) {
                HStack(alignment: .top, spacing: Vrai.Space.s12) {
                    RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous)
                        .fill(tone == .neutral ? Color.Vrai.fill : tone.soft)
                        .frame(width: Vrai.Space.s40, height: Vrai.Space.s40)
                        .overlay {
                            Symbol(icon, font: Font.Vrai.title1.weight(.regular))
                                .foregroundStyle(tone == .neutral ? Color.Vrai.textSecondary : tone.color)
                        }
                    VStack(alignment: .leading, spacing: Vrai.Space.s4) {
                        Text(title)
                            .font(Font.Vrai.title2)
                            .foregroundStyle(Color.Vrai.text)
                            .accessibilityAddTraits(.isHeader)
                        if let description {
                            Text(description)
                                .font(Font.Vrai.callout)
                                .foregroundStyle(Color.Vrai.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, Vrai.Space.s2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: Vrai.Space.s16) {
                        content()
                    }
                    .padding(Vrai.Size.focusHalo)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(scrolls ? .automatic : .never)
                .frame(height: contentHeight > 0 ? min(contentHeight, (limit ?? contentHeight) + Vrai.Size.focusHalo * 2) : nil)
                .padding(-Vrai.Size.focusHalo)
                HStack(spacing: Vrai.Space.s12) {
                    HStack(spacing: Vrai.Space.s8) { footerStart() }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: Vrai.Space.s8) {
                        Button {
                            window.sheets.dismiss()
                        } label: {
                            Text("Cancel", bundle: .module)
                        }
                        .buttonStyle(VraiButtonStyle(variant: .secondary))
                        .keyboardShortcut(.cancelAction)
                        Button {
                            if primaryEnabled, !busy { onSubmit() }
                        } label: {
                            HStack(spacing: Vrai.Space.s6) {
                                if busy { Spinner() }
                                Text(primary)
                            }
                        }
                        .buttonStyle(VraiButtonStyle(variant: danger ? .danger : .primary))
                        .keyboardShortcut(.defaultAction)
                        .disabled(!primaryEnabled || busy)
                    }
                    .fixedSize()
                }
                .padding(.top, Vrai.Space.s4)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
            }
            .padding(Vrai.Space.s20)
            .frame(width: width)
            .background(Color.Vrai.surface)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        }
    }
}

extension SyncForm.Sheet where Start == EmptyView {
    init(title: String, description: String? = nil, icon: String, tone: Tone = .neutral, width: CGFloat = Vrai.Size.sheet, primary: String, primaryEnabled: Bool = true, danger: Bool = false, busy: Bool = false, onSubmit: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, description: description, icon: icon, tone: tone, width: width, primary: primary, primaryEnabled: primaryEnabled, danger: danger, busy: busy, onSubmit: onSubmit, content: content, footerStart: { EmptyView() })
    }
}

extension SyncForm {
    struct Field<Content: View>: View {
        let label: String
        var hint: String?
        var error: String?
        @ViewBuilder let content: () -> Content

        var body: some View {
            VStack(alignment: .leading, spacing: Vrai.Space.s6) {
                Text(label)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.textSecondary)
                content()
                if let error {
                    HStack(spacing: Vrai.Space.s4) {
                        Symbol("exclamationmark.octagon", font: Font.Vrai.callout)
                        Text(error)
                    }
                    .font(Font.Vrai.caption)
                    .foregroundStyle(Color.Vrai.danger)
                    .fixedSize(horizontal: false, vertical: true)
                } else if let hint {
                    Text(hint)
                        .font(Font.Vrai.caption)
                        .foregroundStyle(Color.Vrai.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    struct Input: View {
        let label: String
        @Binding var text: String
        var placeholder = ""
        var hint: String?
        var error: String?
        var mono = false
        var secure = false
        var autofocus = false
        var onSubmit: () -> Void = {}
        @FocusState private var focused: Bool
        @State private var hovering = false

        var body: some View {
            Field(label: label, hint: hint, error: error) {
                Group {
                    if secure {
                        SecureField(text: $text, prompt: Text(placeholder).foregroundStyle(Color.Vrai.textTertiary)) { Text(label) }
                    } else {
                        TextField(text: $text, prompt: Text(placeholder).foregroundStyle(Color.Vrai.textTertiary)) { Text(label) }
                    }
                }
                .textFieldStyle(.plain)
                .font(mono ? Font.Vrai.code : Font.Vrai.body)
                .foregroundStyle(Color.Vrai.text)
                .autocorrectionDisabled(mono || secure)
                .focused($focused)
                .onSubmit(onSubmit)
                .accessibilityLabel(label)
                .padding(.horizontal, Vrai.Space.s8)
                .frame(height: Vrai.Size.control)
                .background(focused ? Color.Vrai.bg : Color.Vrai.fill, in: RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous)
                        .strokeBorder(error != nil ? Color.Vrai.danger : focused ? Color.Vrai.focus : (hovering ? Color.Vrai.borderStrong : Color.Vrai.border), lineWidth: Metrics.hairline)
                }
                .background {
                    if focused || error != nil {
                        RoundedRectangle(cornerRadius: Vrai.Radius.md + Vrai.Size.focusHalo, style: .continuous)
                            .fill(error != nil ? Color.Vrai.dangerSoft : Color.Vrai.accentSoftStrong)
                            .padding(-Vrai.Size.focusHalo)
                    }
                }
                .onHover { hovering = $0 }
            }
            .task {
                guard autofocus else { return }
                try? await Task.sleep(for: .milliseconds(120))
                focused = true
            }
        }
    }

    struct TextArea: View {
        let label: String
        @Binding var text: String
        var placeholder = ""
        var lines = 3
        @FocusState private var focused: Bool

        var body: some View {
            Field(label: label) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(Font.Vrai.body)
                            .foregroundStyle(Color.Vrai.textTertiary)
                            .padding(.horizontal, Vrai.Space.s4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(Font.Vrai.body)
                        .foregroundStyle(Color.Vrai.text)
                        .scrollContentBackground(.hidden)
                        .focused($focused)
                        .accessibilityLabel(label)
                }
                .padding(.vertical, Vrai.Space.s6)
                .padding(.horizontal, Vrai.Space.s4)
                .frame(height: Vrai.Space.s20 * CGFloat(lines) + Vrai.Space.s12)
                .background(focused ? Color.Vrai.bg : Color.Vrai.fill, in: RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous)
                        .strokeBorder(focused ? Color.Vrai.focus : Color.Vrai.border, lineWidth: Metrics.hairline)
                }
                .background {
                    if focused {
                        RoundedRectangle(cornerRadius: Vrai.Radius.md + Vrai.Size.focusHalo, style: .continuous)
                            .fill(Color.Vrai.accentSoftStrong)
                            .padding(-Vrai.Size.focusHalo)
                    }
                }
            }
        }
    }

    struct Checkbox: View {
        @Binding var isOn: Bool
        let label: String
        var description: String?
        var enabled = true

        var body: some View {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                    Text(label)
                        .font(Font.Vrai.body)
                        .foregroundStyle(Color.Vrai.text)
                    if let description {
                        Text(description)
                            .font(Font.Vrai.caption)
                            .foregroundStyle(Color.Vrai.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .toggleStyle(CheckboxStyle())
            .disabled(!enabled)
            .accessibilityLabel(label)
        }
    }

    struct CheckboxStyle: ToggleStyle {
        func makeBody(configuration: Configuration) -> some View {
            StyledBody(configuration: configuration)
        }

        struct StyledBody: View {
            let configuration: ToggleStyleConfiguration
            @Environment(\.isEnabled) private var enabled
            @State private var hovering = false

            var body: some View {
                Button {
                    configuration.isOn.toggle()
                } label: {
                    HStack(alignment: .top, spacing: Vrai.Space.s8) {
                        RoundedRectangle(cornerRadius: Vrai.Radius.xs, style: .continuous)
                            .fill(configuration.isOn ? Color.Vrai.accent : (hovering ? Color.Vrai.fillHover : Color.Vrai.bg))
                            .overlay {
                                if !configuration.isOn {
                                    RoundedRectangle(cornerRadius: Vrai.Radius.xs, style: .continuous)
                                        .strokeBorder(Color.Vrai.borderControl, lineWidth: Metrics.hairline)
                                }
                            }
                            .overlay {
                                if configuration.isOn {
                                    Symbol("checkmark", font: Font.Vrai.overline)
                                        .foregroundStyle(Color.Vrai.onAccent)
                                }
                            }
                            .frame(width: Vrai.Space.s16, height: Vrai.Space.s16)
                            .padding(.top, Metrics.hairline)
                        configuration.label
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(enabled ? 1 : 0.5)
                .onHover { hovering = $0 }
                .accessibilityRepresentation {
                    Toggle(isOn: configuration.$isOn) { configuration.label }
                        .toggleStyle(.checkbox)
                }
            }
        }
    }

    struct Choice<Value: Hashable>: Identifiable {
        let value: Value
        let label: String
        var description: String?
        var danger = false
        var badge: AnyView?

        var id: Value { value }
    }

    struct Radios<Value: Hashable>: View {
        @Binding var selection: Value
        let choices: [Choice<Value>]
        var cards = false
        let label: String

        var body: some View {
            VStack(alignment: .leading, spacing: Vrai.Space.s8) {
                ForEach(choices) { choice in
                    row(choice)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
        }

        func row(_ choice: Choice<Value>) -> some View {
            let on = choice.value == selection
            let tint = choice.danger ? Color.Vrai.danger : Color.Vrai.accent
            return Button {
                selection = choice.value
            } label: {
                HStack(alignment: .top, spacing: Vrai.Space.s8) {
                    Circle()
                        .fill(on ? tint : Color.Vrai.bg)
                        .overlay {
                            if !on { Circle().strokeBorder(Color.Vrai.borderControl, lineWidth: Metrics.hairline) }
                        }
                        .overlay {
                            if on {
                                Circle()
                                    .fill(Color.Vrai.onAccent)
                                    .frame(width: Vrai.Space.s6, height: Vrai.Space.s6)
                            }
                        }
                        .frame(width: Vrai.Space.s16, height: Vrai.Space.s16)
                        .padding(.top, Metrics.hairline)
                    VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                        Text(choice.label)
                            .font(cards ? Font.Vrai.headline : Font.Vrai.body)
                            .foregroundStyle(Color.Vrai.text)
                        if let description = choice.description {
                            Text(description)
                                .font(Font.Vrai.caption)
                                .foregroundStyle(Color.Vrai.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let badge = choice.badge { badge }
                }
                .padding(cards ? Vrai.Space.s12 : 0)
                .background {
                    if cards {
                        RoundedRectangle(cornerRadius: Vrai.Radius.lg, style: .continuous)
                            .fill(on ? (choice.danger ? Color.Vrai.dangerSoft : Color.Vrai.accentSoft) : Color.Vrai.bg)
                    }
                }
                .overlay {
                    if cards {
                        RoundedRectangle(cornerRadius: Vrai.Radius.lg, style: .continuous)
                            .strokeBorder(on ? tint : Color.Vrai.border, lineWidth: on ? Metrics.thinStroke : Metrics.hairline)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(choice.label)
            .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        }
    }

    struct Option<Value: Hashable>: Identifiable {
        let value: Value
        let label: String
        var icon: String?
        var detail: String?

        var id: Value { value }
    }

    struct Select<Value: Hashable>: View {
        @Binding var selection: Value
        let options: [Option<Value>]
        let label: String

        var body: some View {
            let current = options.first { $0.value == selection } ?? options.first
            Menu {
                ForEach(options) { option in
                    Button {
                        selection = option.value
                    } label: {
                        if option.value == selection {
                            Label(option.label, systemImage: "checkmark")
                        } else if let icon = option.icon {
                            Label(option.label, systemImage: icon)
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: Vrai.Space.s6) {
                    if let icon = current?.icon {
                        Symbol(icon, font: Font.Vrai.body)
                            .foregroundStyle(Color.Vrai.textSecondary)
                    }
                    Text(current?.label ?? "")
                        .font(Font.Vrai.body)
                        .foregroundStyle(Color.Vrai.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: Vrai.Space.s4)
                    Symbol("chevron.up.chevron.down", font: Font.Vrai.caption)
                        .foregroundStyle(Color.Vrai.textTertiary)
                }
                .padding(.leading, Vrai.Space.s10)
                .padding(.trailing, Vrai.Space.s6)
                .frame(height: Vrai.Size.control)
                .frame(maxWidth: .infinity)
                .background(Color.Vrai.surfaceRaised, in: RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous)
                        .strokeBorder(Color.Vrai.border, lineWidth: Metrics.hairline)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel(label)
            .accessibilityValue(current?.label ?? "")
        }
    }

    struct Tabs<Value: Hashable>: View {
        @Binding var selection: Value
        let items: [Option<Value>]
        let label: String

        var body: some View {
            HStack(spacing: Vrai.Space.s2) {
                ForEach(items) { item in
                    let on = item.value == selection
                    Button {
                        selection = item.value
                    } label: {
                        Text(item.label)
                            .font(Font.Vrai.body)
                            .foregroundStyle(on ? Color.Vrai.text : Color.Vrai.textSecondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background {
                                if on {
                                    RoundedRectangle(cornerRadius: Vrai.Radius.sm, style: .continuous)
                                        .fill(Color.Vrai.surfaceRaised)
                                        .overlay(RoundedRectangle(cornerRadius: Vrai.Radius.sm, style: .continuous).strokeBorder(Color.Vrai.border, lineWidth: Metrics.hairline / 2))
                                        .shadow(color: Color.Vrai.separator, radius: Metrics.hairline, y: Metrics.hairline)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.label)
                    .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(Vrai.Space.s2)
            .frame(height: Vrai.Size.control)
            .background(Color.Vrai.fill, in: RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous).strokeBorder(Color.Vrai.separator, lineWidth: Metrics.hairline))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
        }
    }

    struct Callout: View {
        var tone: Tone = .info
        var icon: String?
        let title: String
        var message: String?

        var body: some View {
            HStack(alignment: .top, spacing: Vrai.Space.s10) {
                Symbol(icon ?? tone.symbol, font: Font.Vrai.title3.weight(.regular))
                    .foregroundStyle(tone.color)
                VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                    Text(title)
                        .font(Font.Vrai.headline)
                        .foregroundStyle(Color.Vrai.text)
                    if let message {
                        Text(message)
                            .font(Font.Vrai.callout)
                            .foregroundStyle(Color.Vrai.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Vrai.Space.s12)
            .background(tone == .neutral ? Color.Vrai.fill : tone.soft, in: RoundedRectangle(cornerRadius: Vrai.Radius.lg, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    struct Disclosure<Content: View>: View {
        let title: String
        var detail: String?
        @State var open: Bool
        @ViewBuilder let content: () -> Content

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(Animation.Vrai.standardFast) { open.toggle() }
                } label: {
                    HStack(spacing: Vrai.Space.s6) {
                        Symbol("chevron.right", font: Font.Vrai.caption)
                            .foregroundStyle(Color.Vrai.textTertiary)
                            .rotationEffect(.degrees(open ? 90 : 0))
                        Text(title)
                            .font(Font.Vrai.headline)
                            .foregroundStyle(Color.Vrai.text)
                        Spacer(minLength: 0)
                        if let detail {
                            Text(detail)
                                .font(Font.Vrai.caption)
                                .foregroundStyle(Color.Vrai.textTertiary)
                        }
                    }
                    .padding(.horizontal, Vrai.Space.s4)
                    .frame(height: Vrai.Size.control)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(radius: Vrai.Radius.sm, hoverFill: Color.Vrai.fillHover)
                .accessibilityLabel(title)
                .accessibilityValue(open ? Text("Expanded", bundle: .module) : Text("Collapsed", bundle: .module))
                if open {
                    VStack(alignment: .leading, spacing: Vrai.Space.s12) {
                        content()
                    }
                    .padding(.top, Vrai.Space.s8)
                    .padding(.bottom, Vrai.Space.s4)
                    .padding(.leading, Vrai.Space.s20)
                }
            }
        }
    }

    struct CommandPreview: View {
        let command: GitCommand
        @State private var copied = false

        var body: some View {
            HStack(spacing: Vrai.Space.s8) {
                Text(verbatim: "$")
                    .font(Font.Vrai.codeSmall)
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .accessibilityHidden(true)
                Text(Self.styled(command.display))
                    .font(Font.Vrai.codeSmall)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .accessibilityLabel(command.display)
                    .accessibilityIdentifier("command-preview")
                if let tag = Self.riskTag(command.risk) {
                    Text(tag.label)
                        .font(Font.Vrai.captionStrong)
                        .foregroundStyle(tag.tone.color)
                        .padding(.horizontal, Vrai.Space.s6)
                        .frame(height: Vrai.Space.s16)
                        .background(tag.tone.soft, in: Capsule())
                        .fixedSize()
                }
                Button {
                    Clipboard.copy(command.display)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(IconButtonStyle(small: true))
                .help(copied ? String(localized: "Copied", bundle: .module) : String(localized: "Copy command", bundle: .module))
                .accessibilityLabel(copied ? String(localized: "Copied", bundle: .module) : String(localized: "Copy command", bundle: .module))
            }
            .padding(.leading, Vrai.Space.s10)
            .padding(.trailing, Vrai.Space.s4)
            .frame(height: Vrai.Size.control)
            .background(Color.Vrai.bgSunken, in: RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous)
                    .strokeBorder(command.risk == .destructive ? Color.Vrai.dangerSoft : Color.Vrai.separator, lineWidth: Metrics.hairline)
            }
        }

        static func riskTag(_ risk: GitCommand.Risk) -> (label: String, tone: Tone)? {
            switch risk {
            case .safe: nil
            case .rewrites: (String(localized: "Rewrites history", bundle: .module), .warning)
            case .destructive: (String(localized: "Destructive", bundle: .module), .danger)
            }
        }

        static func styled(_ text: String) -> AttributedString {
            var out = AttributedString()
            for token in CommandTokenizer.tokenize(text) {
                var run = AttributedString(token.text)
                switch token.kind {
                case .git: run.foregroundColor = Color.Vrai.textTertiary
                case .sub:
                    run.foregroundColor = Color.Vrai.text
                    run.font = Font.Vrai.codeSmall.weight(.semibold)
                case .flag: run.foregroundColor = Color.Vrai.accentText
                case .str: run.foregroundColor = Color.Vrai.syntaxString
                case .arg: run.foregroundColor = Color.Vrai.textSecondary
                case nil: break
                }
                out += run
            }
            return out
        }
    }

    struct Options<Content: View>: View {
        let commands: [GitCommand]
        var detail: String?
        var hasContent = true
        @ViewBuilder let content: () -> Content
        @Environment(Preferences.self) private var preferences

        var showsPreview: Bool { preferences.expert || preferences.commandPreviews }

        var body: some View {
            let expert = preferences.expert
            if hasContent || !expert {
                Disclosure(title: String(localized: "Options", bundle: .module), detail: detail, open: expert) {
                    content()
                    if !expert, showsPreview { previews }
                }
            }
            if expert { previews }
        }

        @ViewBuilder var previews: some View {
            ForEach(Array(commands.enumerated()), id: \.offset) { _, command in
                CommandPreview(command: command)
            }
        }
    }

    struct CommitList: View {
        let commits: [(id: OID, subject: String)]
        var total: Int
        var limit = 4

        var body: some View {
            VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                ForEach(commits.prefix(limit), id: \.id) { commit in
                    HStack(spacing: Vrai.Space.s8) {
                        Text(commit.id.short)
                            .font(Font.Vrai.codeSmall)
                            .foregroundStyle(Color.Vrai.textTertiary)
                        Text(commit.subject)
                            .font(Font.Vrai.callout)
                            .foregroundStyle(Color.Vrai.text)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, Vrai.Space.s4)
                    .frame(minHeight: Vrai.Space.s20)
                }
                if total > min(limit, commits.count) {
                    Text("and \(n(total - min(limit, commits.count), "more commit"))", bundle: .module)
                        .font(Font.Vrai.caption)
                        .foregroundStyle(Color.Vrai.textTertiary)
                        .padding(.horizontal, Vrai.Space.s4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Vrai.Space.s4)
            .background(Color.Vrai.bg, in: RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous).strokeBorder(Color.Vrai.separator, lineWidth: Metrics.hairline))
        }
    }

    static func branchNameError(_ raw: String, existing: [String], current: String? = nil) -> String? {
        let name = raw.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return nil }
        if name.contains(where: \.isWhitespace) { return String(localized: "Branch names can't contain spaces.", bundle: .module) }
        if name.firstMatch(of: #/\.\.|[~^:?*\[\\]|@\{|//|^/|/$|\.lock$|^-|\.$/#) != nil {
            return String(localized: "git won't accept that name: avoid .., ~ ^ : ? * [ \\ and a trailing slash.", bundle: .module)
        }
        if existing.contains(name), name != current { return String(localized: "A branch named \(name) already exists.", bundle: .module) }
        return nil
    }
}
