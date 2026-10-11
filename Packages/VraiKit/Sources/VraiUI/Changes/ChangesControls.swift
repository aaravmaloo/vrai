import SwiftUI
import VraiCore
import VraiGit

enum ChangesMetrics {
    static let sideWide = Vrai.Size.inspector + Vrai.Space.s20
    static let sideMedium = Vrai.Size.filelist + Vrai.Space.s8
    static let groupHeight = Vrai.Space.s24
    static let summaryHeight = Vrai.Size.control + Vrai.Space.s8
    static let bodyHeight = Vrai.Space.s64 + Vrai.Space.s8
    static let hookOutputHeight = Vrai.Space.s64 * 2
    static let checkMark = Vrai.Space.s12
    static let selectionBar = Vrai.Size.line
    static let summaryLimit = 50
    static let summaryHardLimit = 72
}

struct StageCheckbox: View {
    let state: StageState
    let label: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.captureMode) private var capture

    var body: some View {
        let on = state != .none
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: Vrai.Radius.xs, style: .continuous)
                    .fill(on ? Color.Vrai.accent : (hovering && !capture ? Color.Vrai.fillHover : Color.Vrai.bg))
                if !on {
                    RoundedRectangle(cornerRadius: Vrai.Radius.xs, style: .continuous)
                        .strokeBorder(Color.Vrai.borderControl, lineWidth: Metrics.hairline)
                }
                if state == .partial {
                    Image(systemName: "minus")
                        .font(Font.Vrai.captionStrong)
                        .foregroundStyle(Color.Vrai.onAccent)
                } else if state == .full {
                    Image(systemName: "checkmark")
                        .font(Font.Vrai.captionStrong)
                        .foregroundStyle(Color.Vrai.onAccent)
                }
            }
            .frame(width: Vrai.Space.s16, height: Vrai.Space.s16)
            .shadow(color: Color.Vrai.separator, radius: Metrics.hairline / 2, y: Metrics.hairline / 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .accessibilityValue(state == .full ? Text("Staged", bundle: .module) : state == .partial ? Text("Partly staged", bundle: .module) : Text("Not staged", bundle: .module))
        .accessibilityAddTraits(.isToggle)
    }
}

struct ChangesGroupHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: Vrai.Space.s8) {
            Text(title)
                .overline()
            Spacer(minLength: 0)
            Text(String(count))
                .overline()
                .monospacedDigit()
        }
        .foregroundStyle(Color.Vrai.textTertiary)
        .padding(.leading, Vrai.Space.s10)
        .padding(.trailing, Vrai.Space.s8)
        .frame(height: ChangesMetrics.groupHeight)
        .padding(.top, Vrai.Space.s6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title), \(n(count, "file"))", bundle: .module))
        .accessibilityAddTraits(.isHeader)
    }
}

struct DiffNote: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: Vrai.Space.s8) {
            Symbol(icon, font: Font.Vrai.body)
            Text(text)
                .font(Font.Vrai.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.Vrai.textSecondary)
        .padding(.vertical, Vrai.Space.s8)
        .padding(.horizontal, Vrai.Space.s12)
        .background(Color.Vrai.bgSubtle)
        .hairline(.bottom)
    }
}

struct ChangesCallout: View {
    let tone: Tone
    let title: String
    var message: String?

    var body: some View {
        HStack(alignment: .top, spacing: Vrai.Space.s10) {
            Symbol(tone.symbol, font: Font.Vrai.title3)
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
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Vrai.Space.s12)
        .background(tone.soft, in: RoundedRectangle(cornerRadius: Vrai.Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ComposerCommandLine: View {
    let command: GitCommand
    @State private var copied = false

    var body: some View {
        HStack(spacing: Vrai.Space.s8) {
            Text(verbatim: "$")
                .font(Font.Vrai.codeSmall)
                .foregroundStyle(Color.Vrai.textTertiary)
            tokens
                .font(Font.Vrai.codeSmall)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if command.risk == .rewrites {
                riskTag(String(localized: "Rewrites history", bundle: .module), tone: .warning)
            } else if command.risk == .destructive {
                riskTag(String(localized: "Destructive", bundle: .module), tone: .danger)
            }
            Button {
                Clipboard.copy(command.display)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(Toast.brief / 2))
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
        .overlay(RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous).strokeBorder(Color.Vrai.separator, lineWidth: Metrics.hairline))
    }

    var tokens: Text {
        var out = AttributedString()
        for token in CommandTokenizer.tokenize(command.display) {
            var piece = AttributedString(token.text)
            switch token.kind {
            case .git: piece.foregroundColor = Color.Vrai.textTertiary
            case .sub:
                piece.foregroundColor = Color.Vrai.text
                piece.font = Font.Vrai.codeSmall.weight(.semibold)
            case .flag: piece.foregroundColor = Color.Vrai.accentText
            case .str: piece.foregroundColor = Color.Vrai.syntaxString
            case .arg: piece.foregroundColor = Color.Vrai.textSecondary
            case nil: break
            }
            out.append(piece)
        }
        return Text(out)
    }

    func riskTag(_ text: String, tone: Tone) -> some View {
        Text(text)
            .font(Font.Vrai.captionStrong)
            .foregroundStyle(tone.color)
            .padding(.horizontal, Vrai.Space.s6)
            .frame(height: Vrai.Space.s16)
            .background(tone.soft, in: Capsule())
            .fixedSize()
    }
}
