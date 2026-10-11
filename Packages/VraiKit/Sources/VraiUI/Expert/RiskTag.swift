import SwiftUI
import VraiCore
import VraiGit

struct RiskTag: View {
    let risk: GitCommand.Risk

    var body: some View {
        if let tag = Self.tag(risk) {
            Text(tag.label)
                .font(Font.Vrai.captionStrong)
                .foregroundStyle(tag.tone.color)
                .lineLimit(1)
                .padding(.horizontal, Vrai.Space.s6)
                .frame(height: Vrai.Space.s16)
                .background(tag.tone.soft, in: Capsule())
                .fixedSize()
                .accessibilityLabel(tag.label)
        }
    }

    static func tag(_ risk: GitCommand.Risk) -> (label: String, tone: Tone)? {
        switch risk {
        case .safe: nil
        case .rewrites: (String(localized: "Rewrites history", bundle: .module), .warning)
        case .destructive: (String(localized: "Destructive", bundle: .module), .danger)
        }
    }

    static func level(_ command: GitCommand, at floor: GitCommand.Risk? = nil) -> GitCommand.Risk {
        let parsed = TypedCommand.risk(of: command)
        guard let floor else { return parsed }
        return TypedCommand.rank(floor) > TypedCommand.rank(parsed) ? floor : parsed
    }
}

enum CommandStyle {
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
