import SwiftUI
import VraiCore
import VraiGit

struct ReplayedResolutionNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: Vrai.Space.s8) {
            Symbol(Tone.info.symbol, font: Font.Vrai.callout)
                .foregroundStyle(Tone.info.color)
            VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                Text("git reused your earlier resolution", bundle: .module)
                    .font(Font.Vrai.captionStrong)
                    .foregroundStyle(Color.Vrai.text)
                    .lineLimit(1)
                Text("You resolved this conflict before, so git replayed that resolution (rerere). Check it, then mark the file resolved.", bundle: .module)
                    .font(Font.Vrai.caption)
                    .foregroundStyle(Color.Vrai.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Vrai.Space.s8)
        .padding(.horizontal, Vrai.Space.s12)
        .background(Tone.info.soft)
        .hairline(.bottom)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("conflict-replayed")
    }
}

struct CoAuthorMenu: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @State private var people: [Contributor] = []

    var body: some View {
        Menu {
            if people.isEmpty {
                Text("No contributors yet", bundle: .module)
            } else {
                ForEach(people.prefix(12)) { person in
                    Button(person.email.isEmpty ? person.name : person.name + " <" + person.email + ">") {
                        CoverageActions.addCoAuthor(window, person)
                    }
                }
            }
        } label: {
            HStack(spacing: Vrai.Space.s4) {
                Symbol("person.2", font: Font.Vrai.callout)
                Text("Add co-author", bundle: .module)
                    .font(Font.Vrai.callout)
                    .lineLimit(1)
            }
            .foregroundStyle(Color.Vrai.text)
        }
        .menuStyle(.button)
        .buttonStyle(VraiButtonStyle(variant: .plain, size: .small))
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "Add a Co-authored-by trailer to the message", bundle: .module))
        .accessibilityIdentifier("commit-co-author")
        .task(id: store.snapshot?.headOID) {
            people = await store.contributors()
        }
    }
}
