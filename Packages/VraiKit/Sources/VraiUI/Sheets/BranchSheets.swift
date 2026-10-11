import SwiftUI
import VraiCore
import VraiGit

struct BranchSheet: View {
    @State private var name = ""
    @State private var from: String
    @State private var checkout: Bool
    @State private var publish = false
    @Environment(WindowModel.self) private var window
    @Environment(RepositoryStore.self) private var store

    init(from: String, checkout: Bool, name: String = "") {
        _from = State(initialValue: from)
        _checkout = State(initialValue: checkout)
        _name = State(initialValue: name)
    }

    var snapshot: RepositorySnapshot? { store.snapshot }
    var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    var error: String? { SyncForm.branchNameError(name, existing: snapshot?.branches.map(\.name) ?? []) }
    var ok: Bool { !trimmed.isEmpty && error == nil }
    var origin: String? { window.sync.defaultRemote }

    var commands: [GitCommand] {
        var list = [store.createBranchCommand(name: trimmed.isEmpty ? "<name>" : trimmed, from: from, switchTo: checkout)]
        if publish, let origin { list.append(SyncCommands.push(remote: origin, refspec: trimmed.isEmpty ? "<name>" : trimmed, setUpstream: true)) }
        return list
    }

    var body: some View {
        let dirty = snapshot?.working.count ?? 0
        SyncForm.Sheet(
            title: String(localized: "New branch", bundle: .module),
            description: String(localized: "A branch is a movable name for a line of commits. Its color follows it everywhere.", bundle: .module),
            icon: "arrow.triangle.branch",
            tone: .accent,
            primary: checkout ? String(localized: "Create and switch", bundle: .module) : String(localized: "Create branch", bundle: .module),
            primaryEnabled: ok,
            onSubmit: go
        ) {
            SyncForm.Input(label: String(localized: "Name", bundle: .module), text: $name, placeholder: "feature/graph-search", hint: String(localized: "Use slashes to group branches, like feature/ or fix/.", bundle: .module), error: error, mono: true, autofocus: true, onSubmit: go)
            SyncForm.Field(label: String(localized: "Start from", bundle: .module)) {
                SyncForm.Select(selection: $from, options: RefOptions.make(store: store, includeHead: true, includeRemotes: true, includeTags: true, commit: from), label: String(localized: "Start from", bundle: .module))
            }
            SyncForm.Checkbox(isOn: $checkout, label: String(localized: "Switch to the new branch", bundle: .module), description: dirty > 0 && checkout ? String(localized: "Your \(n(dirty, "change")) come along.", bundle: .module) : nil)
            SyncForm.Options(commands: commands) {
                SyncForm.Checkbox(isOn: $publish, label: String(localized: "Push to \(origin ?? "origin") and track it", bundle: .module), description: String(localized: "Runs git push -u \(origin ?? "origin") after creating it.", bundle: .module), enabled: origin != nil)
            }
        }
    }

    func go() {
        guard ok else { return }
        let sync = window.sync
        window.sheets.dismiss()
        sync.createBranch(name: trimmed, from: from, switchTo: checkout, publish: publish && origin != nil)
    }
}

struct BranchRenameSheet: View {
    let original: String
    @State private var name: String
    @Environment(WindowModel.self) private var window
    @Environment(RepositoryStore.self) private var store

    init(name: String) {
        original = name
        _name = State(initialValue: name)
    }

    var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    var error: String? { trimmed == original ? nil : SyncForm.branchNameError(name, existing: store.snapshot?.branches.map(\.name) ?? [], current: original) }
    var ok: Bool { !trimmed.isEmpty && trimmed != original && error == nil }
    var upstream: String? { store.snapshot?.branches.first { $0.name == original }?.upstream }

    var body: some View {
        SyncForm.Sheet(
            title: String(localized: "Rename \(original)", bundle: .module),
            icon: "pencil",
            primary: String(localized: "Rename", bundle: .module),
            primaryEnabled: ok,
            onSubmit: go
        ) {
            SyncForm.Input(label: String(localized: "New name", bundle: .module), text: $name, error: error, mono: true, autofocus: true, onSubmit: go)
            if let upstream {
                SyncForm.Callout(tone: .info, title: String(localized: "Its upstream stays \(upstream)", bundle: .module), message: String(localized: "Rename the branch on the remote by pushing the new name and deleting the old one.", bundle: .module))
            }
            SyncForm.Options(commands: [BranchCommands.rename(from: original, to: trimmed.isEmpty ? "<name>" : trimmed)], hasContent: false) { EmptyView() }
        }
    }

