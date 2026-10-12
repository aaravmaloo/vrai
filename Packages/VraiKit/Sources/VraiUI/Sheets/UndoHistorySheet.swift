import SwiftUI
import VraiCore
import VraiGit

struct UndoHistorySheet: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @State private var entries: [UndoEntry]?

    var body: some View {
        VStack(alignment: .leading, spacing: Vrai.Space.s16) {
            HStack(alignment: .top, spacing: Vrai.Space.s12) {
                Symbol("arrow.uturn.backward", font: Font.Vrai.title2)
                    .foregroundStyle(Color.Vrai.textSecondary)
                    .frame(width: Vrai.Space.s40, height: Vrai.Space.s40)
                    .background(Color.Vrai.fill, in: RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
                VStack(alignment: .leading, spacing: Vrai.Space.s4) {
                    Text("Undo history", bundle: .module)
                        .font(Font.Vrai.title2)
                        .foregroundStyle(Color.Vrai.text)
                    Text("What Vrai can put back. Discards, resets, deleted branches and dropped stashes are kept for 14 days.", bundle: .module)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Vrai.Space.s2)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            list
            HStack(spacing: Vrai.Space.s8) {
                Spacer(minLength: 0)
                VraiButton(title: String(localized: "Done", bundle: .module)) {
                    window.sheets.dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("undo-history-done")
            }
            .padding(.top, Vrai.Space.s4)
        }
        .padding(Vrai.Space.s20)
        .frame(width: window.sheetWidth(Vrai.Size.sheet))
        .background(Color.Vrai.surface)
        .onExitCommand { window.sheets.dismiss() }
        .task { await load() }
        .accessibilityIdentifier("undo-history")
    }

    @ViewBuilder var list: some View {
        if let entries {
            if entries.isEmpty {
                Text("Nothing yet. Commits, merges, rebases and discards show up here.", bundle: .module)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .padding(Vrai.Space.s12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            UndoHistoryRow(entry: entry, now: window.now) {
                                window.sheets.dismiss()
                                window.restoreUndo(entry)
                            }
                            .accessibilityIdentifier("undo-row-\(index)")
                        }
                    }
                }
                .frame(maxHeight: Vrai.Space.s64 * 5)
                .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Spinner()
                .frame(maxWidth: .infinity)
                .padding(Vrai.Space.s12)
        }
    }

    func load() async {
        do {
            entries = try await store.undoHistory()
        } catch {
            entries = []
        }
    }
}

struct UndoHistoryRow: View {
    let entry: UndoEntry
    let now: Date?
    let restore: () -> Void

    var body: some View {
        HStack(spacing: Vrai.Space.s10) {
            Symbol("arrow.uturn.backward", font: Font.Vrai.title3)
                .foregroundStyle(Color.Vrai.textTertiary)
            VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                Text(entry.label)
                    .font(Font.Vrai.body)
                    .foregroundStyle(Color.Vrai.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(Font.Vrai.caption)
                    .foregroundStyle(Color.Vrai.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VraiButton(title: String(localized: "Restore", bundle: .module), size: .small, action: restore)
                .accessibilityIdentifier("undo-restore")
        }
        .padding(.vertical, Vrai.Space.s4)
        .padding(.horizontal, Vrai.Space.s10)
        .frame(minHeight: Vrai.Size.row + Vrai.Space.s8)
        .accessibilityElement(children: .contain)
    }

    var subtitle: String {
        let when = RelativeDate.text(entry.date, now: now)
        guard let detail = entry.detail, !detail.isEmpty else { return when }
        return detail + ", " + when
    }
}
