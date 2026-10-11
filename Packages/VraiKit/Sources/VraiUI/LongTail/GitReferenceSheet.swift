import SwiftUI
import VraiCore
import VraiGit

struct GitReferenceSheet: View {
    let command: String
    let context: AppSheetContext
    @Environment(AppModel.self) private var app
    @State private var page: [[ManualSpan]] = []
    @State private var failure: String?

    var body: some View {
        LongTailSheet(
            title: "git " + command,
            description: String(localized: "The manual page that comes with git \(app.gitVersion?.description ?? "").", bundle: .module),
            icon: "doc.text",
            width: Vrai.Size.sheetWide
        ) {
            if let failure {
                SyncForm.Callout(tone: .warning, title: String(localized: "The manual page isn't installed", bundle: .module), message: failure)
            } else if page.isEmpty {
                HStack(spacing: Vrai.Space.s8) {
                    Spinner()
                    Text("Reading the manual\u{2026}", bundle: .module)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textSecondary)
                }
            } else {
                Text(Self.styled(page))
                    .font(Font.Vrai.codeSmall)
                    .foregroundStyle(Color.Vrai.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("git-reference")
            }
        } actions: {
            LongTailDone(action: context.dismiss)
        }
        .task {
            do {
                page = try await app.manual(for: command)
            } catch {
                failure = String(localized: "git couldn't show the page for \(command). Install the git documentation, or read it at git-scm.com.", bundle: .module)
            }
        }
    }

    static func styled(_ page: [[ManualSpan]]) -> AttributedString {
        var out = AttributedString()
        for (index, line) in page.enumerated() {
            for span in line {
                var run = AttributedString(span.text)
                switch span.style {
                case .bold:
                    run.font = Font.Vrai.codeStrong
                case .underline:
                    run.foregroundColor = Color.Vrai.accentText
                case .plain:
                    break
                }
                out += run
            }
            if index < page.count - 1 { out += AttributedString("\n") }
        }
        return out
    }
}
