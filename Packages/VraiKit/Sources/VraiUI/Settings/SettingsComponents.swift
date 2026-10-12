import SwiftUI
import VraiCore
import VraiGit

struct SettingsNarrowKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var settingsNarrow: Bool {
        get { self[SettingsNarrowKey.self] }
        set { self[SettingsNarrowKey.self] = newValue }
    }
}

enum SettingsMetrics {
    static let narrowBelow = Vrai.Size.sheet + Vrai.Space.s40
    static let field = Vrai.Size.field - Vrai.Space.s64
    static let fieldNarrow = Vrai.Size.field - Vrai.Space.s64 - Vrai.Space.s40
    static let scopeColumn = Vrai.Space.s64 + Vrai.Space.s8
    static let previewDiff = Vrai.Space.s64 * 2 + Vrai.Space.s24
    static let width = Vrai.Size.sheetWide
    static let height = Vrai.Size.sheet - Vrai.Space.s24
}

struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Form {
            content()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.Vrai.bg)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String?
    var description: String?
    var footer: String?
    var top: AnyView?
    @ViewBuilder var content: () -> Content

    init(_ title: String?, description: String? = nil, footer: String? = nil, top: AnyView? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.description = description
        self.footer = footer
        self.top = top
        self.content = content
    }

    var body: some View {
        Section {
            content()
        } header: {
            if title != nil || description != nil || top != nil {
                VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                    if let top {
                        top
                            .padding(.bottom, Vrai.Space.s16)
                    }
                    if let title {
                        Text(title)
                            .font(Font.Vrai.title3)
                            .foregroundStyle(Color.Vrai.text)
                            .accessibilityAddTraits(.isHeader)
                    }
                    if let description {
                        Text(description)
                            .font(Font.Vrai.callout)
                            .foregroundStyle(Color.Vrai.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .textCase(nil)
            }
        } footer: {
            if let footer {
                Text(footer)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct SettingsLabel: View {
    let title: String
    var description: String?
    var icon: String?
    var badge: String?
    var mono = false

    var body: some View {
        HStack(alignment: .top, spacing: Vrai.Space.s10) {
            if let icon {
                Symbol(icon, font: Font.Vrai.title3.weight(.regular))
                    .foregroundStyle(Color.Vrai.accentText)
                    .frame(width: Vrai.Space.s20)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                HStack(spacing: Vrai.Space.s6) {
                    Text(title)
                        .font(mono ? Font.Vrai.code : Font.Vrai.body)
                        .foregroundStyle(Color.Vrai.text)
                        .lineLimit(2)
                    if let badge { Badge(text: badge, tone: .accent) }
                }
                if let description {
                    Text(description)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    var description: String?
    var icon: String?
    var badge: String?
    var mono = false
    var stacked = false
    @ViewBuilder var control: () -> Control

    init(_ title: String, description: String? = nil, icon: String? = nil, badge: String? = nil, mono: Bool = false, stacked: Bool = false, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.description = description
        self.icon = icon
        self.badge = badge
        self.mono = mono
        self.stacked = stacked
        self.control = control
    }

    var body: some View {
        if stacked {
            VStack(alignment: .leading, spacing: Vrai.Space.s8) {
                SettingsLabel(title: title, description: description, icon: icon, badge: badge, mono: mono)
                control()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Vrai.Space.s2)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Vrai.Space.s12) {
                SettingsLabel(title: title, description: description, icon: icon, badge: badge, mono: mono)
                Spacer(minLength: Vrai.Space.s12)
                control()
            }
            .padding(.vertical, Vrai.Space.s2 / 2)
        }
    }
}

extension SettingsRow where Control == EmptyView {
    init(_ title: String, description: String? = nil, icon: String? = nil) {
        self.init(title, description: description, icon: icon) { EmptyView() }
    }
}

struct SettingsSwitch: View {
    let label: String
    let isOn: Bool
    var id: String?
    var disabled = false
    let set: (Bool) -> Void

    var body: some View {
        Toggle(label, isOn: Binding(get: { isOn }, set: { set($0) }))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(disabled)
            .accessibilityLabel(label)
            .accessibilityIdentifier(id ?? label)
            .accessibilityAction {
                guard !disabled else { return }
                set(!isOn)
            }
    }
}

struct SettingsOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var detail: String?

    var id: Value { value }
}

struct SettingsSelect<Value: Hashable>: View {
    let label: String
    let options: [SettingsOption<Value>]
    let selection: Value
    var id: String?
    var disabled = false
    let set: (Value) -> Void

    var body: some View {
        Picker(label, selection: Binding(get: { selection }, set: { set($0) })) {
            ForEach(options) { option in
                Text(option.detail.map { option.label + ", " + $0 } ?? option.label).tag(option.value)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .disabled(disabled)
        .accessibilityIdentifier(id ?? label)
    }
}

struct SettingsSegments<Value: Hashable>: View {
    let label: String
    let items: [SegmentItem<Value>]
    let selection: Value
    var id: String?
    let set: (Value) -> Void

    var body: some View {
        SegmentedControl(selection: Binding(get: { selection }, set: { set($0) }), items: items, small: false)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
            .accessibilityIdentifier(id ?? label)
    }
}

struct SettingsSlider: View {
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    let step: Int
    let format: (Int) -> String
    var id: String?
    let set: (Int) -> Void

    var body: some View {
        HStack(spacing: Vrai.Space.s12) {
            Slider(value: Binding(get: { Double(value) }, set: { change($0) }), in: Double(range.lowerBound)...Double(range.upperBound)) {
                Text(label)
            }
            .labelsHidden()
            .controlSize(.small)
            .accessibilityValue(format(value))
            .accessibilityIdentifier(id ?? label)
            Text(format(value))
                .font(Font.Vrai.callout)
                .monospacedDigit()
                .foregroundStyle(Color.Vrai.textSecondary)
                .frame(minWidth: Vrai.Space.s40, alignment: .trailing)
        }
    }

    func change(_ raw: Double) {
        let next = min(max(Int((raw / Double(step)).rounded()) * step, range.lowerBound), range.upperBound)
        if next != value { set(next) }
    }
}

struct CommitField: View {
    let value: String
    let label: String
    var placeholder = ""
    var mono = false
    var small = false
    var width: CGFloat?
    var id: String?
    var validate: ((String) -> String?)?
    let onCommit: (String) -> Void
    @State private var draft = ""
    @State private var loaded = false
    @FocusState private var focused: Bool
    @Environment(\.settingsNarrow) private var narrow

    var error: String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != value, let validate else { return nil }
        return validate(trimmed)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: Vrai.Space.s2) {
            TextField(label, text: $draft, prompt: placeholder.isEmpty ? nil : Text(placeholder))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .font(mono ? (small ? Font.Vrai.codeSmall : Font.Vrai.code) : (small ? Font.Vrai.callout : Font.Vrai.body))
                .controlSize(small ? .small : .regular)
                .focused($focused)
                .onSubmit(commit)
                .onKeyPress(.escape) {
                    draft = value
                    focused = false
                    return .handled
                }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
                .accessibilityLabel(label)
                .accessibilityIdentifier(id ?? label)
            if let error {
                Text(error)
                    .font(Font.Vrai.caption)
                    .foregroundStyle(Tone.danger.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.trailing)
            }
        }
        .frame(maxWidth: width ?? (narrow ? SettingsMetrics.fieldNarrow : SettingsMetrics.field))
        .onAppear {
            guard !loaded else { return }
            loaded = true
            draft = value
        }
        .onChange(of: value) { previous, next in
            if !focused || draft == previous { draft = next }
        }
    }

    func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != value else {
            draft = value
            return
        }
        if let validate, validate(trimmed) != nil {
            draft = value
            return
        }
        onCommit(trimmed)
    }
}

struct SettingsCallout<Action: View>: View {
    let tone: Tone
    let title: String
    var message: String?
    var icon: String?
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(alignment: .top, spacing: Vrai.Space.s10) {
            Symbol(icon ?? tone.symbol, font: Font.Vrai.title3)
                .foregroundStyle(tone == .neutral ? Color.Vrai.textSecondary : tone.color)
            VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                Text(title)
                    .font(Font.Vrai.headline)
                    .foregroundStyle(Color.Vrai.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                action()
                    .padding(.top, Vrai.Space.s4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Vrai.Space.s12)
        .background(tone == .neutral ? Color.Vrai.fill : tone.soft, in: RoundedRectangle(cornerRadius: Vrai.Radius.lg, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

extension SettingsCallout where Action == EmptyView {
    init(tone: Tone, title: String, message: String? = nil, icon: String? = nil) {
        self.init(tone: tone, title: title, message: message, icon: icon) { EmptyView() }
    }
}

struct SettingsNotice: View {
    let icon: String
    let title: String
    var message: String?

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                EmptyStateView(icon: icon, title: title, message: message, small: true)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .background(Color.Vrai.bg)
    }
}

enum SettingsCopy {
    static func stored(in file: String, as keys: [String]) -> String {
        String(localized: "Stored in \(file) as \(SettingsCopy.list(keys)).", bundle: .module)
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + String(localized: " and ", bundle: .module) + (items.last ?? "")
        }
    }

    static func trimmed(_ path: String) -> String {
        var value = path
        while value.count > 1, value.hasSuffix("/") { value.removeLast() }
        return value
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}
