import SwiftUI
import VraiCore
import VraiGit

struct InitSheet: View {
    let initialFolder: String?
    let context: AppSheetContext
    @Environment(AppModel.self) private var app
    @State private var name = ""
    @State private var location = "~/Developer"
    @State private var branch = "main"
    @State private var template = GitignoreTemplate.swift
    @State private var readme = true
    @State private var branchValid = true
    @State private var busy = false
    @State private var failure: String?

    init(initialFolder: String?, context: AppSheetContext) {
        self.initialFolder = initialFolder
        self.context = context
        if let initialFolder {
            let url = URL(filePath: initialFolder)
            _name = State(initialValue: url.lastPathComponent)
            let parent = url.deletingLastPathComponent().path(percentEncoded: false)
            _location = State(initialValue: parent.count > 1 && parent.hasSuffix("/") ? String(parent.dropLast()) : parent)
        }
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    var target: URL { app.expandingTilde(location).appending(path: trimmedName, directoryHint: .isDirectory) }
    var shownTarget: String { (location.hasSuffix("/") ? location : location + "/") + (trimmedName.isEmpty ? "<name>" : trimmedName) }

    var nameError: String? {
        if trimmedName.contains(where: \.isWhitespace) { return String(localized: "Names can't contain spaces.", bundle: .module) }
        if trimmedName.contains("/") { return String(localized: "Use the In field for the folder; the name can't contain a slash.", bundle: .module) }
        if !trimmedName.isEmpty, FileManager.default.fileExists(atPath: target.appending(path: ".git").path(percentEncoded: false)) {
            return String(localized: "\(trimmedName) is already a git repository. Open it instead.", bundle: .module)
        }
        return nil
    }

    var branchError: String? {
        branchValid ? nil : String(localized: "git won't accept that branch name. Avoid spaces, .., ~ ^ : ? * [ \\ and a trailing slash.", bundle: .module)
    }

    var command: GitCommand {
        app.initCommand(at: target, initialBranch: branch)
    }

    var ok: Bool { !trimmedName.isEmpty && nameError == nil && branchValid && !branch.isEmpty }

    var body: some View {
        LongTailSheet(
            title: String(localized: "New repository", bundle: .module),
            icon: "folder.badge.plus",
            tone: .accent
        ) {
            if let failure {
                SyncForm.Callout(tone: .danger, title: String(localized: "git couldn't create the repository", bundle: .module), message: failure)
            }
            HStack(alignment: .top, spacing: Vrai.Space.s12) {
                SyncForm.Input(label: String(localized: "Name", bundle: .module), text: $name, placeholder: "pocket-notes", error: nameError, mono: true, autofocus: true) { create() }
                LongTailPathField(label: String(localized: "In", bundle: .module), text: $location, placeholder: "~/Developer", kind: .folder, home: app.homeFolder)
            }
            HStack(alignment: .top, spacing: Vrai.Space.s12) {
                SyncForm.Input(label: String(localized: "First branch", bundle: .module), text: $branch, error: branchError, mono: true) { create() }
                SyncForm.Field(label: String(localized: ".gitignore", bundle: .module)) {
                    SyncForm.Select(selection: $template, options: GitignoreTemplate.allCases.map { SyncForm.Option(value: $0, label: label($0)) }, label: String(localized: ".gitignore template", bundle: .module))
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            SyncForm.Checkbox(isOn: $readme, label: String(localized: "Add a README", bundle: .module))
            SyncForm.Options(commands: [command], hasContent: false) { EmptyView() }
        } actions: {
            LongTailFoot(label: String(localized: "Create repository", bundle: .module), enabled: ok, busy: busy, identifier: "init-run", cancel: context.dismiss) { create() }
        }
        .task {
            let preferred = await app.defaultBranchName()
            if branch == "main" { branch = preferred }
        }
        .task(id: branch) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            branchValid = branch.isEmpty ? true : await app.isValidBranchName(branch)
        }
    }

    func label(_ template: GitignoreTemplate) -> String {
        template == .none ? String(localized: "None", bundle: .module) : template.rawValue
    }

    func create() {
        guard ok else { return }
        busy = true
        failure = nil
        Task {
            defer { busy = false }
            do {
                let reference = try await app.initRepository(at: target, initialBranch: branch, gitignoreTemplate: template, readme: readme)
                context.dismiss()
                context.toasts?.show(Toast(message: String(localized: "Created \(trimmedName)", bundle: .module), detail: String(localized: "An empty repository on \(branch). Its first files are in Changes.", bundle: .module), icon: "folder.badge.plus"))
                context.opened(reference)
            } catch let error as GitError {
                failure = error.result?.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines) ?? ErrorCopy(error).message
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
