import SwiftUI
import VraiCore
import VraiGit

struct RewriteSheet<Content: View, FooterStart: View, Actions: View>: View {
    let title: String
    var description: String?
    var width: CGFloat = Vrai.Size.sheet
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footerStart: () -> FooterStart
    @ViewBuilder let actions: () -> Actions
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
            Text(title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
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
                HStack(spacing: Vrai.Space.s8) {
                    footerStart()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Vrai.Space.s8) {
                    actions()
                }
                .fixedSize()
            }
            .padding(.top, Vrai.Space.s4)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
        }
        .padding(Vrai.Space.s20)
        .frame(width: window.sheetWidth(width), alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

extension RewriteSheet where FooterStart == EmptyView {
    init(title: String, description: String? = nil, width: CGFloat = Vrai.Size.sheet, @ViewBuilder content: @escaping () -> Content, @ViewBuilder actions: @escaping () -> Actions) {
        self.init(title: title, description: description, width: width, content: content, footerStart: { EmptyView() }, actions: actions)
    }
}

struct RewriteFoot: View {
    let label: String
    var variant: ButtonVariant = .primary
    var disabled = false
    var busy = false
    var identifier: String?
    let cancel: () -> Void
    let action: () -> Void
    @Environment(\.commandDraft) private var draft

    var body: some View {
        Button(action: cancel) {
            Text("Cancel", bundle: .module)
        }
        .keyboardShortcut(.cancelAction)
        Button {
            if draft?.submit() == true { return }
            action()
        } label: {
            HStack(spacing: Vrai.Space.s6) {
                if busy { Spinner() }
                Text(label)
            }
        }
        .buttonStyle(VraiButtonStyle(variant: variant))
        .keyboardShortcut(.defaultAction)
        .disabled((disabled && draft?.isEdited != true) || busy)
        .accessibilityIdentifier(identifier ?? label)
    }
}

struct RewriteField<Content: View>: View {
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
                    Symbol("exclamationmark.octagon", font: Font.Vrai.caption)
                    Text(error)
                }
                .font(Font.Vrai.caption)
                .foregroundStyle(Color.Vrai.danger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(hint ?? "")
    }
}

struct RewriteTextField: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var mono = false
    var error: String?
    var hint: String?
    var autofocus = false
    var identifier: String?
    @FocusState private var focused: Bool

    var body: some View {
        RewriteField(label: label, hint: hint, error: error) {
            TextField(label, text: $text, prompt: placeholder.isEmpty ? nil : Text(placeholder))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(mono ? Font.Vrai.code : Font.Vrai.body)
                .focused($focused)
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier ?? label)
            .onAppear { if autofocus { focused = true } }
        }
    }
}

struct RewriteOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var icon: String?

    var id: Value { value }
}

struct RewriteSelect<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [RewriteOption<Value>]
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
        .accessibilityIdentifier(label)
    }
}

struct RewriteCallout: View {
    let tone: Tone
    let title: String
    var message: String?
    var icon: String?

    var body: some View {
        HStack(alignment: .top, spacing: Vrai.Space.s10) {
            Symbol(icon ?? tone.symbol, font: Font.Vrai.title3)
                .foregroundStyle(tone == .neutral ? Color.Vrai.textSecondary : tone.color)
                .padding(.top, -Vrai.Space.s2)
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Vrai.Space.s12)
        .background(tone == .neutral ? Color.Vrai.fill : tone.soft, in: RoundedRectangle(cornerRadius: Vrai.Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct RewriteCheckbox<Label: View>: View {
    @Binding var isOn: Bool
    var description: String?
    @ViewBuilder let label: () -> Label

    var body: some View {
        Toggle(isOn: $isOn, label: label)
            .toggleStyle(.checkbox)
            .help(description ?? "")
    }
}

extension RewriteCheckbox where Label == Text {
    init(_ title: String, isOn: Binding<Bool>, description: String? = nil) {
        self.init(isOn: isOn, description: description) { Text(title) }
    }
}

struct RewriteRadioOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var description: String?
    var danger = false

    var id: Value { value }
}

struct RewriteRadioCards<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [RewriteRadioOption<Value>]
    let label: String

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(options) { option in
                Text(option.label)
                    .foregroundStyle(option.danger ? Color.Vrai.danger : Color.primary)
                    .help(option.description ?? "")
                    .accessibilityIdentifier(option.label)
                    .tag(option.value)
            }
        }
        .labelsHidden()
        .pickerStyle(.radioGroup)
        .accessibilityLabel(label)
    }
}

struct RewriteDisclosure<Content: View>: View {
    let title: String
    var detail: String?
    @State var open: Bool
    @ViewBuilder let content: () -> Content

    init(title: String, detail: String? = nil, open: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.detail = detail
        _open = State(initialValue: open)
        self.content = content
    }

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: Vrai.Space.s8) {
                content()
            }
            .padding(.top, Vrai.Space.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack(spacing: Vrai.Space.s8) {
                Text(title)
                    .font(.headline)
                Spacer(minLength: Vrai.Space.s8)
                if let detail, !open {
                    Text(detail)
                        .font(Font.Vrai.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { open.toggle() } }
        }
        .accessibilityLabel(title)
    }
}

struct RewriteCommandPreview: View {
    let command: GitCommand
    var risk: GitCommand.Risk?
    @State private var copied = false

