import SwiftUI
import VraiCore
import VraiGit

struct ChangesView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(\.widthClass) private var widthClass

    var body: some View {
        let changes = window.changes
        let working = store.snapshot?.working ?? []
        ChangesFittedFrame {
            if working.isEmpty, window.mergeSource == nil, !changes.amend {
                ChangesEmptyState()
            } else if widthClass.isNarrow {
                if changes.narrowDetail, changes.pick != nil {
                    ChangesDiffPane()
                } else {
                    ChangesSide()
                }
            } else {
                HStack(spacing: 0) {
                    ChangesSide()
                        .frame(width: widthClass >= .regular ? ChangesMetrics.sideWide : ChangesMetrics.sideMedium)
                        .hairline(.trailing)
                    ChangesDiffPane()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color.Vrai.bg)
        .onAppear {
            changes.listen(store)
            changes.sync(store)
        }
        .onChange(of: store.snapshot) { _, _ in changes.sync(store) }
    }
}

struct ChangesFittedFrame<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            content()
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .clipped()
    }
}

struct ChangesEmptyState: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window

    var body: some View {
        let snapshot = store.snapshot
        let place = snapshot?.head.branchName ?? window.repositoryName
        EmptyStateView(
            icon: "checkmark.circle",
            title: String(localized: "No changes to commit", bundle: .module),
            message: String(localized: "Edit a file in \(place) and it shows up here.", bundle: .module)
        ) {
            VraiButton(title: String(localized: "Show history", bundle: .module), icon: "clock.arrow.circlepath") {
                window.show(.history)
            }
            if snapshot?.stashes.isEmpty == false {
                VraiButton(title: String(localized: "Apply latest stash", bundle: .module), icon: "tray.and.arrow.up") {
                    window.applyLatestStash()
                }
            }
            if snapshot?.headOID != nil {
                VraiButton(title: String(localized: "Amend last commit", bundle: .module), icon: "pencil", variant: .plain) {
                    window.startAmend()
                }
            }
        }
    }
}

extension WindowModel {
    func applyLatestStash() {
        runChange { [weak self, store] in
            try await store.applyStash(index: 0)
            guard let self else { return }
            let count = store.snapshot?.working.count ?? 0
            self.toasts.show(Toast(message: String(localized: "Applied stash@{0}", bundle: .module), detail: String(localized: "\(n(count, "file")) back in Changes.", bundle: .module), icon: "tray.and.arrow.up"))
        }
    }
}

struct ChangesSide: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @State private var sideHeight: CGFloat?
    @State private var bottomHeight: CGFloat?

    static let listMinimum = Vrai.Size.row * 3

    var body: some View {
        let groups = window.changeGroups
        VStack(spacing: 0) {
            ChangesHead(groups: groups)
            ChangesFileList(groups: groups)
                .frame(maxHeight: .infinity)
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    if window.mergeSource != nil, !groups.conflicts.isEmpty {
                        ChangesCallout(
                            tone: .warning,
                            title: String(localized: "Resolve \(n(groups.conflicts.count, "conflict")) to commit the merge", bundle: .module),
                            message: String(localized: "Or abort it from the banner to put \(window.headName) back.", bundle: .module)
                        )
                        .padding(.horizontal, Vrai.Space.s12)
                        .padding(.bottom, Vrai.Space.s10)
                    }
                    CommitComposerView()
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: bottomFrame)
        }
        .background(Color.Vrai.bg)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sideHeight = $0 }
    }

    var bottomFrame: CGFloat? {
        guard let bottomHeight else { return nil }
        guard let sideHeight else { return bottomHeight }
        return max(0, min(bottomHeight, sideHeight - Metrics.barHeight - Self.listMinimum))
    }
}

struct ChangesHead: View {
    let groups: ChangeGroups
    @Environment(WindowModel.self) private var window

    var body: some View {
        let files = groups.staged + groups.unstaged + groups.untracked
        let allStaged = !files.isEmpty && files.allSatisfy { $0.staged == .full }
        HStack(spacing: Vrai.Space.s8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Changes", bundle: .module)
                    .font(Font.Vrai.headline)
                    .foregroundStyle(Color.Vrai.text)
                Text(summary)
                    .font(Font.Vrai.caption)
                    .foregroundStyle(Color.Vrai.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("changes-title")
            if !files.isEmpty {
                VraiButton(title: allStaged ? String(localized: "Unstage all", bundle: .module) : String(localized: "Stage all", bundle: .module), size: .small) {
                    window.toggleStageAll(includeUntracked: window.optionDown)
                }
                .accessibilityIdentifier("changes-stage-all")
            }
            IconMenu(icon: "ellipsis.circle", label: String(localized: "More actions", bundle: .module)) {
                ChangesMoreMenu(groups: groups, window: window)
            }
        }
        .padding(.leading, Vrai.Space.s12)
        .padding(.trailing, Vrai.Space.s8)
        .frame(height: Metrics.barHeight)
        .hairline(.bottom)
    }

    var summary: String {
        var text = n(groups.changedFiles, "file")
        if !groups.staged.isEmpty { text += String(localized: ", \(groups.staged.count) staged", bundle: .module) }
        if !groups.conflicts.isEmpty { text += ", " + n(groups.conflicts.count, "conflict") }
        return text
    }
}

struct ChangesMoreMenu: View {
    let groups: ChangeGroups
    let window: WindowModel

    var body: some View {
        let files = groups.staged + groups.unstaged + groups.untracked
        let allStaged = !files.isEmpty && files.allSatisfy { $0.staged == .full }
        AlternateMenuItem(
            primary: MenuItem(title: allStaged ? String(localized: "Unstage all", bundle: .module) : String(localized: "Stage all", bundle: .module), icon: allStaged ? "minus" : "plus", enabled: !files.isEmpty) {
                if allStaged { window.unstageEverything() } else { window.stageEverything(includeUntracked: false) }
            },
            alternate: MenuItem(title: String(localized: "Stage all, including untracked", bundle: .module), icon: "plus", enabled: !files.isEmpty) {
                window.stageEverything(includeUntracked: true)
            }
        )
        MenuItem(title: String(localized: "Stash changes\u{2026}", bundle: .module), icon: "tray.and.arrow.down", enabled: !files.isEmpty) { RewriteActions.openStash(window) }
        MenuItem(title: String(localized: "Remove untracked files\u{2026}", bundle: .module), icon: "trash", enabled: !groups.untracked.isEmpty, destructive: true) {
            window.confirmClean()
        }
        if window.preferences.expert {
            MenuItem(title: String(localized: "Remove untracked and ignored files\u{2026}", bundle: .module), icon: "trash", enabled: true, destructive: true) {
                LongTailActions.openClean(window, ignored: true)
            }
        }
        Divider()
        MenuItem(title: String(localized: "Discard all changes\u{2026}", bundle: .module), icon: "arrow.uturn.backward", enabled: !files.isEmpty, destructive: true) {
            window.confirmDiscardAll()
        }
    }
}