    func go() {
        guard ok else { return }
        let sync = window.sync
        let from = original
        let to = trimmed
        window.sheets.dismiss()
        sync.perform({ [weak sync] in
            guard let sync else { return }
            let summary = try await sync.store.renameBranch(from: from, to: to)
            sync.toast(summary, icon: "pencil")
        })
    }
}

struct BranchUpstreamSheet: View {
    let name: String
    @State private var upstream: String
    @Environment(WindowModel.self) private var window
    @Environment(RepositoryStore.self) private var store

    init(name: String) {
        self.name = name
        _upstream = State(initialValue: "")
    }

    var options: [SyncForm.Option<String>] {
        [SyncForm.Option(value: "", label: String(localized: "None", bundle: .module))]
            + (store.snapshot?.remoteBranches ?? []).sorted { $0.fullName < $1.fullName }.map { SyncForm.Option(value: $0.fullName, label: $0.fullName, icon: "cloud") }
    }

    var body: some View {
        SyncForm.Sheet(
            title: String(localized: "Upstream for \(name)", bundle: .module),
            description: String(localized: "The remote branch that pull reads from and push writes to, and that ahead and behind counts compare against.", bundle: .module),
            icon: "link",
            primary: String(localized: "Save", bundle: .module),
            onSubmit: go
        ) {
            SyncForm.Field(label: String(localized: "Track", bundle: .module)) {
                SyncForm.Select(selection: $upstream, options: options, label: String(localized: "Upstream", bundle: .module))
            }
            SyncForm.Options(commands: [BranchCommands.setUpstream(branch: name, upstream: upstream.isEmpty ? nil : upstream)], hasContent: false) { EmptyView() }
        }
        .onAppear {
            upstream = store.snapshot?.branches.first { $0.name == name }?.upstream ?? ""
        }
    }

    func go() {
        let sync = window.sync
        let branch = name
        let target = upstream.isEmpty ? nil : upstream
        window.sheets.dismiss()
        sync.perform({ [weak sync] in
            guard let sync else { return }
            let summary = try await sync.store.setUpstream(branch: branch, upstream: target)
            sync.toast(summary, icon: "link")
        })
    }
}

enum RefOptions {
    @MainActor static func make(store: RepositoryStore, includeHead: Bool, includeRemotes: Bool = false, includeTags: Bool = false, commit: String? = nil, exclude: String? = nil) -> [SyncForm.Option<String>] {
        guard let snapshot = store.snapshot else { return [] }
        var out: [SyncForm.Option<String>] = []
        let current = snapshot.head.branchName
        if includeHead {
            let label = current.map { String(localized: "\($0) (current)", bundle: .module) } ?? String(localized: "HEAD at \(snapshot.headOID?.short ?? "")", bundle: .module)
            out.append(SyncForm.Option(value: "HEAD", label: label, icon: "mappin.and.ellipse"))
        }
        if let commit, let id = OID(commit) {
            let subject = store.history.index[id].map { store.history.commits[$0].subject } ?? ""
            out.append(SyncForm.Option(value: commit, label: id.short + (subject.isEmpty ? "" : " " + subject), icon: "smallcircle.filled.circle"))
        }
        for branch in snapshot.branches.map(\.name).sorted() where (!includeHead || branch != current) && branch != exclude {
            out.append(SyncForm.Option(value: branch, label: branch, icon: "arrow.triangle.branch"))
        }
        if includeRemotes {
            for remote in snapshot.remoteBranches.map(\.fullName).sorted() where remote != exclude && !remote.hasSuffix("/HEAD") {
                out.append(SyncForm.Option(value: remote, label: remote, icon: "cloud"))
            }
        }
        if includeTags {
            for tag in snapshot.tags.map(\.name).sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending }).prefix(200) {
                out.append(SyncForm.Option(value: tag, label: tag, icon: "tag"))
            }
        }
        if let commit, !out.contains(where: { $0.value == commit }) {
            out.append(SyncForm.Option(value: commit, label: commit, icon: "smallcircle.filled.circle"))
        }
        return out
    }
}