    var body: some View {
        let level = RiskTag.level(command, at: risk)
        HStack(spacing: Vrai.Space.s8) {
            Text(verbatim: "$")
                .font(Font.Vrai.codeSmall)
                .foregroundStyle(Color.Vrai.textTertiary)
                .accessibilityHidden(true)
            Text(Self.tokens(command.display))
                .font(Font.Vrai.codeSmall)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(command.display)
                .accessibilityIdentifier("command-preview")
            if level != .safe {
                Text(level == .destructive ? String(localized: "Destructive", bundle: .module) : String(localized: "Rewrites history", bundle: .module))
                    .font(Font.Vrai.captionStrong)
                    .foregroundStyle(level == .destructive ? Color.Vrai.danger : Color.Vrai.warning)
                    .padding(.horizontal, Vrai.Space.s6)
                    .frame(height: Vrai.Space.s16)
                    .background(level == .destructive ? Color.Vrai.dangerSoft : Color.Vrai.warningSoft, in: Capsule())
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
        .overlay(RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous).strokeBorder(level == .destructive ? Color.Vrai.dangerSoft : Color.Vrai.Contrast.separator, lineWidth: Metrics.hairline))
    }

    static func tokens(_ display: String) -> AttributedString {
        var out = AttributedString()
        var seenGit = false
        var seenSub = false
        for match in display.matches(of: /"[^"]*"|'[^']*'|\S+|\s+/) {
            let token = String(match.output)
            var piece = AttributedString(token)
            if token.allSatisfy(\.isWhitespace) {
                out.append(piece)
                continue
            }
            if !seenGit, token == "git" {
                seenGit = true
                piece.foregroundColor = Color.Vrai.textTertiary
            } else if seenGit, !seenSub, !token.hasPrefix("-") {
                seenSub = true
                piece.foregroundColor = Color.Vrai.text
                piece.font = Font.Vrai.codeStrong
            } else if token.hasPrefix("\"") || token.hasPrefix("'") {
                piece.foregroundColor = Color.Vrai.syntaxString
            } else if token.hasPrefix("-") {
                piece.foregroundColor = Color.Vrai.accentText
            } else {
                piece.foregroundColor = Color.Vrai.textSecondary
            }
            out.append(piece)
        }
        return out
    }
}

struct RewriteOptions<Content: View>: View {
    let command: GitCommand
    var risk: GitCommand.Risk?
    var detail: String?
    var hasContent = true
    @ViewBuilder let content: () -> Content
    @Environment(Preferences.self) private var preferences

    var body: some View {
        let expert = preferences.expert
        let showCommand = expert || preferences.commandPreviews
        if hasContent || !expert {
            RewriteDisclosure(title: String(localized: "Options", bundle: .module), detail: detail, open: expert) {
                content()
                if !expert, showCommand { RewriteCommandPreview(command: command, risk: risk) }
            }
        }
        if expert { ExpertCommandField(index: 0, command: command, risk: risk) }
    }
}

extension RewriteOptions where Content == EmptyView {
    init(command: GitCommand, risk: GitCommand.Risk? = nil, detail: String? = nil) {
        self.init(command: command, risk: risk, detail: detail, hasContent: false) { EmptyView() }
    }
}

struct RewriteCommitList: View {
    let commits: [PreviewCommit]
    var total: Int?
    var max = 6
    @Environment(\.expert) private var expert

    var body: some View {
        let shown = Array(commits.prefix(max))
        let more = (total ?? commits.count) - shown.count
        VStack(alignment: .leading, spacing: Vrai.Space.s2) {
            ForEach(shown) { commit in
                HStack(spacing: Vrai.Space.s8) {
                    Text(commit.id.short(expert: expert))
                        .font(Font.Vrai.codeSmall)
                        .foregroundStyle(Color.Vrai.textTertiary)
                    Text(commit.subject)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Metrics.hairline)
            }
            if more > 0 {
                Text("and \(n(more, "more commit"))", bundle: .module)
                    .font(Font.Vrai.caption)
                    .foregroundStyle(Color.Vrai.textTertiary)
            }
        }
        .padding(Vrai.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Vrai.bg, in: RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous).strokeBorder(Color.Vrai.Contrast.separator, lineWidth: Metrics.hairline))
    }
}

enum RewriteRefOptions {
    @MainActor static func build(_ snapshot: RepositorySnapshot?, includeHead: Bool = false, includeRemotes: Bool = false, includeTags: Bool = false, exclude: String? = nil, commit: PreviewCommit? = nil) -> [RewriteOption<String>] {
        guard let snapshot else { return [] }
        var out: [RewriteOption<String>] = []
        let current = snapshot.head.branchName
        if includeHead {
            let label = current.map { String(localized: "\($0) (current)", bundle: .module) } ?? String(localized: "HEAD at \(snapshot.headOID?.short ?? "")", bundle: .module)
            out.append(RewriteOption(value: "HEAD", label: label, icon: "mappin.and.ellipse"))
        }
        if let commit {
            out.append(RewriteOption(value: commit.id.rawValue, label: commit.id.short + " " + commit.subject, icon: "smallcircle.filled.circle"))
        }
        for branch in snapshot.branches.map(\.name).sorted() where !(includeHead && branch == current) && branch != exclude {
            out.append(RewriteOption(value: branch, label: branch, icon: "arrow.triangle.branch"))
        }
        if includeRemotes {
            for remote in snapshot.remoteBranches where remote.fullName != exclude && !remote.fullName.hasSuffix("/HEAD") {
                out.append(RewriteOption(value: remote.fullName, label: remote.fullName, icon: "cloud"))
            }
        }
        if includeTags {
            for tag in snapshot.tags.map(\.name).sorted().reversed() {
                out.append(RewriteOption(value: tag, label: tag, icon: "tag"))
            }
        }
        return out
    }
}
