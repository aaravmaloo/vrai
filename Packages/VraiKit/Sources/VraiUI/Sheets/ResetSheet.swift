import SwiftUI
import VraiCore
import VraiGit

struct ResetSheet: View {
    let target: OID
    var label: String?
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @State private var mode: ResetMode = .mixed
    @State private var commits: [PreviewCommit] = []
    @State private var count = 0
    @State private var subject: String?

    var body: some View {
        let head = window.headName
        let changes = store.snapshot?.working.count ?? 0
        let hard = mode == .hard
        RewriteSheet(
            title: String(localized: "Reset \(head) to \(target.short)", bundle: .module),
            description: subject,
            icon: "arrow.counterclockwise",
            tone: hard ? .danger : .warning
        ) {
            if count > 0 {
                Text("\(head) moves back past \(n(count, "commit")):", bundle: .module)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.textSecondary)
                RewriteCommitList(commits: commits, total: count, max: 4)
            }
            RewriteRadioCards(selection: $mode, options: options(changes: changes), label: String(localized: "What happens to your files", bundle: .module))
            RewriteOptions(command: RewriteCommands.reset(to: target.rawValue, mode: mode), risk: hard ? .destructive : .rewrites)
        } actions: {
            RewriteFoot(label: hard ? String(localized: "Reset and discard", bundle: .module) : String(localized: "Reset", bundle: .module), variant: hard ? .danger : .primary, identifier: "reset-run", cancel: { window.sheets.dismiss() }, action: run)
        }
        .task {
            subject = await store.subject(of: target)
            let between = await store.commitsBetween(target.rawValue, "HEAD")
            commits = between.commits
            count = between.count
        }
    }

    func options(changes: Int) -> [RewriteRadioOption<ResetMode>] {
        let discarded = count > 0 ? String(localized: "those commits' changes", bundle: .module) : String(localized: "nothing committed", bundle: .module)
        let yours = changes > 0 ? String(localized: " and your \(n(changes, "uncommitted change"))", bundle: .module) : ""
        return [
            RewriteRadioOption(value: .soft, label: String(localized: "Soft", bundle: .module), description: count > 0 ? String(localized: "Their changes come back as staged changes, ready to commit again.", bundle: .module) : String(localized: "Only the branch moves.", bundle: .module)),
            RewriteRadioOption(value: .mixed, label: String(localized: "Mixed", bundle: .module), description: count > 0 ? String(localized: "Their changes come back unstaged. Your files don't change.", bundle: .module) : String(localized: "Unstages everything; your files don't change.", bundle: .module)),
            RewriteRadioOption(value: .keep, label: String(localized: "Keep", bundle: .module), description: String(localized: "Moves the branch and keeps your uncommitted changes; stops if they'd be overwritten.", bundle: .module)),
            RewriteRadioOption(value: .hard, label: String(localized: "Hard", bundle: .module), description: String(localized: "Discards \(discarded)\(yours). A copy stays in Undo history for 14 days.", bundle: .module), danger: true)
        ]
    }

    func run() {
        let head = window.headName
        let changes = store.snapshot?.working.count ?? 0
        let chosen = mode
        let total = count
        window.sheets.dismiss()
        guard chosen == .hard else {
            RewriteActions.reset(window, target: target, mode: chosen, count: total)
            return
        }
        var lost: [String] = []
        if total > 0 { lost.append(String(localized: "the changes in \(n(total, "commit"))", bundle: .module)) }
        if changes > 0 { lost.append(String(localized: "your \(n(changes, "uncommitted change"))", bundle: .module)) }
        let what = lost.isEmpty ? String(localized: "nothing you'd lose", bundle: .module) : lost.joined(separator: String(localized: " and ", bundle: .module))
        RewriteActions.presentAfterSheet(window, AlertRequest(
            title: String(localized: "Reset \(head) to \(target.short) and discard?", bundle: .module),
            message: String(localized: "This discards \(what). A copy stays in Undo history for 14 days.", bundle: .module),
            actions: [
                AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel),
                AlertAction(title: String(localized: "Reset and discard", bundle: .module), role: .destructive) {
                    RewriteActions.reset(window, target: target, mode: .hard, count: total)
                }
            ]
        ))
    }
}
