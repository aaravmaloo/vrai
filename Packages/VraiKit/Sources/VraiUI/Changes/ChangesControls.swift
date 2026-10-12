import SwiftUI
import VraiCore
import VraiGit

enum ChangesMetrics {
    static let sideWide = Vrai.Size.inspector + Vrai.Space.s20
    static let sideMedium = Vrai.Size.filelist + Vrai.Space.s8
    static let bodyHeight = Vrai.Space.s64 + Vrai.Space.s8
    static let hookOutputHeight = Vrai.Space.s64 * 2
    static let selectionBar = Vrai.Size.line
    static let summaryLimit = 50
    static let summaryHardLimit = 72
    static let splitMinimum = Vrai.Size.sheet + Vrai.Space.s40
}

struct StageCheckbox: View {
    let state: StageState
    let label: String
    let action: () -> Void

    var body: some View {
        let once = StageOnce(action)
        Toggle(sources: [
            Binding(get: { state != .none }, set: { _ in once.run() }),
            Binding(get: { state == .full }, set: { _ in once.run() })
        ], isOn: \.self) {
            Text(label)
        }
        .toggleStyle(.checkbox)
        .labelsHidden()
        .help(label)
        .accessibilityLabel(label)
    }
}

@MainActor
final class StageOnce {
    private let action: () -> Void
    private var running = false

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    func run() {
        guard !running else { return }
        running = true
        action()
        Task { @MainActor [weak self] in self?.running = false }
    }
}

struct ChangesGroupHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: Vrai.Space.s8) {
            Text(title)
            Spacer(minLength: 0)
            Text(count, format: .number)
                .monospacedDigit()
        }
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
            Text(title)
                .font(Font.Vrai.headline)
                .foregroundStyle(Color.Vrai.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Vrai.Space.s12)
        .background(tone.soft, in: RoundedRectangle(cornerRadius: Vrai.Radius.lg, style: .continuous))
        .help(message ?? "")
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
            if RiskTag.level(command) == .rewrites {
                riskTag(String(localized: "Rewrites history", bundle: .module), tone: .warning)
            } else if RiskTag.level(command) == .destructive {
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
        .overlay(RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous).strokeBorder(Color.Vrai.Contrast.separator, lineWidth: Metrics.hairline))
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
