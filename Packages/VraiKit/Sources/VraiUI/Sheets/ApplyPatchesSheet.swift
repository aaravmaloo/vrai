import SwiftUI
import VraiCore
import VraiGit

struct ApplyPatchesSheet: View {
    let initialFiles: [URL]
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(AppModel.self) private var app
    @State private var files: [URL] = []
    @State private var summaries: [PatchSummary] = []
    @State private var applied: Set<URL> = []
    @State private var threeWay = true
    @State private var signoff = false
    @State private var loading = false
    @State private var busy = false

    var patchCount: Int { max(summaries.count, files.count) }

    var authors: [String] {
        var seen: [String] = []
        for summary in summaries where !summary.author.isEmpty && !seen.contains(summary.author) { seen.append(summary.author) }
        return seen
    }

    var body: some View {
        LongTailSheet(
            title: String(localized: "Apply patches", bundle: .module),
            description: String(localized: "Applies patches from mail or format-patch files as commits, keeping authors and messages.", bundle: .module)
        ) {
            if files.isEmpty {
                SyncForm.Callout(tone: .info, title: String(localized: "Pick .patch or .mbox files", bundle: .module), message: String(localized: "git format-patch writes them; mail clients export mbox.", bundle: .module))
            } else {
                LongTailBox {
                    if summaries.isEmpty {
                        ForEach(files, id: \.self) { file in
                            LongTailLine(text: file.lastPathComponent) {
                                Symbol("doc.text", font: Font.Vrai.callout)
                                    .foregroundStyle(Color.Vrai.textSecondary)
                            }
                        }
                    } else {
                        ForEach(summaries) { summary in
                            row(summary)
                        }
                    }
                }
                if !applied.isEmpty {
                    SyncForm.Callout(tone: .warning, title: String(localized: "\(n(applied.count, "file")) looks already applied", bundle: .module), message: String(localized: "A commit with the same changes is already on \(window.headName). git skips patches it finds empty.", bundle: .module))
                }
            }
            HStack {
                VraiButton(title: files.isEmpty ? String(localized: "Choose patch files\u{2026}", bundle: .module) : String(localized: "Choose other files\u{2026}", bundle: .module), icon: "doc.text") {
                    let picked = LongTailPanels.pickFiles(home: app.homeFolder)
                    if !picked.isEmpty { files = picked }
                }
                .accessibilityIdentifier("am-choose")
                Spacer(minLength: 0)
            }
            SyncForm.Checkbox(isOn: $threeWay, label: String(localized: "Fall back to a three-way merge", bundle: .module), description: "--3way")
            SyncForm.Checkbox(isOn: $signoff, label: String(localized: "Add Signed-off-by", bundle: .module), description: "--signoff")
            if !files.isEmpty {
                SyncForm.Options(commands: [store.applyPatchesCommand(files: files, threeWay: threeWay, signoff: signoff)], hasContent: false) { EmptyView() }
            }
        } actions: {
            LongTailFoot(label: patchCount > 0 ? String(localized: "Apply \(n(patchCount, "patch"))", bundle: .module) : String(localized: "Apply", bundle: .module), enabled: !files.isEmpty && !loading, busy: busy, identifier: "am-run", cancel: { window.sheets.dismiss() }) { run() }
        }
        .onAppear { if files.isEmpty { files = initialFiles } }
        .task(id: files) {
            guard !files.isEmpty else {
                summaries = []
                applied = []
                return
            }
            loading = true
            summaries = await store.patchSummaries(files: files)
            applied = await store.appliedPatchFiles(files)
            loading = false
        }
    }

    func row(_ summary: PatchSummary) -> some View {
        let done = applied.contains { $0.lastPathComponent == summary.file }
        return HStack(alignment: .firstTextBaseline, spacing: Vrai.Space.s8) {
            Symbol("doc.text", font: Font.Vrai.callout)
                .foregroundStyle(Color.Vrai.textSecondary)
            VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                Text(summary.subject.isEmpty ? summary.file : summary.subject)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.text)
                    .lineLimit(1)
                Text(summary.author.isEmpty ? summary.file : summary.author + ", " + summary.file)
                    .font(Font.Vrai.caption)
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if done {
                Badge(text: String(localized: "Already applied", bundle: .module), tone: .warning)
            }
        }
        .padding(.horizontal, Vrai.Space.s4)
        .padding(.vertical, Vrai.Space.s2)
        .accessibilityElement(children: .combine)
    }

    func run() {
        guard !files.isEmpty, !busy else { return }
        busy = true
        let chosen = files
        let three = threeWay
        let sign = signoff
        let people = authors
        let count = patchCount
        let folder = chosen.first.map { app.displayPath($0.deletingLastPathComponent()) } ?? ""
        let head = window.headName
        window.sheets.dismiss()
        Task {
            defer { busy = false }
            do {
                let made = try await store.applyPatches(files: chosen, threeWay: three, signoff: sign)
                let by = people.count == 1 ? String(localized: " by \(people[0])", bundle: .module) : ""
                window.toasts.show(RewriteActions.undoToast(window, message: String(localized: "Applied \(n(count, "patch"))", bundle: .module), detail: String(localized: "From \(folder), as \(n(made, "commit"))\(by) on \(head).", bundle: .module), icon: "doc.on.doc"))
                RewriteActions.selectHead(store)
            } catch {
                if case .applyingPatches? = store.snapshot?.state {
                    window.toasts.show(Toast(tone: .warning, message: String(localized: "Stopped applying patches", bundle: .module), detail: String(localized: "Fix the patch, then continue from the banner.", bundle: .module), icon: "bandage"))
                    return
                }
                RewriteActions.report(error, window, failure: String(localized: "The patches didn't apply", bundle: .module))
            }
        }
    }
}
