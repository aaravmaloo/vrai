import SwiftUI
import VraiCore
import VraiGit

struct TagSheet: View {
    enum Kind: Hashable {
        case lightweight
        case annotated
        case signed
    }

    @State private var name = ""
    @State private var target: String
    @State private var kind: Kind = .annotated
    @State private var message = ""
    @State private var push = false
    @Environment(WindowModel.self) private var window
    @Environment(RepositoryStore.self) private var store

    init(target: String) {
        _target = State(initialValue: target)
    }

    var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    var origin: String? { window.sync.defaultRemote }

    var error: String? {
        guard !name.isEmpty else { return nil }
        if name.contains(where: \.isWhitespace) { return String(localized: "Tag names can't contain spaces.", bundle: .module) }
        if store.snapshot?.tags.contains(where: { $0.name == trimmed }) == true { return String(localized: "A tag named \(trimmed) already exists.", bundle: .module) }
        return nil
    }

    var ok: Bool { !trimmed.isEmpty && error == nil && (kind == .lightweight || !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }

    var resolved: OID? { store.resolve(target) }

    var description: String? {
        guard let id = resolved else { return nil }
        let subject = store.history.index[id].map { store.history.commits[$0].subject }
        return String(localized: "On \(id.short)\(subject.map { " " + $0 } ?? "")", bundle: .module)
    }

    var command: GitCommand {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.createTagCommand(name: trimmed.isEmpty ? "<name>" : trimmed, target: target, message: kind == .lightweight ? nil : (text.isEmpty ? (trimmed.isEmpty ? "message" : trimmed) : text), sign: kind == .signed)
    }

    var body: some View {
        SyncForm.Sheet(
            title: String(localized: "New tag", bundle: .module),
            description: description,
            primary: String(localized: "Create tag", bundle: .module),
            primaryEnabled: ok,
            onSubmit: go
        ) {
            HStack(alignment: .top, spacing: Vrai.Space.s12) {
                SyncForm.Input(label: String(localized: "Name", bundle: .module), text: $name, placeholder: "v0.9.2", error: error, mono: true, autofocus: true, onSubmit: go)
                SyncForm.Field(label: String(localized: "On", bundle: .module)) {
                    SyncForm.Select(selection: $target, options: RefOptions.make(store: store, includeHead: true, commit: target), label: String(localized: "Target", bundle: .module))
                }
            }
            SyncForm.Radios(selection: $kind, choices: [
                SyncForm.Choice(value: Kind.lightweight, label: String(localized: "Lightweight", bundle: .module), description: String(localized: "Just a name for the commit. Good for private bookmarks.", bundle: .module)),
                SyncForm.Choice(value: Kind.annotated, label: String(localized: "Annotated", bundle: .module), description: String(localized: "Records who tagged it, when, and a message. Use for releases.", bundle: .module)),
                SyncForm.Choice(value: Kind.signed, label: String(localized: "Signed", bundle: .module), description: String(localized: "Annotated, plus your SSH signature so others can verify it.", bundle: .module), badge: AnyView(SignatureBadge(state: .verified, compact: true)))
            ], cards: true, label: String(localized: "Kind", bundle: .module))
            if kind != .lightweight {
                SyncForm.TextArea(label: String(localized: "Message", bundle: .module), text: $message, placeholder: String(localized: "\(window.repositoryName.capitalized) \(trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : (trimmed.isEmpty ? "0.9.2" : trimmed))\n\nWhat's in this release.", bundle: .module))
            }
            SyncForm.Checkbox(isOn: $push, label: String(localized: "Push the tag to \(origin ?? "origin")", bundle: .module), enabled: origin != nil)
            SyncForm.Options(commands: [command] + (push && origin != nil ? [SyncCommands.pushTag(name: trimmed.isEmpty ? "<name>" : trimmed, remote: origin ?? "origin")] : []), hasContent: false) { EmptyView() }
        }
        .task {
            if await store.signsTagsByDefault() { kind = .signed }
        }
    }

    func go() {
        guard ok else { return }
        let sync = window.sync
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        window.sheets.dismiss()
        sync.createTag(name: trimmed, target: target, message: kind == .lightweight ? nil : text, sign: kind == .signed, push: push && origin != nil)
    }
}
