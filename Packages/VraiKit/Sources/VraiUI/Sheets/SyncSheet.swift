import SwiftUI
import VraiCore
import VraiGit

struct SyncSheet: View {
    let publish: Bool
    @State private var tab: SyncTab
    @State private var remote: String
    @State private var branch: String
    @State private var setUpstream: Bool
    @State private var tags = false
    @State private var force: PushForce = .none
    @State private var noVerify = false
    @State private var pushOptions = ""
    @State private var mode: PullMode = .merge
    @State private var autostash = false
    @State private var fetchFrom: String
    @State private var prune = true
    @State private var fetchTags = false
    @State private var depth = ""
    @State private var unshallow = false
    @State private var command: GitCommand?
    @Environment(WindowModel.self) private var window
    @Environment(RepositoryStore.self) private var store
    @Environment(Preferences.self) private var preferences

    static let allRemotes = "--all"

    @MainActor init(sync: SyncModel, tab: SyncTab, publish: Bool) {
        let snapshot = sync.snapshot
        let current = snapshot?.currentBranch
        let remotes = snapshot?.remotes.map(\.name) ?? []
        let upstream = current?.upstream.flatMap { upstream in remotes.sorted { $0.count > $1.count }.first { upstream.hasPrefix($0 + "/") }.map { (remote: $0, branch: String(upstream.dropFirst($0.count + 1))) } }
        self.publish = publish && current?.upstream == nil
        _tab = State(initialValue: publish ? .push : tab)
        _remote = State(initialValue: upstream?.remote ?? (remotes.contains("origin") ? "origin" : remotes.first ?? "origin"))
        _branch = State(initialValue: upstream?.branch ?? current?.name ?? "")
        _setUpstream = State(initialValue: current?.upstream == nil)
        _fetchFrom = State(initialValue: Self.allRemotes)
    }

    var snapshot: RepositorySnapshot? { store.snapshot }
    var current: Branch? { snapshot?.currentBranch }
    var remotes: [Remote] { snapshot?.remotes ?? [] }

    var key: CommandKey {
        CommandKey(tab: tab, remote: remote, branch: branch, setUpstream: setUpstream, tags: tags, force: force, noVerify: noVerify, pushOptions: options, mode: mode, autostash: autostash, fetchFrom: fetchFrom, prune: prune, fetchTags: fetchTags, depth: Int(depth), unshallow: unshallow, head: snapshot?.headOID)
    }

