import SwiftUI
import VraiCore
import VraiGit

struct StashSheet: View {
    let paths: [String]?
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @State private var message = ""
    @State private var untracked = false
    @State private var keepIndex = false
    @State private var onlyStaged = false
    @State private var picked: Set<String> = []
    @State private var started = false

    var files: [WorkingFile] {
        (store.snapshot?.working ?? []).filter { $0.status != .conflicted }
    }

    var chosen: [WorkingFile] {
        files.filter { file in
            picked.contains(file.path)
                && (untracked || file.status != .untracked || file.staged != .none)
                && (!onlyStaged || file.staged != .none)
        }
    }

    var body: some View {
        let head = window.headName
        let selection = chosen
        let partial = selection.count != files.count
        let command = RewriteCommands.stash(message: trimmed.isEmpty ? nil : trimmed, includeUntracked: untracked, keepIndex: keepIndex, onlyStaged: onlyStaged, paths: partial ? selection.map(\.path) : [])
        RewriteSheet(
            title: String(localized: "Stash changes", bundle: .module),
            description: String(localized: "Sets changes aside in a stash so the working tree is clean. Apply or pop it later, on any branch.", bundle: .module)
        ) {
            RewriteTextField(label: String(localized: "Message", bundle: .module), text: $message, placeholder: String(localized: "WIP on \(head)", bundle: .module), autofocus: true, identifier: "stash-message")
            ScrollView {
                VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                    ForEach(files, id: \.path) { file in
                        let enabled = untracked || file.status != .untracked || file.staged != .none
                        RewriteCheckbox(isOn: Binding(get: { picked.contains(file.path) }, set: { on in
                            if on { picked.insert(file.path) } else { picked.remove(file.path) }
                        })) {
                            HStack(spacing: Vrai.Space.s8) {
                                FileStatusTile(status: file.status)
                                Text(file.path)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .disabled(!enabled)
                        .padding(.vertical, Metrics.hairline)
                    }
                }
                .padding(Vrai.Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: Vrai.Space.s64 * 3)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.Vrai.bg, in: RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous).strokeBorder(Color.Vrai.Contrast.separator, lineWidth: Metrics.hairline))
            RewriteCheckbox(String(localized: "Include untracked files", bundle: .module), isOn: $untracked, description: String(localized: "--include-untracked", bundle: .module))
            RewriteOptions(command: command, detail: String(localized: "Keep index, staged only", bundle: .module)) {
                RewriteCheckbox(String(localized: "Leave staged changes in place", bundle: .module), isOn: $keepIndex, description: String(localized: "--keep-index", bundle: .module))
                RewriteCheckbox(String(localized: "Stash only what's staged", bundle: .module), isOn: $onlyStaged, description: String(localized: "--staged", bundle: .module))
            }
        } actions: {
            RewriteFoot(label: String(localized: "Stash \(n(selection.count, "change"))", bundle: .module), disabled: selection.isEmpty, identifier: "stash-run", cancel: { window.sheets.dismiss() }) {
                window.sheets.dismiss()
                RewriteActions.stash(window, message: trimmed.isEmpty ? nil : trimmed, includeUntracked: untracked, keepIndex: keepIndex, onlyStaged: onlyStaged, paths: partial ? selection.map(\.path) : [], count: selection.count)
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            untracked = files.contains { $0.status == .untracked }
            picked = Set(paths ?? files.map(\.path))
        }
    }

    var trimmed: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
