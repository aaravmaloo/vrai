import SwiftUI
import VraiCore
import VraiGit

enum SyncForm {}

extension SyncForm {
    struct Sheet<Content: View, Start: View>: View {
        let title: String
        var description: String?
        var width: CGFloat = Vrai.Size.sheet
        let primary: String
        var primaryEnabled = true
        var danger = false
        var busy = false
        let onSubmit: () -> Void
        @ViewBuilder let content: () -> Content
        @ViewBuilder let footerStart: () -> Start
        @Environment(WindowModel.self) private var window
        @Environment(\.commandDraft) private var draft
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
                Text(title)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(description ?? "")
                    .accessibilityAddTraits(.isHeader)
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
                        .keyboardShortcut(.cancelAction)
                        Button {
                            if draft?.submit() == true { return }
                            if primaryEnabled, !busy { onSubmit() }
                        } label: {
                            HStack(spacing: Vrai.Space.s6) {
                                if busy { Spinner() }
                                Text(primary)
                            }
                        }
                        .buttonStyle(VraiButtonStyle(variant: danger ? .danger : .primary))
                        .keyboardShortcut(.defaultAction)
                        .disabled(!(primaryEnabled || draft?.isEdited == true) || busy)
                    }
                    .fixedSize()
                }
                .padding(.top, Vrai.Space.s4)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
            }
            .padding(Vrai.Space.s20)
            .frame(width: window.sheetWidth(width))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        }
    }
}

extension SyncForm.Sheet where Start == EmptyView {
    init(title: String, description: String? = nil, width: CGFloat = Vrai.Size.sheet, primary: String, primaryEnabled: Bool = true, danger: Bool = false, busy: Bool = false, onSubmit: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, description: description, width: width, primary: primary, primaryEnabled: primaryEnabled, danger: danger, busy: busy, onSubmit: onSubmit, content: content, footerStart: { EmptyView() })
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
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(hint ?? "")
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

        var body: some View {
            Field(label: label, hint: hint, error: error) {
                Group {
                    if secure {
                        SecureField(text: $text, prompt: Text(placeholder)) { Text(label) }
                    } else {
                        TextField(text: $text, prompt: Text(placeholder)) { Text(label) }
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(mono ? Font.Vrai.code : Font.Vrai.body)
                .autocorrectionDisabled(mono || secure)
                .focused($focused)
                .onSubmit(onSubmit)
                .accessibilityLabel(label)
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
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: Vrai.Radius.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Vrai.Radius.sm, style: .continuous)
                        .strokeBorder(focused ? Color.Vrai.focus : Color(nsColor: .separatorColor), lineWidth: focused ? Vrai.Size.line : Metrics.hairline)
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
            Toggle(label, isOn: $isOn)
            .toggleStyle(.checkbox)
            .help(description ?? "")
            .disabled(!enabled)
            .accessibilityLabel(label)
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
            Picker(label, selection: $selection) {
                ForEach(choices) { choice in
                    HStack(spacing: Vrai.Space.s6) {
                        Text(choice.label)
                            .foregroundStyle(choice.danger ? Color.Vrai.danger : Color.primary)
                        if let badge = choice.badge { badge }
                    }
                    .help(choice.description ?? "")
                    .accessibilityLabel(choice.label)
                    .tag(choice.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)
            .accessibilityLabel(label)
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
            Picker(label, selection: $selection) {
                ForEach(options) { option in
                    if let icon = option.icon {
                        Label(option.label, systemImage: icon).tag(option.value)
                    } else {
                        Text(option.label).tag(option.value)
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(label)
        }
    }

    struct Tabs<Value: Hashable>: View {
        @Binding var selection: Value
        let items: [Option<Value>]
        let label: String

        var body: some View {
            Picker(label, selection: $selection) {
                ForEach(items) { item in
                    Text(item.label).tag(item.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
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
            RewriteDisclosure(title: title, detail: detail, open: open, content: content)
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
                    .accessibilityLabel(command.display)
                    .accessibilityIdentifier("command-preview")
                if let tag = Self.riskTag(RiskTag.level(command)) {
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
                    .strokeBorder(RiskTag.level(command) == .destructive ? Color.Vrai.dangerSoft : Color.Vrai.Contrast.separator, lineWidth: Metrics.hairline)
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
            if expert { expertPreviews }
        }

        @ViewBuilder var expertPreviews: some View {
            ForEach(Array(commands.enumerated()), id: \.offset) { offset, command in
                ExpertCommandField(index: offset, command: command)
            }
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
            .overlay(RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous).strokeBorder(Color.Vrai.Contrast.separator, lineWidth: Metrics.hairline))
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