    var options: [String] {
        pushOptions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var behind: Int { current?.behind ?? 0 }

    var pending: (commits: [(id: OID, subject: String)], total: Int) {
        guard let current else { return ([], 0) }
        let tracking = snapshot?.remoteBranches.first { $0.remote == remote && $0.name == branch }
        let exclude = tracking.map { [$0.tip] } ?? (snapshot?.remoteBranches.filter { $0.remote == remote }.map(\.tip) ?? [])
        return PendingCommits.walk(history: store.history, from: current.tip, excluding: exclude, known: tracking != nil && current.upstream == tracking?.fullName ? current.ahead : nil)
    }

    var title: String {
        if publish { return String(localized: "Publish \(current?.name ?? String(localized: "branch", bundle: .module))", bundle: .module) }
        return String(localized: "Sync with remotes", bundle: .module)
    }

    var description: String {
        if publish, let name = current?.name {
            return String(localized: "\(name) isn't on any remote yet. Pushing it sets the upstream, so later pushes are one click.", bundle: .module)
        }
        return String(localized: "Fetch reads, pull integrates, push writes. Each tab shows the exact command.", bundle: .module)
    }

    var icon: String {
        switch tab {
        case .fetch: "arrow.triangle.2.circlepath"
        case .pull: "arrow.down.to.line"
        case .push: "arrow.up.to.line"
        }
    }

    var primary: String {
        switch tab {
        case .push:
            if force != .none { return String(localized: "Force push", bundle: .module) }
            if publish { return String(localized: "Publish \(current?.name ?? "")", bundle: .module) }
            let count = pending.total
            return count > 0 ? String(localized: "Push \(n(count, "commit"))", bundle: .module) : String(localized: "Push", bundle: .module)
        case .pull:
            return behind > 0 ? String(localized: "Pull \(n(behind, "commit"))", bundle: .module) : String(localized: "Pull", bundle: .module)
        case .fetch:
            return String(localized: "Fetch", bundle: .module)
        }
    }

    var enabled: Bool {
        guard !remotes.isEmpty else { return false }
        if tab != .fetch, current == nil { return false }
        if tab == .pull, branch.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return true
    }

    var body: some View {
        SyncForm.Sheet(title: title, description: description, icon: icon, tone: .accent, primary: primary, primaryEnabled: enabled, danger: tab == .push && force != .none, onSubmit: go) {
            if !publish {
                SyncForm.Tabs(selection: $tab, items: [
                    SyncForm.Option(value: SyncTab.fetch, label: String(localized: "Fetch", bundle: .module)),
                    SyncForm.Option(value: SyncTab.pull, label: String(localized: "Pull", bundle: .module)),
                    SyncForm.Option(value: SyncTab.push, label: String(localized: "Push", bundle: .module))
                ], label: String(localized: "Operation", bundle: .module))
            }
            switch tab {
            case .fetch: fetchTab
            case .pull: pullTab
            case .push: pushTab
            }
        }
        .task(id: key) { await build() }
        .task { await loadDefaults() }
    }

    var remoteOptions: [SyncForm.Option<String>] {
        remotes.map { SyncForm.Option(value: $0.name, label: $0.name, icon: "network", detail: PathText.remoteDetail($0.fetchURL)) }
    }

    @ViewBuilder var fetchTab: some View {
        SyncForm.Field(label: String(localized: "From", bundle: .module)) {
            SyncForm.Select(selection: $fetchFrom, options: [SyncForm.Option(value: Self.allRemotes, label: String(localized: "All remotes", bundle: .module))] + remoteOptions, label: String(localized: "Remote", bundle: .module))
        }
        SyncForm.Checkbox(isOn: $prune, label: String(localized: "Remove remote branches that were deleted", bundle: .module), description: "--prune")
        SyncForm.Checkbox(isOn: $fetchTags, label: String(localized: "Fetch every tag", bundle: .module), description: "--tags")
        if preferences.expert {
            SyncForm.Input(label: String(localized: "Depth", bundle: .module), text: Binding(get: { depth }, set: { depth = $0.filter(\.isNumber) }), placeholder: String(localized: "Full history", bundle: .module), hint: String(localized: "Limit how many commits to fetch on a shallow clone.", bundle: .module), mono: true)
            if snapshot?.isShallow == true {
                SyncForm.Checkbox(isOn: $unshallow, label: String(localized: "Fetch the full history", bundle: .module), description: "--unshallow")
            }
        }
        SyncForm.Options(commands: command.map { [$0] } ?? [], hasContent: false) { EmptyView() }
    }

    @ViewBuilder var pullTab: some View {
        HStack(alignment: .top, spacing: Vrai.Space.s12) {
            SyncForm.Field(label: String(localized: "Remote", bundle: .module)) {
                SyncForm.Select(selection: $remote, options: remoteOptions, label: String(localized: "Remote", bundle: .module))
            }
            SyncForm.Input(label: String(localized: "Branch", bundle: .module), text: $branch, mono: true, onSubmit: go)
        }
        SyncForm.Radios(selection: $mode, choices: [
            SyncForm.Choice(value: PullMode.merge, label: String(localized: "Merge", bundle: .module), description: String(localized: "Keeps both histories; adds a merge commit when they diverged.", bundle: .module)),
            SyncForm.Choice(value: PullMode.rebase, label: String(localized: "Rebase", bundle: .module), description: String(localized: "Replays your \(n(current?.ahead ?? 0, "commit")) on top. Rewrites them.", bundle: .module)),
            SyncForm.Choice(value: PullMode.fastForwardOnly, label: String(localized: "Fast-forward only", bundle: .module), description: String(localized: "Stops if your branch has commits the remote lacks.", bundle: .module))
        ], cards: true, label: String(localized: "How to integrate", bundle: .module))
        SyncForm.Checkbox(isOn: $autostash, label: String(localized: "Set uncommitted changes aside while pulling", bundle: .module), description: "--autostash")
        SyncForm.Options(commands: command.map { [$0] } ?? [], hasContent: false) { EmptyView() }
    }

    @ViewBuilder var pushTab: some View {
        HStack(alignment: .top, spacing: Vrai.Space.s12) {
            SyncForm.Field(label: String(localized: "Remote", bundle: .module)) {
                SyncForm.Select(selection: $remote, options: remoteOptions, label: String(localized: "Remote", bundle: .module))
            }
            SyncForm.Input(label: String(localized: "As branch", bundle: .module), text: $branch, mono: true, onSubmit: go)
        }
        let pending = pending
        if pending.total > 0 {
            VStack(alignment: .leading, spacing: Vrai.Space.s6) {
                Text("\(n(pending.total, "commit")) to push:", bundle: .module)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.textSecondary)
                SyncForm.CommitList(commits: pending.commits, total: pending.total)
            }
        }
        if behind > 0, force == .none, current?.upstream == remote + "/" + branch {
            SyncForm.Callout(tone: .warning, title: String(localized: "\(remote) has \(n(behind, "commit")) you don't have", bundle: .module), message: String(localized: "A normal push will be rejected. Pull first, or force push with lease to replace them.", bundle: .module))
        }
        SyncForm.Checkbox(isOn: $setUpstream, label: String(localized: "Track \(remote)/\(branch.isEmpty ? String(localized: "branch", bundle: .module) : branch) as the upstream", bundle: .module), description: "-u")
        SyncForm.Checkbox(isOn: $tags, label: String(localized: "Push annotated tags on these commits", bundle: .module), description: "--follow-tags")
        SyncForm.Options(commands: command.map { [$0] } ?? [], detail: String(localized: "Force, hooks", bundle: .module)) {
            SyncForm.Radios(selection: $force, choices: forceChoices, label: String(localized: "Force", bundle: .module))
            SyncForm.Checkbox(isOn: $noVerify, label: String(localized: "Skip the pre-push hook", bundle: .module), description: "--no-verify")
            if preferences.expert {
                SyncForm.Input(label: String(localized: "Push options", bundle: .module), text: $pushOptions, placeholder: "ci.skip", hint: String(localized: "Sent to the server with -o. Separate several with commas.", bundle: .module), mono: true)
            }
        }
    }

