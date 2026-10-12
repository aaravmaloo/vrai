import SwiftUI
import VraiCore
import VraiGit

struct SplitSheet: View {
    let id: OID
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @State private var files: [ChangedPath] = []
    @State private var picked: Set<String> = []
    @State private var subject = ""
    @State private var original = ""
    @State private var loaded = false
    @State private var busy = false

    var kept: [String] { files.map(\.path).filter { !picked.contains($0) } }
    var ok: Bool { !picked.isEmpty && picked.count < files.count && !subject.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        LongTailSheet(
            title: String(localized: "Split \(id.short)", bundle: .module),
            description: original.isEmpty ? nil : original,
            icon: "rectangle.split.2x1",
            tone: .warning
        ) {
            if !loaded {
                Spinner()
            } else if files.count < 2 {
                SyncForm.Callout(tone: .info, title: String(localized: "There's only 1 file in this commit", bundle: .module), message: String(localized: "Split works file by file, so it needs at least 2.", bundle: .module))
            } else {
                Text("Move these files into a second commit:", bundle: .module)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.textSecondary)
                LongTailBox {
                    ForEach(files) { file in
                        Toggle(isOn: Binding(get: { picked.contains(file.path) }, set: { on in
                            if on { picked.insert(file.path) } else { picked.remove(file.path) }
                        })) {
                            HStack(spacing: Vrai.Space.s8) {
                                FileStatusTile(status: file.status.first.flatMap(FileStatus.init(letter:)) ?? .modified)
                                PathBar(path: file.path)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .toggleStyle(SyncForm.CheckboxStyle())
                        .padding(.horizontal, Vrai.Space.s4)
                        .frame(minHeight: Vrai.Size.controlSm)
                        .accessibilityIdentifier("split-" + file.path)
                    }
                }
                SyncForm.Input(label: String(localized: "Summary of the second commit", bundle: .module), text: $subject) { run() }
                if picked.count == files.count {
                    Text("Leave at least 1 file in the first commit.", bundle: .module)
                        .font(Font.Vrai.caption)
                        .foregroundStyle(Color.Vrai.warning)
                }
            }
            RewriteOptions(command: store.splitCommand(id: id, keep: kept), risk: .rewrites)
        } actions: {
            LongTailFoot(label: String(localized: "Split commit", bundle: .module), enabled: ok, busy: busy, identifier: "split-run", cancel: { window.sheets.dismiss() }) { run() }
        }
        .task {
            let message = try? await store.commitMessage(of: id)
            original = message?.subject ?? ""
            files = (try? await store.commitFiles(id: id)) ?? []
            picked = Set(files.dropFirst().map(\.path))
            subject = Self.secondSubject(original)
            loaded = true
        }
    }

    static func secondSubject(_ subject: String) -> String {
        subject.isEmpty ? "" : subject + " (part 2)"
    }

    func run() {
        guard ok, !busy else { return }
        busy = true
        let moving = files.map(\.path).filter { picked.contains($0) }
        let second = subject.trimmingCharacters(in: .whitespaces)
        let note = RewriteActions.forcePushNote(store)
        window.sheets.dismiss()
        Task {
            defer { busy = false }
            do {
                try await store.split(id: id, moving: moving, secondSubject: second)
                window.toasts.show(RewriteActions.undoToast(window, message: String(localized: "Split \(id.short) in two", bundle: .module), detail: String(localized: "\(n(moving.count, "file")) moved to a second commit.", bundle: .module) + note, icon: "rectangle.split.2x1"))
                RewriteActions.selectHead(store)
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "The split didn't finish", bundle: .module))
            }
        }
    }
}
