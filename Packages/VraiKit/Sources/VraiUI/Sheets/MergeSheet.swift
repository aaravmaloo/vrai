import SwiftUI
import VraiCore
import VraiGit

struct MergeSheet: View {
    let initialSource: String?
    let initialMode: MergeMode
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(Preferences.self) private var preferences
    @State private var source = ""
    @State private var mode: MergeMode = .auto
    @State private var message = ""
    @State private var strategy = ""
    @State private var preview: MergePreview?
    @State private var started = false

    var body: some View {
        let head = window.headName
        let options = RewriteRefOptions.build(store.snapshot, includeRemotes: true, exclude: store.snapshot?.head.branchName)
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = RewriteCommands.merge(source: source.isEmpty ? "<branch>" : source, mode: mode, message: trimmed.isEmpty ? nil : trimmed, strategyOption: strategy.isEmpty ? nil : strategy)
        RewriteSheet(title: String(localized: "Merge into \(head)", bundle: .module), icon: "arrow.triangle.merge", tone: .accent) {
            RewriteField(label: String(localized: "Branch to merge", bundle: .module)) {
                RewriteSelect(selection: $source, options: options, label: String(localized: "Branch to merge", bundle: .module))
            }
            if let preview {
                callout(preview, head: head)
                if !preview.commits.isEmpty {
                    RewriteCommitList(commits: preview.commits, total: preview.commitCount, max: 4)
                }
            }
            RewriteRadioCards(selection: $mode, options: modes(head: head), label: String(localized: "How to merge", bundle: .module))
            RewriteOptions(command: command, detail: mode == .squash ? nil : String(localized: "Message, strategy", bundle: .module)) {
                if mode != .squash {
                    RewriteTextField(label: String(localized: "Merge commit message", bundle: .module), text: $message, placeholder: defaultMessage(head: head))
                }
                if preferences.expert {
                    RewriteField(label: String(localized: "When both sides changed the same lines", bundle: .module)) {
                        RewriteSelect(selection: $strategy, options: [
                            RewriteOption(value: "", label: String(localized: "Stop and let me resolve", bundle: .module)),
                            RewriteOption(value: "ours", label: String(localized: "Prefer \(head) (-X ours)", bundle: .module)),
                            RewriteOption(value: "theirs", label: String(localized: "Prefer \(source) (-X theirs)", bundle: .module))
                        ], label: String(localized: "Strategy option", bundle: .module))
                    }
                }
            }
        } actions: {
            RewriteFoot(label: buttonLabel, disabled: source.isEmpty || preview?.kind == .upToDate || preview?.kind == .unknown, identifier: "merge-run", cancel: { window.sheets.dismiss() }, action: run)
        }
        .task {
            guard !started else { return }
            started = true
            mode = initialMode == .fastForwardOnly && !preferences.expert ? .auto : initialMode
            if let initialSource {
                source = initialSource
            } else {
                source = await defaultSource(options: options)
            }
        }
        .task(id: source) {
            guard !source.isEmpty else { return }
            let loaded = await store.mergePreview(source: source)
            preview = loaded
        }
    }

    var buttonLabel: String {
        if mode == .squash { return String(localized: "Squash", bundle: .module) }
        if mode == .auto, preview?.kind == .fastForward { return String(localized: "Fast-forward", bundle: .module) }
        return String(localized: "Merge", bundle: .module)
    }

    func run() {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        window.sheets.dismiss()
        RewriteActions.merge(window, source: source, mode: mode, message: trimmed.isEmpty || mode == .squash ? nil : trimmed, strategyOption: strategy.isEmpty ? nil : strategy, count: preview?.commitCount)
    }

    func defaultMessage(head: String) -> String {
        let remote = store.snapshot?.remoteBranches.contains { $0.fullName == source } ?? false
        let start = remote ? String(localized: "Merge remote-tracking branch '\(source)'", bundle: .module) : String(localized: "Merge branch '\(source)'", bundle: .module)
        let main = ["main", "master"].contains(head)
        return main ? start : start + String(localized: " into \(head)", bundle: .module)
    }

    func modes(head: String) -> [RewriteRadioOption<MergeMode>] {
        let name = source.isEmpty ? String(localized: "the branch", bundle: .module) : source
        var out = [
            RewriteRadioOption(value: MergeMode.auto, label: String(localized: "Fast-forward when possible", bundle: .module), description: String(localized: "Moves \(head) forward if it hasn't diverged; otherwise makes a merge commit.", bundle: .module)),
            RewriteRadioOption(value: MergeMode.mergeCommit, label: String(localized: "Always make a merge commit", bundle: .module), description: String(localized: "Keeps the branch visible in the graph as its own line.", bundle: .module)),
            RewriteRadioOption(value: MergeMode.squash, label: String(localized: "Squash into staged changes", bundle: .module), description: String(localized: "Puts all of \(name)'s changes in Changes as one commit for you to write.", bundle: .module))
        ]
        if preferences.expert {
            out.append(RewriteRadioOption(value: MergeMode.fastForwardOnly, label: String(localized: "Fast-forward only", bundle: .module), description: String(localized: "Stops instead of making a merge commit.", bundle: .module)))
        }
        return out
    }

    @ViewBuilder func callout(_ preview: MergePreview, head: String) -> some View {
        switch preview.kind {
        case .unknown:
            RewriteCallout(tone: .danger, title: String(localized: "Unknown branch", bundle: .module))
        case .upToDate:
            RewriteCallout(tone: .info, title: String(localized: "Already up to date", bundle: .module), message: String(localized: "\(head) already has every commit on \(source).", bundle: .module))
        case .fastForward:
            RewriteCallout(tone: .success, title: String(localized: "Fast-forward possible", bundle: .module), message: String(localized: "\(n(preview.commitCount, "commit")) ahead; no merge commit needed.", bundle: .module))
        case .clean:
            RewriteCallout(tone: .success, title: String(localized: "No conflicts expected", bundle: .module), message: String(localized: "\(n(preview.commitCount, "commit")) touching \(n(preview.files, "file")) merge cleanly.", bundle: .module))
        case .conflicts:
            RewriteCallout(tone: .warning, title: String(localized: "\(n(preview.conflicted.count, "file")) will conflict", bundle: .module), message: String(localized: "\(Self.names(preview.conflicted)) changed on both sides. Vrai walks you through each conflict.", bundle: .module))
        }
    }

    static func names(_ paths: [String]) -> String {
        let names = paths.map { PathParts.split($0).name }
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return String(localized: "\(names[0]) and \(names[1])", bundle: .module)
        case 3: return String(localized: "\(names[0]), \(names[1]) and \(names[2])", bundle: .module)
        default: return String(localized: "\(names[0]), \(names[1]) and \(n(names.count - 2, "more file"))", bundle: .module)
        }
    }

    func defaultSource(options: [RewriteOption<String>]) async -> String {
        let values = options.map(\.value)
        var order: [String] = ["origin/main", "main"]
        if let branch = store.snapshot?.currentBranch, branch.behind > 0, let upstream = branch.upstream { order.append(upstream) }
        order += values
        var seen: Set<String> = []
        for candidate in order where values.contains(candidate) && seen.insert(candidate).inserted && seen.count <= 8 {
            let preview = await store.mergePreview(source: candidate)
            if preview.kind != .upToDate, preview.kind != .unknown { return candidate }
        }
        return values.first ?? ""
    }
}