    var forceChoices: [SyncForm.Choice<PushForce>] {
        var choices = [
            SyncForm.Choice(value: PushForce.none, label: String(localized: "Normal push", bundle: .module)),
            SyncForm.Choice(value: PushForce.withLease, label: String(localized: "Force with lease", bundle: .module), description: String(localized: "Replaces the remote branch only if nobody pushed since your last fetch.", bundle: .module))
        ]
        if preferences.expert {
            choices.append(SyncForm.Choice(value: PushForce.force, label: String(localized: "Force", bundle: .module), description: String(localized: "Replaces it no matter what. Others' commits can be lost.", bundle: .module), danger: true))
        }
        return choices
    }

    var defaultRemoteBranch: String? {
        guard let current else { return nil }
        if let upstream = current.upstream, upstream.hasPrefix(remote + "/") { return String(upstream.dropFirst(remote.count + 1)) }
        return current.name
    }

    var customTarget: String? {
        let trimmed = branch.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != defaultRemoteBranch else { return nil }
        return trimmed
    }

    func build() async {
        switch tab {
        case .fetch:
            command = store.fetchCommand(remote: fetchFrom == Self.allRemotes ? nil : fetchFrom, all: fetchFrom == Self.allRemotes, prune: prune, tags: fetchTags, depth: Int(depth), unshallow: unshallow)
        case .pull:
            command = store.pullCommand(mode: mode, autostash: autostash, remote: remote, branch: branch.trimmingCharacters(in: .whitespaces))
        case .push:
            guard let current else {
                command = nil
                return
            }
            if let target = customTarget {
                command = SyncCommands.push(remote: remote, refspec: "refs/heads/" + current.name + ":refs/heads/" + target, force: force, setUpstream: setUpstream, tags: tags, noVerify: noVerify, pushOptions: options)
            } else {
                command = try? await store.pushCommand(remote: remote, branch: current.name, force: force, setUpstream: setUpstream, tags: tags, noVerify: noVerify, pushOptions: options)
            }
        }
    }

    func loadDefaults() async {
        let defaults = await store.pullDefaults()
        mode = defaults.mode
        autostash = defaults.autostash
    }

    func go() {
        guard enabled else { return }
        let sync = window.sync
        window.sheets.dismiss()
        switch tab {
        case .push:
            sync.push(force: force, remote: remote, branch: current?.name, remoteBranch: customTarget, setUpstream: setUpstream, tags: tags, noVerify: noVerify, pushOptions: options)
        case .pull:
            sync.pull(mode: mode, autostash: autostash, remote: remote, branch: branch.trimmingCharacters(in: .whitespaces))
        case .fetch:
            let all = fetchFrom == Self.allRemotes
            sync.fetch(remote: all ? nil : fetchFrom, all: all, prune: prune, tags: fetchTags, depth: Int(depth), unshallow: unshallow)
        }
    }

    struct CommandKey: Hashable {
        var tab: SyncTab
        var remote: String
        var branch: String
        var setUpstream: Bool
        var tags: Bool
        var force: PushForce
        var noVerify: Bool
        var pushOptions: [String]
        var mode: PullMode
        var autostash: Bool
        var fetchFrom: String
        var prune: Bool
        var fetchTags: Bool
        var depth: Int?
        var unshallow: Bool
        var head: OID?
    }
}

enum PendingCommits {
    static let walkLimit = 5000

    static func walk(history: HistoryState, from tip: OID, excluding: [OID], known: Int?, limit: Int = 4) -> (commits: [(id: OID, subject: String)], total: Int) {
        var excluded = Set<OID>()
        var queue = excluding
        while let next = queue.popLast(), excluded.count < walkLimit {
            guard excluded.insert(next).inserted, let index = history.index[next] else { continue }
            queue.append(contentsOf: history.commits[index].parents)
        }
        var found: [(id: OID, subject: String)] = []
        var seen = Set<OID>()
        var frontier = [tip]
        var head = 0
        while head < frontier.count, found.count < walkLimit {
            let next = frontier[head]
            head += 1
            guard !excluded.contains(next), seen.insert(next).inserted, let index = history.index[next] else { continue }
            let commit = history.commits[index]
            found.append((commit.id, commit.subject))
            frontier.append(contentsOf: commit.parents)
        }
        return (Array(found.prefix(limit)), known ?? found.count)
    }
}
