import SwiftUI
import VraiCore
import VraiGit

struct BugReportSheet: View {
    let context: AppSheetContext
    @Environment(AppModel.self) private var app
    @State private var note = ""
    @State private var diagnostics = true
    @State private var busy = false
    @State private var failure: String?

    var folderName: String {
        let name = context.store?.snapshot?.root?.lastPathComponent ?? "git"
        return name + "-report"
    }

    var folder: URL { app.desktopFolder.appending(path: folderName, directoryHint: .isDirectory) }

    var commands: [GitCommand] {
        if let store = context.store { return store.bugReportCommands(to: folder, diagnostics: diagnostics) }
        return [app.bugReportCommand(to: folder)]
    }

    var body: some View {
        LongTailSheet(
            title: String(localized: "Report a git problem", bundle: .module),
            description: String(localized: "Collects git's own bug report and, if you like, a diagnostics archive, into a folder you can attach.", bundle: .module),
            icon: "stethoscope"
        ) {
            if let failure {
                SyncForm.Callout(tone: .danger, title: String(localized: "git couldn't write the report", bundle: .module), message: failure)
            }
            SyncForm.TextArea(label: String(localized: "What happened", bundle: .module), text: $note, placeholder: String(localized: "What did you do, what did you expect, and what happened instead?", bundle: .module), lines: 4)
            SyncForm.Checkbox(isOn: $diagnostics, label: String(localized: "Include a diagnostics archive", bundle: .module), description: context.store == nil ? String(localized: "Open a repository first; the archive describes one repository.", bundle: .module) : String(localized: "Repository layout and stats, no file contents.", bundle: .module), enabled: context.store != nil)
            SyncForm.Options(commands: commands, hasContent: false) { EmptyView() }
        } actions: {
            LongTailFoot(label: String(localized: "Create report", bundle: .module), busy: busy, identifier: "bugreport-run", cancel: context.dismiss) { run() }
        }
    }

    func run() {
        busy = true
        failure = nil
        let target = folder
        Task {
            defer { busy = false }
            do {
                let files: [URL]
                if let store = context.store {
                    files = try await store.bugReport(to: target, diagnostics: diagnostics, note: note)
                } else {
                    files = try await app.bugReport(to: target, note: note)
                }
                context.dismiss()
                let count = files.filter { $0.lastPathComponent != "what-happened.txt" }.count
                if let toasts = context.toasts {
                    toasts.show(Toast(message: String(localized: "Saved the report to the Desktop", bundle: .module), detail: String(localized: "\(folderName), \(n(count, "file")). Nothing was sent.", bundle: .module), icon: "stethoscope", action: String(localized: "Show in Finder", bundle: .module)) {
                        LongTailReveal.show(files.isEmpty ? [target] : files)
                    })
                } else {
                    LongTailReveal.show(files.isEmpty ? [target] : files)
                }
            } catch let error as GitError {
                failure = error.result?.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines) ?? ErrorCopy(error).message
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
