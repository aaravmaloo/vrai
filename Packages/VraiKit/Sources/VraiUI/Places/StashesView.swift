import SwiftUI
import VraiCore
import VraiGit

struct StashesView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(\.vraiNow) private var now
    @State private var selected = 0

    var body: some View {
        let stashes = store.snapshot?.stashes ?? []
        let working = store.snapshot?.working.count ?? 0
        if stashes.isEmpty {
            EmptyStateView(
                icon: "tray.full",
                title: String(localized: "No stashes", bundle: .module),
                message: String(localized: "Stashing sets your changes aside so you can switch branches with a clean working tree, then bring them back.", bundle: .module)
            ) {
                if working > 0 {
                    VraiButton(title: String(localized: "Stash \(n(working, "change"))", bundle: .module), icon: "tray.and.arrow.down", variant: .primary) {}
                        .disabled(true)
                }
            }
        } else {
            let index = min(selected, stashes.count - 1)
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Stashes", bundle: .module).font(Font.Vrai.headline)
                            Text(n(stashes.count, "stash", "stashes"))
                                .font(Font.Vrai.caption)
                                .foregroundStyle(Color.Vrai.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.leading, Vrai.Space.s16)
                    .padding(.trailing, Vrai.Space.s8)
                    .frame(minHeight: Metrics.barHeight)
                    .hairline(.bottom)
                    ScrollView {
                        VStack(spacing: Vrai.Space.s2) {
                            ForEach(Array(stashes.enumerated()), id: \.element.id) { offset, stash in
                                Button {
                                    selected = offset
                                } label: {
                                    HStack(spacing: Vrai.Space.s10) {
                                        Symbol("tray.full", font: Font.Vrai.title3)
                                            .foregroundStyle(Color.Vrai.textTertiary)
                                        VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                                            Text(Self.title(stash.message))
                                                .font(Font.Vrai.body)
                                                .lineLimit(1)
                                            Text(String(localized: "On \(stash.branch ?? "HEAD"), \(RelativeDate.text(stash.date, now: now))", bundle: .module))
                                                .font(Font.Vrai.caption)
                                                .foregroundStyle(Color.Vrai.textSecondary)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(stash.selector)
                                            .font(Font.Vrai.caption)
                                            .foregroundStyle(Color.Vrai.textTertiary)
                                    }
                                    .padding(.horizontal, Vrai.Space.s10)
                                    .padding(.vertical, Vrai.Space.s4)
                                    .frame(minHeight: Vrai.Size.row + Vrai.Space.s8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .hoverHighlight(radius: Vrai.Radius.sm, selected: offset == index)
                                .contextMenu { StashMenu(stash: stash, window: window) }
                            }
                        }
                        .padding(Vrai.Space.s6)
                    }
                }
                .frame(width: Vrai.Size.inspector + Vrai.Space.s40)
                .hairline(.trailing)
                stashDetail(stashes[index])
            }
        }
    }

    func stashDetail(_ stash: Stash) -> some View {
        VStack(alignment: .leading, spacing: Vrai.Space.s6) {
            Text(Self.title(stash.message))
                .font(Font.Vrai.title2)
            HStack(spacing: Vrai.Space.s12) {
                Text(stash.selector).font(Font.Vrai.codeSmall)
                if let base = stash.base {
                    Text("On \(stash.branch ?? "HEAD"), based on \(base.short)", bundle: .module)
                }
                Text(RelativeDate.text(stash.date, now: now))
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .help(RelativeDate.full(stash.date))
            }
            .font(Font.Vrai.callout)
            .foregroundStyle(Color.Vrai.textSecondary)
            HStack(spacing: Vrai.Space.s8) {
                VraiButton(title: String(localized: "Apply", bundle: .module), icon: "tray.and.arrow.up", variant: .primary, size: .small) {}.disabled(true)
                VraiButton(title: String(localized: "Pop", bundle: .module), icon: "tray.and.arrow.up", size: .small) {}.disabled(true)
                VraiButton(title: String(localized: "New branch", bundle: .module), icon: "arrow.triangle.branch", size: .small) {}.disabled(true)
                VraiButton(title: String(localized: "Drop\u{2026}", bundle: .module), icon: "trash", variant: .plain, size: .small) {}.disabled(true)
            }
            .padding(.top, Vrai.Space.s4)
            Spacer()
        }
        .padding(.top, Vrai.Space.s12)
        .padding(.horizontal, Vrai.Space.s16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    static func title(_ message: String) -> String {
        guard let match = message.firstMatch(of: /^(?:WIP on|On) [^:]+: (.*)$/) else { return message }
        return String(match.output.1)
    }
}
