import SwiftUI
import VraiCore
import VraiGit

struct RebaseSheet: View {
    let initialOnto: String?
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(Preferences.self) private var preferences
    @State private var onto = ""
    @State private var autostash = false
    @State private var updateRefs = true
    @State private var replay = false
    @State private var preview: RebasePreview?
    @State private var ontoCommit: PreviewCommit?
    @State private var started = false

    var body: some View {
        let head = window.headName
        let branch = store.snapshot?.currentBranch
        let working = store.snapshot?.working.count ?? 0
        let options = RewriteRefOptions.build(store.snapshot, includeRemotes: true, includeTags: true, exclude: branch?.name, commit: ontoCommit)
        let shown = RewriteActions.shortName(onto)
        let canReplay = store.git.executable.supports(.replay) && branch != nil
        let useReplay = replay && canReplay && preferences.expert
        let command = useReplay
            ? RewriteCommands.replay(onto: onto.isEmpty ? "<onto>" : onto, branch: branch?.name ?? head, contained: updateRefs)
            : RewriteCommands.rebase(onto: onto.isEmpty ? "<onto>" : onto, autostash: autostash, updateRefs: updateRefs)
        let count = preview?.commits.count ?? 0
        let upToDate = preview?.upToDate ?? false
        RewriteSheet(
            title: String(localized: "Rebase \(head)", bundle: .module),
            description: String(localized: "Replays your commits on top of another branch, as if you had started from there. Their hashes change.", bundle: .module),
            icon: "arrow.triangle.swap",
            tone: .warning
        ) {
            RewriteField(label: String(localized: "Onto", bundle: .module)) {
                RewriteSelect(selection: $onto, options: options, label: String(localized: "Onto", bundle: .module))
            }
            if let preview {
                if upToDate {
                    RewriteCallout(tone: .info, title: String(localized: "Already up to date", bundle: .module), message: String(localized: "\(head) already contains \(shown).", bundle: .module))
                } else {
                    Text("\(n(count, "commit")) will be replayed on top of \(shown):", bundle: .module)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textSecondary)
                    RewriteCommitList(commits: preview.commits, max: 5)
                }
                if preview.pushed > 0, let branch, let upstream = branch.upstream {
                    RewriteCallout(tone: .warning, title: String(localized: "\(n(preview.pushed, "commit")) already on \(upstream)", bundle: .module), message: String(localized: "After the rebase, push with force with lease. Anyone who pulled \(branch.name) will need to reset to the new version.", bundle: .module))
                }
            }
            RewriteOptions(command: command, risk: .rewrites, detail: String(localized: "Autostash, update refs", bundle: .module)) {
                RewriteCheckbox(
                    String(localized: "Set my changes aside and bring them back after", bundle: .module),
                    isOn: $autostash,
                    description: working > 0 ? String(localized: "\(n(working, "uncommitted change")), using git stash.", bundle: .module) : String(localized: "No uncommitted changes right now.", bundle: .module)
                )
                RewriteCheckbox(String(localized: "Move branches that point into the rebased commits", bundle: .module), isOn: $updateRefs, description: String(localized: "Stacked branches follow along (--update-refs).", bundle: .module))
                if preferences.expert, canReplay {
                    RewriteCheckbox(String(localized: "Rebase without touching the working tree", bundle: .module), isOn: $replay, description: String(localized: "Uses git replay; conflicts stop it instead of pausing.", bundle: .module))
                }
            }
        } footerStart: {
            Button {
                let target = onto
                window.sheets.dismiss()
                Task { @MainActor in RewriteActions.openInteractive(window, onto: target) }
            } label: {
                HStack(spacing: Vrai.Space.s6) {
                    Symbol("list.number")
                    Text("Edit steps\u{2026}", bundle: .module)
                }
            }
            .buttonStyle(VraiButtonStyle(variant: .plain))
            .disabled(upToDate || count == 0)
        } actions: {
            RewriteFoot(label: String(localized: "Rebase \(n(count, "commit"))", bundle: .module), disabled: onto.isEmpty || upToDate || count == 0, identifier: "rebase-run", cancel: { window.sheets.dismiss() }) {
                window.sheets.dismiss()
                RewriteActions.rebase(window, onto: onto, autostash: autostash, updateRefs: updateRefs, inBackground: useReplay)
            }
        }
        .task {
            guard !started else { return }
            started = true
            autostash = working > 0
            let target = initialOnto ?? RewriteActions.defaultRebaseBase(window) ?? options.first?.value ?? ""
            if let oid = OID(target) {
                ontoCommit = PreviewCommit(id: oid, subject: await store.subject(of: oid) ?? "")
            }
            onto = target
        }
        .task(id: onto) {
            guard !onto.isEmpty else { return }
            preview = await store.rebasePreview(onto: onto)
        }
    }
}
