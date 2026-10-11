import SwiftUI
import VraiCore
import VraiGit

struct RewordSheet: View {
    let id: OID
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @State private var subject = ""
    @State private var messageBody = ""
    @State private var loaded = false
    @State private var later = 0
    @State private var busy = false

    var description: String {
        later > 0
            ? String(localized: "Changes the message without a full rebase. \(n(later, "later commit")) get new hashes too.", bundle: .module)
            : String(localized: "Changes the message without a full rebase. It's the latest commit.", bundle: .module)
    }

    var body: some View {
        LongTailSheet(
            title: String(localized: "Reword \(id.short)", bundle: .module),
            description: description,
            icon: "pencil",
            tone: .warning
        ) {
            if loaded {
                SyncForm.Input(label: String(localized: "Summary", bundle: .module), text: $subject, autofocus: true) { run() }
                SyncForm.TextArea(label: String(localized: "Description", bundle: .module), text: $messageBody, lines: 4)
            } else {
                Spinner()
            }
            RewriteOptions(command: store.rewordCommand(id: id), risk: .rewrites)
        } actions: {
            LongTailFoot(label: String(localized: "Reword", bundle: .module), enabled: loaded && !subject.trimmingCharacters(in: .whitespaces).isEmpty, busy: busy, identifier: "reword-run", cancel: { window.sheets.dismiss() }) { run() }
        }
        .task {
            if let message = try? await store.commitMessage(of: id) {
                subject = message.subject
                messageBody = message.body
            }
            later = await store.laterCommitCount(after: id)
            loaded = true
        }
    }

    func run() {
        let trimmed = subject.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !busy else { return }
        busy = true
        let message = CommitMessage(subject: trimmed, body: messageBody.trimmingCharacters(in: .whitespacesAndNewlines))
        let rewritten = later + 1
        let note = RewriteActions.forcePushNote(store)
        window.sheets.dismiss()
        Task {
            defer { busy = false }
            do {
                try await store.reword(id: id, message: message)
                window.toasts.show(RewriteActions.undoToast(window, message: String(localized: "Reworded \(id.short)", bundle: .module), detail: String(localized: "Rewrote \(n(rewritten, "commit")).", bundle: .module) + note, icon: "pencil"))
                RewriteActions.selectHead(store)
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "The reword didn't finish", bundle: .module))
            }
        }
    }
}
