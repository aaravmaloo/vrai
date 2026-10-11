import SwiftUI
import VraiCore
import VraiGit

struct ChangesView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window

    var body: some View {
        let working = store.snapshot?.working ?? []
        if working.isEmpty {
            EmptyStateView(
                icon: "checkmark.circle",
                title: String(localized: "No changes to commit", bundle: .module),
                message: String(localized: "Edit a file in \(store.snapshot?.currentBranch?.name ?? window.repositoryName) and it shows up here.", bundle: .module)
            ) {
                VraiButton(title: String(localized: "Show history", bundle: .module), icon: "clock.arrow.circlepath") {
                    window.show(.history)
                }
            }
        } else {
            let staged = working.filter { $0.staged != .none }.count
            let conflicts = working.filter { $0.status == .conflicted }.count
            VStack(spacing: 0) {
                HStack(spacing: Vrai.Space.s8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Changes", bundle: .module)
                            .font(Font.Vrai.headline)
                        Text(summary(files: working.count - conflicts, staged: staged, conflicts: conflicts))
                            .font(Font.Vrai.caption)
                            .foregroundStyle(Color.Vrai.textSecondary)
                    }
                    Spacer()
                    VraiButton(title: String(localized: "Stage all", bundle: .module), size: .small) {}
                        .disabled(true)
                }
                .padding(.leading, Vrai.Space.s12)
                .padding(.trailing, Vrai.Space.s8)
                .frame(height: Metrics.barHeight)
                .hairline(.bottom)
                DiffPanel(files: store.wipFiles.map(FileEntry.init)) { file in
                    if let match = working.first(where: { $0.path == file.path }) {
                        WorkingFileMenu(file: match, window: window)
                    }
                } filesHeader: {
                    EmptyView()
                }
            }
            .onAppear { if store.selection != .wip { store.select(.wip) } }
        }
    }

    func summary(files: Int, staged: Int, conflicts: Int) -> String {
        var text = n(files, "file")
        if staged > 0 { text += String(localized: ", \(staged) staged", bundle: .module) }
        if conflicts > 0 { text += ", " + n(conflicts, "conflict") }
        return text
    }
}
