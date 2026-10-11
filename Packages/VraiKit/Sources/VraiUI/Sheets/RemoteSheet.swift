import SwiftUI
import VraiCore
import VraiGit

struct RemoteSheet: View {
    let editing: Remote?
    @State private var name: String
    @State private var url: String
    @State private var pushURL: String
    @State private var prune: Bool
    @State private var urlError: String?
    @Environment(WindowModel.self) private var window
    @Environment(RepositoryStore.self) private var store
    @Environment(Preferences.self) private var preferences

    init(editing remote: Remote?) {
        editing = remote
        _name = State(initialValue: remote?.name ?? "")
        _url = State(initialValue: remote?.fetchURL ?? "")
        _pushURL = State(initialValue: remote?.pushURL ?? "")
        _prune = State(initialValue: remote?.prune ?? true)
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    var trimmedURL: String { url.trimmingCharacters(in: .whitespaces) }
    var trimmedPush: String { pushURL.trimmingCharacters(in: .whitespaces) }

    var nameError: String? {
        guard !name.isEmpty else { return nil }
        if name.contains(where: \.isWhitespace) { return String(localized: "No spaces.", bundle: .module) }
        if trimmedName != editing?.name, store.snapshot?.remotes.contains(where: { $0.name == trimmedName }) == true {
            return String(localized: "A remote named \(trimmedName) already exists.", bundle: .module)
        }
        return nil
    }

    var ok: Bool { !trimmedName.isEmpty && !trimmedURL.isEmpty && nameError == nil }

    var commands: [GitCommand] {
        let shownName = trimmedName.isEmpty ? "<name>" : trimmedName
        let shownURL = trimmedURL.isEmpty ? "<url>" : trimmedURL
        guard let editing else {
            var list = [SyncCommands.addRemote(name: shownName, url: shownURL)]
            if prune { list.append(SyncCommands.setRemotePrune(name: shownName, prune: true)) }
            return list
        }
        var list: [GitCommand] = []
        if trimmedName != editing.name { list.append(SyncCommands.renameRemote(from: editing.name, to: shownName)) }
        if trimmedURL != editing.fetchURL || list.isEmpty { list.append(SyncCommands.setRemoteURL(name: shownName, url: shownURL)) }
        if trimmedPush != (editing.pushURL ?? "") {
            list.append(trimmedPush.isEmpty ? SyncCommands.unsetRemotePushURL(name: shownName) : SyncCommands.setRemoteURL(name: shownName, url: trimmedPush, push: true))
        }
        if prune != editing.prune { list.append(SyncCommands.setRemotePrune(name: shownName, prune: prune)) }
        return list
    }

    var body: some View {
        SyncForm.Sheet(
            title: editing.map { String(localized: "Edit remote \($0.name)", bundle: .module) } ?? String(localized: "Add remote", bundle: .module),
            description: String(localized: "A remote is another copy of this repository you fetch from and push to.", bundle: .module),
            icon: "network",
            primary: editing == nil ? String(localized: "Add remote", bundle: .module) : String(localized: "Save", bundle: .module),
            primaryEnabled: ok,
            onSubmit: go
        ) {
            SyncForm.Input(label: String(localized: "Name", bundle: .module), text: $name, placeholder: "upstream", error: nameError, mono: true, autofocus: editing == nil, onSubmit: go)
            SyncForm.Input(label: String(localized: "URL", bundle: .module), text: Binding(get: { url }, set: { url = $0; urlError = nil }), placeholder: "git@github.com:owner/repo.git", error: urlError, mono: true, onSubmit: go)
            SyncForm.Checkbox(isOn: $prune, label: String(localized: "Remove branches deleted on the remote when fetching", bundle: .module), description: "remote.<name>.prune")
            SyncForm.Options(commands: commands, hasContent: preferences.expert) {
                if preferences.expert {
                    SyncForm.Input(label: String(localized: "Push URL", bundle: .module), text: $pushURL, placeholder: String(localized: "Same as URL", bundle: .module), hint: String(localized: "Push somewhere other than where you fetch from.", bundle: .module), mono: true, onSubmit: go)
                }
            }
        } footerStart: {
            if let editing {
                Button {
                    let sync = window.sync
                    window.sheets.dismiss()
                    sync.confirmRemoveRemote(editing.name)
                } label: {
                    HStack(spacing: Vrai.Space.s6) {
                        Symbol("trash", font: Font.Vrai.body)
                        Text("Remove\u{2026}", bundle: .module)
                    }
                }
                .buttonStyle(VraiButtonStyle(variant: .plain))
            }
        }
    }

    func go() {
        guard ok else { return }
        guard RemoteURL.isValid(trimmedURL) else {
            urlError = String(localized: "git can't use that URL. Try one like git@github.com:owner/repo.git.", bundle: .module)
            return
        }
        if !trimmedPush.isEmpty, !RemoteURL.isValid(trimmedPush) {
            urlError = String(localized: "git can't use the push URL. Try one like git@github.com:owner/repo.git.", bundle: .module)
            return
        }
        let sync = window.sync
        let name = trimmedName
        let url = trimmedURL
        let push = trimmedPush
        let prune = prune
        window.sheets.dismiss()
        if let editing {
            sync.perform({ [weak sync] in
                guard let sync else { return }
                let summary = try await sync.store.editRemote(name: editing.name, newName: name, fetchURL: url, pushURL: push, prune: prune)
                sync.toast(summary, icon: "network")
            })
        } else {
            sync.perform({ [weak sync] in
                guard let sync else { return }
                let summary = try await sync.store.addRemote(name: name, url: url)
                if prune { _ = try await sync.store.editRemote(name: name, prune: true) }
                sync.toast(summary, icon: "network", action: String(localized: "Fetch", bundle: .module)) { [weak sync] in sync?.fetch(remote: name) }
            })
        }
    }
}
