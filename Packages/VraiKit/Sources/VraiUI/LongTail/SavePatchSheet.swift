import SwiftUI
import VraiCore
import VraiGit

struct SavePatchSheet: View {
    enum Scope: Hashable {
        case one
        case series
    }

    enum Follow: Hashable {
        case nothing
        case sendEmail
        case imapSend
    }

    let id: OID
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(AppModel.self) private var app
    @State private var scope = Scope.one
    @State private var follow = Follow.sendEmail
    @State private var folder = "~/Desktop"
    @State private var recipient = ""
    @State private var later: [PreviewCommit] = []
    @State private var busy = false
    @State private var failure: String?

    var ids: [OID] { scope == .one ? [id] : [id] + later.reversed().map(\.id) }
    var directory: URL { LongTailPanels.expand(folder, home: app.homeFolder) ?? app.desktopFolder }

    var previewFiles: [URL] {
        ids.enumerated().map { directory.appending(path: String(format: "%04d-", $0.offset + 1) + "\u{2026}.patch") }
    }

    var commands: [GitCommand] {
        var out = store.savePatchCommands(ids: ids, to: directory)
        switch follow {
        case .nothing: break
        case .sendEmail: out.append(LongTailCommands.sendEmail(files: previewFiles.map { $0.path(percentEncoded: false) }, to: recipient))
        case .imapSend: out.append(store.imapSendCommand())
        }
        return out
    }

    var body: some View {
        LongTailSheet(
            title: String(localized: "Save \(id.short) as a patch", bundle: .module),
            description: String(localized: "Writes format-patch files you can mail or apply elsewhere with Apply patches.", bundle: .module),
            icon: "envelope"
        ) {
            if let failure {
                SyncForm.Callout(tone: .danger, title: String(localized: "git couldn't write the patches", bundle: .module), message: failure)
            }
            if !later.isEmpty {
                SyncForm.Field(label: String(localized: "Commits", bundle: .module)) {
                    SyncForm.Radios(selection: $scope, choices: [
                        SyncForm.Choice(value: Scope.one, label: String(localized: "Only \(id.short)", bundle: .module)),
                        SyncForm.Choice(value: Scope.series, label: String(localized: "\(id.short) and \(n(later.count, "later commit")) on \(window.headName)", bundle: .module), description: String(localized: "Saves a numbered series.", bundle: .module))
                    ], label: String(localized: "Commits", bundle: .module))
                }
            }
            LongTailPathField(label: String(localized: "Save to", bundle: .module), text: $folder, kind: .folder, home: app.homeFolder)
            SyncForm.Field(label: String(localized: "Then copy", bundle: .module)) {
                SyncForm.Radios(selection: $follow, choices: [
                    SyncForm.Choice(value: Follow.sendEmail, label: String(localized: "The git send-email command", bundle: .module), description: String(localized: "Paste it in Terminal to mail the series.", bundle: .module)),
                    SyncForm.Choice(value: Follow.imapSend, label: String(localized: "The git imap-send command", bundle: .module), description: String(localized: "Puts the series in your IMAP drafts folder.", bundle: .module)),
                    SyncForm.Choice(value: Follow.nothing, label: String(localized: "Nothing", bundle: .module))
                ], label: String(localized: "Then copy", bundle: .module))
            }
            if follow == .sendEmail {
                SyncForm.Input(label: String(localized: "To", bundle: .module), text: $recipient, placeholder: "git@vger.kernel.org", mono: true) { run() }
            }
            SyncForm.Options(commands: commands, hasContent: false) { EmptyView() }
        } actions: {
            LongTailFoot(label: ids.count == 1 ? String(localized: "Save patch", bundle: .module) : String(localized: "Save \(n(ids.count, "patch"))", bundle: .module), busy: busy, identifier: "patch-run", cancel: { window.sheets.dismiss() }) { run() }
        }
        .task {
            guard await HeadReach.contains(id, store: store) else { return }
            later = await store.commitsBetween(id.rawValue, "HEAD", limit: 100).commits
        }
    }

    func run() {
        guard !busy else { return }
        busy = true
        failure = nil
        let chosen = ids
        let target = directory
        let then = follow
        let to = recipient
        Task {
            defer { busy = false }
            do {
                let files = try await store.savePatches(ids: chosen, to: target)
                window.sheets.dismiss()
                var detail = files.count == 1 ? files[0].lastPathComponent : String(localized: "\(n(files.count, "file")) in \(app.displayPath(target))", bundle: .module)
                switch then {
                case .nothing:
                    break
                case .sendEmail:
                    Clipboard.copy(LongTailCommands.sendEmail(files: files.map { $0.path(percentEncoded: false) }, to: to).display)
                    detail += String(localized: ". Copied the send-email command.", bundle: .module)
                case .imapSend:
                    let quoted = files.map { "'" + $0.path(percentEncoded: false).replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
                    Clipboard.copy("cat " + quoted + " | " + store.imapSendCommand().display)
                    detail += String(localized: ". Copied the imap-send command.", bundle: .module)
                }
                window.toasts.show(Toast(message: files.count == 1 ? String(localized: "Saved a patch", bundle: .module) : String(localized: "Saved \(n(files.count, "patch"))", bundle: .module), detail: detail, icon: "envelope", action: String(localized: "Show in Finder", bundle: .module)) {
                    LongTailReveal.show(files)
                })
            } catch let error as GitError {
                failure = error.result?.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines) ?? ErrorCopy(error).message
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
