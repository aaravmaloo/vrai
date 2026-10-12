import SwiftUI
import VraiCore
import VraiGit

struct CleanSheet: View {
    let ignored: Bool
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @State private var plan: CleanPlan?
    @State private var failure: String?
    @State private var busy = false

    var title: String {
        ignored ? String(localized: "Remove untracked and ignored files", bundle: .module) : String(localized: "Remove untracked files", bundle: .module)
    }

    var body: some View {
        LongTailSheet(
            title: title,
            description: ignored
                ? String(localized: "Includes build products and anything else .gitignore hides. git lists them first; nothing is removed until you confirm.", bundle: .module)
                : String(localized: "git lists them first; nothing is removed until you confirm.", bundle: .module)
        ) {
            if let failure {
                SyncForm.Callout(tone: .danger, title: String(localized: "git couldn't list the files", bundle: .module), message: failure)
            } else if let plan {
                if plan.paths.isEmpty {
                    SyncForm.Callout(tone: .info, title: String(localized: "Nothing to remove", bundle: .module), message: ignored ? String(localized: "There are no untracked or ignored files.", bundle: .module) : String(localized: "There are no untracked files.", bundle: .module))
                } else {
                    Text("\(n(plan.files.count, "file")), \(LongTailReveal.bytes(plan.bytes))", bundle: .module)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textSecondary)
                    LongTailBox {
                        ForEach(plan.paths.prefix(200), id: \.self) { path in
                            LongTailLine(text: path, path: true) {
                                Symbol(path.hasSuffix("/") ? "folder" : "doc", font: Font.Vrai.callout)
                                    .foregroundStyle(Color.Vrai.textSecondary)
                            }
                        }
                        if plan.paths.count > 200 {
                            Text("and \(n(plan.paths.count - 200, "more item"))", bundle: .module)
                                .font(Font.Vrai.caption)
                                .foregroundStyle(Color.Vrai.textTertiary)
                                .padding(.horizontal, Vrai.Space.s4)
                        }
                    }
                    if plan.keepsCopy {
                        SyncForm.Callout(tone: .info, icon: "arrow.uturn.backward", title: String(localized: "A copy stays in Undo history for 14 days", bundle: .module))
                    } else {
                        SyncForm.Callout(tone: .warning, title: String(localized: "Too large to keep a copy", bundle: .module), message: String(localized: "Undo history keeps up to \(n(RepositoryStore.cleanCopyFileLimit, "file")) and \(LongTailReveal.bytes(RepositoryStore.cleanCopyByteLimit)). These are gone for good once removed.", bundle: .module))
                    }
                }
            } else {
                Spinner()
            }
            RewriteOptions(command: store.cleanCommand(ignored: ignored), risk: .destructive)
        } actions: {
            LongTailFoot(label: plan.map { String(localized: "Remove \(n($0.files.count, "file"))", bundle: .module) } ?? String(localized: "Remove", bundle: .module), enabled: !(plan?.paths.isEmpty ?? true), busy: busy, danger: true, identifier: "clean-run", cancel: { window.sheets.dismiss() }) { run() }
        }
        .task {
            do {
                plan = try await store.cleanPlan(ignored: ignored)
            } catch let error as GitError {
                failure = error.result?.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines) ?? ErrorCopy(error).message
            } catch {
                failure = ErrorCopy.reading(error)
            }
        }
    }

    func run() {
        guard let plan, !plan.paths.isEmpty, !busy else { return }
        busy = true
        window.sheets.dismiss()
        Task {
            defer { busy = false }
            do {
                try await store.clean(plan)
                let message = String(localized: "Removed \(n(plan.files.count, "file"))", bundle: .module)
                if plan.keepsCopy {
                    window.toasts.show(Toast(message: message, detail: LongTailReveal.bytes(plan.bytes), icon: "trash", action: String(localized: "Undo", bundle: .module)) { window.undoLast() })
                } else {
                    window.toasts.show(Toast(message: message, detail: LongTailReveal.bytes(plan.bytes), icon: "trash"))
                }
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "The files weren't removed", bundle: .module))
            }
        }
    }
}

struct RenameFileSheet: View {
    let path: String
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @State private var target = ""
    @State private var busy = false
    @State private var failure: String?

    var trimmed: String { target.trimmingCharacters(in: .whitespaces) }

    var error: String? {
        guard !trimmed.isEmpty, trimmed != path else { return nil }
        if let root = store.snapshot?.root, FileManager.default.fileExists(atPath: root.appending(path: trimmed).path(percentEncoded: false)) {
            return String(localized: "\(trimmed) already exists.", bundle: .module)
        }
        return nil
    }

    var body: some View {
        LongTailSheet(
            title: String(localized: "Rename \(PathParts.split(path).name)", bundle: .module),
            description: String(localized: "Moves the file and stages the rename in one step, so history follows it.", bundle: .module)
        ) {
            if let failure {
                SyncForm.Callout(tone: .danger, title: String(localized: "git couldn't rename it", bundle: .module), message: failure)
            }
            SyncForm.Input(label: String(localized: "New path", bundle: .module), text: $target, error: error, mono: true, autofocus: true) { run() }
            RewriteOptions(command: LongTailCommands.moveFile(from: path, to: trimmed.isEmpty ? path : trimmed))
        } actions: {
            LongTailFoot(label: String(localized: "Rename", bundle: .module), enabled: !trimmed.isEmpty && trimmed != path && error == nil, busy: busy, identifier: "rename-file-run", cancel: { window.sheets.dismiss() }) { run() }
        }
        .onAppear { if target.isEmpty { target = path } }
    }

    func run() {
        guard !trimmed.isEmpty, trimmed != path, error == nil, !busy else { return }
        busy = true
        failure = nil
        let destination = trimmed
        Task {
            defer { busy = false }
            do {
                try await store.moveFile(from: path, to: destination)
                window.sheets.dismiss()
                window.toasts.show(Toast(message: String(localized: "Renamed to \(PathParts.split(destination).name)", bundle: .module), detail: String(localized: "The rename is staged.", bundle: .module), icon: "pencil"))
            } catch let error as GitError {
                failure = error.result?.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines) ?? ErrorCopy(error).message
            } catch {
                failure = ErrorCopy.writing(error)
            }
        }
    }
}
