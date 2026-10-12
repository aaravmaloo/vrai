import SwiftUI
import VraiCore
import VraiGit

struct StashBranchSheet: View {
    let index: Int
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @State private var name = ""

    var body: some View {
        let stash = store.snapshot?.stashes.first { $0.index == index }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let error = name.isEmpty ? nil : Self.problem(trimmed, snapshot: store.snapshot)
        let base = stash?.base?.short ?? ""
        RewriteSheet(
            title: String(localized: "New branch from stash", bundle: .module),
            description: String(localized: "Starts a branch at \(base), where the stash was made, then applies and drops it. Useful when the stash no longer applies cleanly.", bundle: .module),
            icon: "arrow.triangle.branch"
        ) {
            RewriteTextField(label: String(localized: "Name", bundle: .module), text: $name, placeholder: String(localized: "feature/halo-experiments", bundle: .module), mono: true, error: error, autofocus: true, identifier: "stash-branch-name")
            RewriteOptions(command: RewriteCommands.branchFromStash(index: index, name: trimmed.isEmpty ? "<name>" : trimmed))
        } actions: {
            RewriteFoot(label: String(localized: "Create branch", bundle: .module), disabled: trimmed.isEmpty || error != nil, identifier: "stash-branch-run", cancel: { window.sheets.dismiss() }) {
                window.sheets.dismiss()
                RewriteActions.branchFromStash(window, index: index, name: trimmed)
            }
        }
    }

    static func problem(_ name: String, snapshot: RepositorySnapshot?) -> String? {
        if name.contains(where: \.isWhitespace) { return String(localized: "Branch names can't contain spaces.", bundle: .module) }
        if snapshot?.branches.contains(where: { $0.name == name }) == true { return String(localized: "A branch named \(name) already exists.", bundle: .module) }
        let invalid = name.hasPrefix("-") || name.hasPrefix("/") || name.hasSuffix("/") || name.hasSuffix(".") || name.hasSuffix(".lock")
            || name.contains("..") || name.contains("//") || name.contains("@{") || name == "@"
            || name.contains(where: { "~^:?*[\\".contains($0) || $0.asciiValue.map { $0 < 32 || $0 == 127 } == true })
        return invalid ? String(localized: "git won't accept that name: avoid .., ~ ^ : ? * [ \\ and a trailing slash.", bundle: .module) : nil
    }
}
