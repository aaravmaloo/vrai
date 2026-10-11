import SwiftUI
import VraiCore
import VraiGit

struct SparseSheet: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @State private var state: SparseState?
    @State private var picked: Set<String> = []
    @State private var changes: [String: FolderChange] = [:]
    @State private var busy = false

    var available: [String] { state?.available ?? [] }
    var chosen: [String] { available.filter { picked.contains($0) } }
    var turningOff: Bool { state?.enabled == true && chosen.count == available.count }

    var command: GitCommand {
        turningOff ? store.sparseCommand(folders: []) : store.sparseCommand(folders: chosen)
    }

    var body: some View {
        LongTailSheet(
            title: String(localized: "Sparse checkout", bundle: .module),
            description: String(localized: "Checks out only the folders you pick. The rest stays in history, out of the way.", bundle: .module),
            icon: "folder"
        ) {
            if state == nil {
                HStack(spacing: Vrai.Space.s8) {
                    Spinner()
                    Text("Reading folders\u{2026}", bundle: .module)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textSecondary)
                }
            } else if available.isEmpty {
                SyncForm.Callout(tone: .info, title: String(localized: "There are no folders to pick", bundle: .module), message: String(localized: "Every file sits at the top of the repository.", bundle: .module))
            } else {
                if state?.enabled == true {
                    SyncForm.Callout(tone: .info, icon: "square.dashed", title: String(localized: "Sparse checkout is on", bundle: .module), message: String(localized: "Pick every folder to turn it off.", bundle: .module))
                }
                LongTailBox {
                    ForEach(available, id: \.self) { folder in
                        Toggle(isOn: Binding(get: { picked.contains(folder) }, set: { on in
                            if on { picked.insert(folder) } else { picked.remove(folder) }
                        })) {
                            HStack(spacing: Vrai.Space.s8) {
                                Symbol("folder", font: Font.Vrai.callout)
                                    .foregroundStyle(Color.Vrai.textSecondary)
                                Text(folder)
                                    .font(Font.Vrai.callout)
                                    .foregroundStyle(Color.Vrai.text)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if let change = changes[folder] {
                                    Text(RelativeDate.ago(change.date, now: window.now ?? Date()))
                                        .font(Font.Vrai.caption)
                                        .foregroundStyle(Color.Vrai.textTertiary)
                                        .lineLimit(1)
                                        .help(change.id.short + " " + change.subject)
                                }
                            }
                        }
                        .toggleStyle(SyncForm.CheckboxStyle())
                        .padding(.horizontal, Vrai.Space.s4)
                        .frame(minHeight: Vrai.Size.controlSm)
                        .accessibilityIdentifier("sparse-" + folder)
                    }
                }
                HStack(spacing: Vrai.Space.s8) {
                    VraiButton(title: String(localized: "Select all", bundle: .module), variant: .plain, size: .small) { picked = Set(available) }
                    VraiButton(title: String(localized: "Select none", bundle: .module), variant: .plain, size: .small) { picked = [] }
                    Spacer(minLength: 0)
                }
            }
            SyncForm.Options(commands: [command], hasContent: false) { EmptyView() }
        } actions: {
            LongTailFoot(label: turningOff ? String(localized: "Turn off", bundle: .module) : String(localized: "Apply", bundle: .module), enabled: state != nil && !chosen.isEmpty, busy: busy, identifier: "sparse-run", cancel: { window.sheets.dismiss() }) { run() }
        }
        .task {
            let loaded = await store.sparseState()
            picked = Set(loaded.enabled && !loaded.folders.isEmpty ? loaded.folders.filter { loaded.available.contains($0) } : loaded.available)
            state = loaded
            changes = await store.lastModified(paths: loaded.available)
        }
    }

    func run() {
        guard !busy, !chosen.isEmpty else { return }
        busy = true
        let folders = chosen
        let off = turningOff
        let hidden = available.filter { !picked.contains($0) }
        window.sheets.dismiss()
        Task {
            defer { busy = false }
            do {
                if off {
                    try await store.disableSparseCheckout()
                    window.toasts.show(Toast(message: String(localized: "Sparse checkout is off", bundle: .module), detail: String(localized: "Every folder is checked out again.", bundle: .module), icon: "folder"))
                } else {
                    try await store.setSparseCheckout(dirs: folders)
                    let detail = hidden.isEmpty ? nil : String(localized: "Hidden until you add them back: \(ListFormatter.localizedString(byJoining: Array(hidden.prefix(3))))\(hidden.count > 3 ? "\u{2026}" : "").", bundle: .module)
                    window.toasts.show(Toast(message: String(localized: "Checking out \(n(folders.count, "folder"))", bundle: .module), detail: detail, icon: "folder"))
                }
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "Sparse checkout didn't change", bundle: .module))
            }
        }
    }
}
