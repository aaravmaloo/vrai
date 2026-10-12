import SwiftUI
import VraiCore
import VraiGit

struct SubmoduleSheet: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @State private var url = ""
    @State private var path = ""
    @State private var pathEdited = false
    @State private var branch = ""

    var body: some View {
        let destination = pathEdited ? path : Self.defaultPath(for: url)
        let urlError = url.isEmpty || Self.isValidURL(url) ? nil : String(localized: "Use an https or SSH address, like https://github.com/apple/swift-argument-parser.git.", bundle: .module)
        let pathError = pathProblem(destination)
        let ok = Self.isValidURL(url) && !destination.isEmpty && pathError == nil
        let trimmedBranch = branch.trimmingCharacters(in: .whitespaces)
        let command = store.addSubmoduleCommand(url: url.isEmpty ? "<url>" : url, path: destination.isEmpty ? "<path>" : destination, branch: trimmedBranch.isEmpty ? nil : trimmedBranch)
        SyncForm.Sheet(
            title: String(localized: "Add submodule", bundle: .module),
            description: String(localized: "Pins another repository at an exact commit inside this one.", bundle: .module),
            primary: String(localized: "Add submodule", bundle: .module),
            primaryEnabled: ok,
            busy: store.busy.contains("addSubmodule"),
            onSubmit: { run(path: destination) }
        ) {
            SyncForm.Input(label: String(localized: "URL", bundle: .module), text: $url, placeholder: "https://github.com/apple/swift-argument-parser.git", error: urlError, mono: true, autofocus: true) {
                if ok { run(path: destination) }
            }
            SyncForm.Input(label: String(localized: "Path", bundle: .module), text: Binding(get: { destination }, set: { path = $0; pathEdited = true }), placeholder: "Vendor/name", error: pathError, mono: true) {
                if ok { run(path: destination) }
            }
            SyncForm.Options(commands: [command]) {
                SyncForm.Input(label: String(localized: "Branch to track", bundle: .module), text: $branch, placeholder: "main", hint: String(localized: "Leave it empty to follow the remote's default branch.", bundle: .module), mono: true)
            }
        }
        .accessibilityIdentifier("submodule-sheet")
    }

    static func defaultPath(for url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        let last = trimmed.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? ""
        let name = last.hasSuffix(".git") ? String(last.dropLast(4)) : last
        return name.isEmpty ? "" : "Vendor/" + name
    }

    static func isValidURL(_ url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return false }
        return trimmed.firstMatch(of: /^(git@|https?:\/\/|ssh:\/\/|git:\/\/|file:\/\/|\/|\.\.?\/)/) != nil
    }

    func pathProblem(_ path: String) -> String? {
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("/") || path.split(separator: "/").contains("..") {
            return String(localized: "Use a path inside this repository, like Vendor/name.", bundle: .module)
        }
        if store.snapshot?.submodules.contains(where: { $0.path == path }) == true {
            return String(localized: "A submodule already lives at this path.", bundle: .module)
        }
        guard let root = store.snapshot?.root else { return nil }
        let full = root.appending(path: path).path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: full, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue, (try? FileManager.default.contentsOfDirectory(atPath: full))?.isEmpty == true { return nil }
        return String(localized: "Something is already at this path. Choose an empty one.", bundle: .module)
    }

    func run(path: String) {
        let trimmedBranch = branch.trimmingCharacters(in: .whitespaces)
        let source = url.trimmingCharacters(in: .whitespaces)
        window.sheets.dismiss()
        PlacesActions.addSubmodule(window, url: source, path: path, branch: trimmedBranch.isEmpty ? nil : trimmedBranch)
    }
}
