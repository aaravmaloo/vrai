import SwiftUI
import VraiCore
import VraiGit

struct ArchiveSheet: View {
    let ref: String
    var label: String?
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(AppModel.self) private var app
    @State private var format = ArchiveFormat.zip
    @State private var prefix = ""
    @State private var paths = ""
    @State private var destination = ""
    @State private var destinationEdited = false
    @State private var busy = false
    @State private var failure: String?

    var shown: String {
        if let label { return label }
        if ref == "HEAD" { return window.headName }
        return OID(ref)?.short ?? ref
    }

    var defaultPrefix: String {
        let name = window.repositoryName
        if let tag = store.snapshot?.tags.first(where: { $0.name == ref }) { return name + "-" + Self.version(tag.name) + "/" }
        let id = store.resolve(ref)
        if let id, let tag = store.snapshot?.tags.first(where: { $0.target == id }) { return name + "-" + Self.version(tag.name) + "/" }
        return name + "-" + (id?.short ?? shown) + "/"
    }

    static func version(_ tag: String) -> String {
        tag.hasPrefix("v") && tag.dropFirst().first?.isNumber == true ? String(tag.dropFirst()) : tag
    }

    var fileName: String {
        let base = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).replacingOccurrences(of: "/", with: "-")
        return (base.isEmpty ? window.repositoryName : base) + "." + format.fileExtension
    }

    var suggestedDestination: String { "~/Downloads/" + fileName }

    var target: URL {
        LongTailPanels.expand(destination.isEmpty ? suggestedDestination : destination, home: app.homeFolder) ?? app.downloadsFolder.appending(path: fileName)
    }

    var pathList: [String] {
        paths.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" }).map(String.init).filter { !$0.isEmpty }
    }

    var command: GitCommand {
        store.archiveCommand(ref: ref, format: format, prefix: prefix, paths: pathList, to: target)
    }

    var body: some View {
        LongTailSheet(
            title: String(localized: "Export \(shown)", bundle: .module),
            description: String(localized: "Saves the files at that commit, without the .git folder.", bundle: .module),
            icon: "archivebox"
        ) {
            if let failure {
                SyncForm.Callout(tone: .danger, title: String(localized: "git couldn't write the archive", bundle: .module), message: failure)
            }
            SyncForm.Field(label: String(localized: "Format", bundle: .module)) {
                SegmentedControl(selection: $format, items: [
                    SegmentItem(value: ArchiveFormat.zip, title: "zip", label: "zip"),
                    SegmentItem(value: ArchiveFormat.tarGz, title: "tar.gz", label: "tar.gz")
                ], small: false)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(String(localized: "Format", bundle: .module))
            }
            SyncForm.Input(label: String(localized: "Folder inside the archive", bundle: .module), text: $prefix, mono: true, autofocus: true) { run() }
            SyncForm.Options(commands: [command]) {
                LongTailPathField(label: String(localized: "Save as", bundle: .module), text: Binding(get: { destination.isEmpty ? suggestedDestination : destination }, set: { destination = $0; destinationEdited = true }), kind: .saveFile(fileName), home: app.homeFolder)
                SyncForm.Input(label: String(localized: "Only these paths", bundle: .module), text: $paths, placeholder: "Sources Docs/README.md", hint: String(localized: "Leave empty to export everything. Separate paths with spaces.", bundle: .module), mono: true) { run() }
            }
        } actions: {
            LongTailFoot(label: String(localized: "Export", bundle: .module), enabled: !prefix.isEmpty, busy: busy, identifier: "archive-run", cancel: { window.sheets.dismiss() }) { run() }
        }
        .onAppear { if prefix.isEmpty { prefix = defaultPrefix } }
        .onChange(of: format) { if !destinationEdited { destination = "" } }
        .onChange(of: prefix) { if !destinationEdited { destination = "" } }
    }

    func run() {
        guard !prefix.isEmpty, !busy else { return }
        busy = true
        failure = nil
        let file = target
        let chosen = format
        let folder = prefix.hasSuffix("/") ? prefix : prefix + "/"
        let only = pathList
        Task {
            defer { busy = false }
            do {
                let made = try await store.exportArchive(ref: ref, format: chosen, prefix: folder, paths: only, to: file)
                window.sheets.dismiss()
                let place = app.displayPath(made.deletingLastPathComponent())
                window.toasts.show(Toast(message: String(localized: "Exported \(made.lastPathComponent)", bundle: .module), detail: String(localized: "In \(place).", bundle: .module), icon: "archivebox", action: String(localized: "Show in Finder", bundle: .module)) {
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
