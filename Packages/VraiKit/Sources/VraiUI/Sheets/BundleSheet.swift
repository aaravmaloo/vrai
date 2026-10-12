import SwiftUI
import VraiCore
import VraiGit

struct BundleSheet: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(AppModel.self) private var app
    @State private var include = "--all"
    @State private var destination = ""
    @State private var busy = false
    @State private var failure: String?

    var choices: [SyncForm.Choice<String>] {
        var out = [SyncForm.Choice(value: "--all", label: String(localized: "Every branch and tag", bundle: .module), description: "--all")]
        let branches = store.snapshot?.branches ?? []
        let current = store.snapshot?.currentBranch?.name
        let mainLine = branches.first { BranchColors.mainLines.contains($0.name) }?.name
        for name in [mainLine, current].compactMap({ $0 }) where !out.contains(where: { $0.value == name }) {
            out.append(SyncForm.Choice(value: name, label: String(localized: "\(name) only", bundle: .module)))
        }
        return out
    }

    var suggested: String { "~/Desktop/" + window.repositoryName + ".bundle" }

    var target: URL {
        LongTailPanels.expand(destination.isEmpty ? suggested : destination, home: app.homeFolder) ?? app.desktopFolder.appending(path: window.repositoryName + ".bundle")
    }

    var refs: [String] { [include] }

    var body: some View {
        LongTailSheet(
            title: String(localized: "Create bundle", bundle: .module),
            description: String(localized: "Packs commits into one file you can clone or fetch from, for moving a repository without a server.", bundle: .module)
        ) {
            if let failure {
                SyncForm.Callout(tone: .danger, title: String(localized: "git couldn't write the bundle", bundle: .module), message: failure)
            }
            SyncForm.Radios(selection: $include, choices: choices, label: String(localized: "Include", bundle: .module))
            SyncForm.Options(commands: [store.bundleCommand(refs: refs, to: target)]) {
                LongTailPathField(label: String(localized: "Save as", bundle: .module), text: Binding(get: { destination.isEmpty ? suggested : destination }, set: { destination = $0 }), kind: .saveFile(window.repositoryName + ".bundle"), home: app.homeFolder)
            }
        } actions: {
            LongTailFoot(label: String(localized: "Create bundle", bundle: .module), busy: busy, identifier: "bundle-run", cancel: { window.sheets.dismiss() }) { run() }
        }
    }

    func run() {
        guard !busy else { return }
        busy = true
        failure = nil
        let file = target
        let chosen = refs
        let what = include == "--all" ? String(localized: "every ref", bundle: .module) : include
        Task {
            defer { busy = false }
            do {
                let made = try await store.createBundle(refs: chosen, to: file)
                window.sheets.dismiss()
                let size = (try? made.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { LongTailReveal.bytes(Int64($0)) } ?? ""
                let place = app.displayPath(made.deletingLastPathComponent())
                window.toasts.show(Toast(message: String(localized: "Saved \(made.lastPathComponent) to \(place)", bundle: .module), detail: size.isEmpty ? what : size + ", " + what, icon: "archivebox", action: String(localized: "Show in Finder", bundle: .module)) {
                    LongTailReveal.show([made])
                })
            } catch let error as GitError {
                failure = error.result?.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines) ?? ErrorCopy(error).message
            } catch {
                failure = ErrorCopy.writing(error)
            }
        }
    }
}
