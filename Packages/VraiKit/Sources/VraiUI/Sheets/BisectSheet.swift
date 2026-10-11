import SwiftUI
import VraiCore
import VraiGit

struct BisectSheet: View {
    let initialGood: String?
    let initialBad: String?
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @State private var good = ""
    @State private var bad = "HEAD"
    @State private var goodCommit: PreviewCommit?
    @State private var preview: BisectPreview?
    @State private var started = false

    var body: some View {
        let snapshot = store.snapshot
        let badOptions = RewriteRefOptions.build(snapshot, includeHead: true, includeTags: true)
        let goodOptions = RewriteRefOptions.build(snapshot, includeTags: true, commit: goodCommit)
        let candidates = preview?.candidates ?? 0
        RewriteSheet(
            title: String(localized: "Find the commit that broke something", bundle: .module),
            description: String(localized: "Bisect checks out commits halfway between a good one and a bad one. You say good or bad until one is left.", bundle: .module),
            icon: "scope",
            tone: .accent
        ) {
            HStack(alignment: .top, spacing: Vrai.Space.s12) {
                RewriteField(label: String(localized: "Known bad", bundle: .module)) {
                    RewriteSelect(selection: $bad, options: badOptions, label: String(localized: "Known bad", bundle: .module))
                }
                RewriteField(label: String(localized: "Known good", bundle: .module)) {
                    RewriteSelect(selection: $good, options: goodOptions, label: String(localized: "Known good", bundle: .module))
                }
            }
            if let preview {
                if preview.valid {
                    RewriteCallout(tone: .info, title: String(localized: "\(n(candidates, "commit")) to search, about \(n(preview.steps, "step"))", bundle: .module), message: String(localized: "Each step halves what's left.", bundle: .module))
                } else {
                    RewriteCallout(tone: .warning, title: String(localized: "The good commit must be an ancestor of the bad one", bundle: .module), message: String(localized: "Pick an older good commit.", bundle: .module))
                }
            }
            RewriteOptions(command: RewriteCommands.startBisect(bad: bad, good: good.isEmpty ? "<good>" : good))
        } actions: {
            RewriteFoot(label: String(localized: "Start bisect", bundle: .module), disabled: candidates == 0, identifier: "bisect-run", cancel: { window.sheets.dismiss() }) {
                window.sheets.dismiss()
                RewriteActions.startBisect(window, bad: bad, good: good)
            }
        }
        .task {
            guard !started else { return }
            started = true
            bad = initialBad ?? "HEAD"
            if let initialGood {
                if let oid = OID(initialGood) {
                    goodCommit = PreviewCommit(id: oid, subject: await store.subject(of: oid) ?? "")
                }
                good = initialGood
            } else {
                good = await defaultGood()
            }
        }
        .task(id: [bad, good]) {
            guard !good.isEmpty, !bad.isEmpty else { return }
            preview = await store.bisectPreview(bad: bad, good: good)
        }
    }

    func defaultGood() async -> String {
        let tags = (store.snapshot?.tags ?? []).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        for tag in tags.prefix(12) {
            let preview = await store.bisectPreview(bad: bad, good: tag.name)
            if preview.valid, preview.candidates > 1 { return tag.name }
        }
        return tags.first?.name ?? store.snapshot?.branches.first { !$0.isCurrent }?.name ?? ""
    }
}
