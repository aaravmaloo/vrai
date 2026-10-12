import SwiftUI
import VraiCore
import VraiGit

struct ExpertCommandField: View {
    let index: Int
    let command: GitCommand
    var risk: GitCommand.Risk?
    @Environment(\.commandDraft) private var draft

    var body: some View {
        if let draft {
            EditableCommandLine(index: index, command: command, risk: risk, draft: draft)
        } else {
            ReadOnlyCommandLine(command: command, risk: RiskTag.level(command, at: risk))
        }
    }
}

struct EditableCommandLine: View {
    let index: Int
    let command: GitCommand
    let risk: GitCommand.Risk?
    @Bindable var draft: CommandDraft
    @FocusState private var focused: Bool
    @State private var copied = false

    var body: some View {
        let edited = draft.isEdited(index)
        let text = draft.text(index)
        let level = edited ? (TypedCommand(text)?.risk ?? .safe) : RiskTag.level(command, at: risk)
        VStack(alignment: .leading, spacing: Vrai.Space.s4) {
            HStack(spacing: Vrai.Space.s8) {
                Text(verbatim: "$")
                    .font(Font.Vrai.codeSmall)
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .accessibilityHidden(true)
                TextField(text: Binding(get: { draft.text(index) }, set: { draft.edit(index, $0) })) {
                    Text("Command", bundle: .module)
                }
                .textFieldStyle(.plain)
                .font(Font.Vrai.codeSmall)
                .foregroundStyle(Color.Vrai.text)
                .autocorrectionDisabled()
                .focused($focused)
                .onSubmit { draft.submit() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(Text("Command", bundle: .module))
                .accessibilityIdentifier("command-preview")
                RiskTag(risk: level)
                if edited {
                    Button {
                        draft.revert(index)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(IconButtonStyle(small: true))
                    .help(String(localized: "Use the command Vrai built", bundle: .module))
                    .accessibilityLabel(String(localized: "Use the command Vrai built", bundle: .module))
                }
                Button {
                    Clipboard.copy(draft.text(index))
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
            .background(focused ? Color.Vrai.bg : Color.Vrai.bgSunken, in: RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous)
                    .strokeBorder(focused ? Color.Vrai.focus : (level == .destructive ? Color.Vrai.dangerSoft : Color.Vrai.Contrast.separator), lineWidth: Metrics.hairline)
            }
            if edited {
                Text(draft.problem ?? String(localized: "Runs as you typed it, and the output shows in the console.", bundle: .module))
                    .font(Font.Vrai.caption)
                    .foregroundStyle(draft.problem == nil ? Color.Vrai.textTertiary : Color.Vrai.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: command, initial: true) { _, next in draft.register(index, next) }
    }
}

struct ReadOnlyCommandLine: View {
    let command: GitCommand
    let risk: GitCommand.Risk
    @State private var copied = false

    var body: some View {
        HStack(spacing: Vrai.Space.s8) {
            Text(verbatim: "$")
                .font(Font.Vrai.codeSmall)
                .foregroundStyle(Color.Vrai.textTertiary)
                .accessibilityHidden(true)
            Text(CommandStyle.styled(command.display))
                .font(Font.Vrai.codeSmall)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .accessibilityLabel(command.display)
                .accessibilityIdentifier("command-preview")
            RiskTag(risk: risk)
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
        .overlay(RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous).strokeBorder(risk == .destructive ? Color.Vrai.dangerSoft : Color.Vrai.Contrast.separator, lineWidth: Metrics.hairline))
    }
}
