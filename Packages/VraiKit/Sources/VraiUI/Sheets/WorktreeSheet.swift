import SwiftUI
import VraiCore
import VraiGit

struct WorktreeSheet: View {
    enum Mode: Hashable {
        case new
        case existing
    }

    var initialBranch: String?
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var mode: Mode = .new
    @State private var name = ""
    @State private var existing = ""
    @State private var folder = ""
    @State private var folderEdited = false
    @State private var started = false

    var body: some View {
        let free = freeBranches
        let branch = mode == .new ? name.trimmingCharacters(in: .whitespaces) : existing
        let destination = folderEdited ? folder : defaultFolder(for: branch)
        let nameError = mode == .new ? SyncForm.branchNameError(name, existing: store.snapshot?.branches.map(\.name) ?? []) : nil
        let folderError = folderProblem(destination)
        let ok = !branch.isEmpty && nameError == nil && folderError == nil && !destination.trimmingCharacters(in: .whitespaces).isEmpty
        let command = store.addWorktreeCommand(path: destination, branch: branch.isEmpty ? "<name>" : branch, createBranch: mode == .new)
        SyncForm.Sheet(
            title: String(localized: "Add worktree", bundle: .module),
            description: String(localized: "A second working folder for this repository, on another branch. Both share one history.", bundle: .module),
            icon: "rectangle.on.rectangle",
            primary: String(localized: "Add worktree", bundle: .module),
            primaryEnabled: ok,
            busy: store.busy.contains("addWorktree"),
            onSubmit: { run(path: destination, branch: branch) }
        ) {
            SyncForm.Tabs(selection: $mode, items: [
                SyncForm.Option(value: Mode.new, label: String(localized: "New branch", bundle: .module)),
                SyncForm.Option(value: Mode.existing, label: String(localized: "Existing branch", bundle: .module))
            ], label: String(localized: "Branch", bundle: .module))
            if mode == .new {
                SyncForm.Input(label: String(localized: "Branch name", bundle: .module), text: $name, placeholder: "fix/sync-button-overlap", error: nameError, mono: true, autofocus: true) {
                    if ok { run(path: destination, branch: branch) }
                }
            } else {
                SyncForm.Field(label: String(localized: "Branch", bundle: .module), hint: free.isEmpty ? String(localized: "Every branch is checked out somewhere already. Create a new one instead.", bundle: .module) : nil) {
                    if free.isEmpty {
                        SyncForm.Select(selection: .constant(""), options: [SyncForm.Option(value: "", label: String(localized: "No free branches", bundle: .module))], label: String(localized: "Branch", bundle: .module))
                            .disabled(true)
                    } else {
                        SyncForm.Select(selection: $existing, options: free.map { SyncForm.Option(value: $0, label: $0, icon: "arrow.triangle.branch") }, label: String(localized: "Branch", bundle: .module))
                    }
                }
            }
            SyncForm.Input(label: String(localized: "Folder", bundle: .module), text: Binding(get: { destination }, set: { folder = $0; folderEdited = true }), error: folderError, mono: true) {
                if ok { run(path: destination, branch: branch) }
            }
            SyncForm.Options(commands: [command], hasContent: false) { EmptyView() }
        }
        .onAppear {
            guard !started else { return }
            started = true
            if let initialBranch, free.contains(initialBranch) {
                mode = .existing
                existing = initialBranch
            } else {
                existing = free.first ?? ""
            }
        }
        .accessibilityIdentifier("worktree-sheet")
    }

    var freeBranches: [String] {
        guard let snapshot = store.snapshot else { return [] }
        let taken = Set(snapshot.worktrees.compactMap(\.branch))
        return snapshot.branches.filter { !taken.contains($0.name) && $0.worktreePath == nil && !$0.isCurrent }.map(\.name).sorted()
    }

    func defaultFolder(for branch: String) -> String {
        let last = branch.split(separator: "/").last.map(String.init) ?? ""
        let suffix = last.isEmpty ? String(localized: "branch", bundle: .module) : last
        guard let root = store.snapshot?.root else { return "~/" + window.repositoryName + "-" + suffix }
        let parent = root.deletingLastPathComponent().path(percentEncoded: false)
        let base = parent.hasSuffix("/") ? parent : parent + "/"
        return PathText.abbreviated(base + root.lastPathComponent + "-" + suffix)
    }

    func folderProblem(_ path: String) -> String? {
        let resolved = store.resolvedPath(path)
        guard !resolved.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue, (try? FileManager.default.contentsOfDirectory(atPath: resolved))?.isEmpty == true { return nil }
        return String(localized: "Something is already there. Choose a new or empty folder.", bundle: .module)
    }

    func run(path: String, branch: String) {
        guard !branch.isEmpty else { return }
        let createBranch = mode == .new
        window.sheets.dismiss()
        PlacesActions.addWorktree(window, path: path, branch: branch, createBranch: createBranch, opener: PlacesOpener(app: app, openWindow: openWindow))
    }
}
