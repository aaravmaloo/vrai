import AppKit
import SwiftUI
import VraiCore
import VraiGit

@MainActor
final class IslandRouter {
    weak var window: WindowModel?
    let island: IslandCenter
    var routed: Set<UUID> = []
    var handoffUntil = Date.distantPast
    var stateID: UUID?
    var stateKind: String?

    init(window: WindowModel, island: IslandCenter = .shared) {
        self.window = window
        self.island = island
    }

    static func activity(for toast: Toast, source: String?) -> IslandActivity {
        let phase: IslandActivity.Phase = if toast.busy {
            .running
        } else {
            switch toast.tone {
            case .danger: .failure
            case .warning: .warning
            case .info, .accent: .info
            case .neutral, .success: .success
            }
        }
        var actions: [IslandAction] = []
        if let title = toast.action {
            let perform = toast.onAction ?? {}
            actions.append(IslandAction(title: title, prominent: !toast.busy, activates: !toast.busy, perform: perform))
        }
        let linger = toast.busy ? nil : toast.timeout.flatMap { $0 < 60 ? $0 : nil }
        let attention = (phase == .failure || phase == .warning) && toast.action != nil
        return IslandActivity(id: toast.id, phase: phase, title: toast.message, detail: toast.detail, icon: phase == .info ? (toast.icon ?? toast.tone.symbol) : toast.icon, source: source, actions: actions, linger: linger, attention: attention)
    }

    func route(_ toast: Toast) -> Bool {
        guard island.isActive, let window else { return false }
        let handoff = Date() < handoffUntil
        let wanted: Bool
        if toast.busy {
            wanted = island.allows(.sync)
        } else if handoff || !NSApp.isActive {
            wanted = true
        } else {
            wanted = island.mode == .everything && island.hasNotch && toast.timeout != Toast.brief
        }
        guard wanted else { return false }
        if handoff { handoffUntil = .distantPast }
        island.show(Self.activity(for: toast, source: window.repositoryName))
        if toast.busy { routed.insert(toast.id) }
        return true
    }

    func dismissed(_ id: UUID) {
        guard routed.remove(id) != nil else { return }
        handoffUntil = Date().addingTimeInterval(0.6)
        island.dismiss(id, after: 0.35)
    }

    func syncState(_ snapshot: RepositorySnapshot?) {
        guard let window, island.allows(.states), let snapshot, let next = Self.stateActivity(snapshot, window: window) else {
            clearState()
            return
        }
        if let id = stateID, island.contains(id), next.kind == stateKind {
            island.update(id) { activity in
                activity.title = next.activity.title
                activity.detail = next.activity.detail
                activity.badge = next.activity.badge
                activity.progress = next.activity.progress
                activity.accessory = next.activity.accessory
                activity.tint = next.activity.tint
                activity.actions = next.activity.actions
            }
            return
        }
        if let id = stateID { island.dismiss(id, after: 0) }
        stateID = next.activity.id
        stateKind = next.kind
        island.show(next.activity)
    }

    func clearState() {
        if let id = stateID { island.dismiss(id, after: 0.1) }
        stateID = nil
        stateKind = nil
    }

    static func stateActivity(_ snapshot: RepositorySnapshot, window: WindowModel) -> (kind: String, activity: IslandActivity)? {
        let head = BannerBuilder.headName(snapshot)
        let conflicts = snapshot.conflicts.count
        let source = window.repositoryName
        let resolve = IslandAction(title: String(localized: "Resolve", bundle: .module), prominent: true) { [weak window] in window?.showConflicts() }
        let abort = IslandAction(title: String(localized: "Abort", bundle: .module), activates: false) { [weak window] in
            if let window { RewriteActions.abort(window) }
        }
        func proceed(_ title: String) -> IslandAction {
            IslandAction(title: title, prominent: true, activates: false) { [weak window] in
                if let window { RewriteActions.continueOperation(window) }
            }
        }
        let tint: Tone = conflicts > 0 ? .warning : .accent
        func paused(_ title: String, _ detail: String, icon: String, badge: String?, actions: [IslandAction]) -> IslandActivity {
            IslandActivity(phase: .paused, title: title, detail: detail, icon: icon, source: source, badge: badge, tint: tint, actions: actions)
        }
        switch snapshot.state {
        case .rebasing(let step, let total, _, let reason, let branch, _):
            let name = branch ?? head
            let detail: String = if conflicts > 0 {
                String(localized: "Stopped on \(n(conflicts, "conflict")) at step \(step) of \(total). Resolve them, then continue.", bundle: .module)
            } else if reason == .edit {
                String(localized: "Stopped at step \(step) of \(total) so you can edit. Amend, then continue.", bundle: .module)
            } else {
                String(localized: "Paused at step \(step) of \(total).", bundle: .module)
            }
            let actions = conflicts > 0 ? [resolve, abort] : [proceed(String(localized: "Continue", bundle: .module)), abort]
            var activity = paused(String(localized: "Rebasing \(name)", bundle: .module), detail, icon: "arrow.triangle.swap", badge: String(step) + "/" + String(total), actions: actions)
            activity.progress = conflicts == 0 && total > 0 ? Double(step) / Double(total) : nil
            activity.accessory = conflicts > 0 ? "exclamationmark.triangle.fill" : nil
            return ("rebase", activity)
        case .merging(let from):
            let title = from.map { String(localized: "Merging \($0) into \(head)", bundle: .module) } ?? String(localized: "Merging into \(head)", bundle: .module)
            let detail = conflicts > 0 ? String(localized: "\(n(conflicts, "conflict")) left to resolve.", bundle: .module) : String(localized: "Every conflict is resolved. Commit to finish the merge.", bundle: .module)
            let actions = conflicts > 0 ? [resolve, abort] : [proceed(String(localized: "Commit", bundle: .module)), abort]
            var activity = paused(title, detail, icon: "arrow.triangle.merge", badge: conflicts > 0 ? String(conflicts) : nil, actions: actions)
            activity.accessory = conflicts > 0 ? "exclamationmark.triangle.fill" : "checkmark"
            return ("merge", activity)
        case .cherryPicking(let id), .reverting(let id):
            let picking: Bool = if case .cherryPicking = snapshot.state { true } else { false }
            let what = id?.short ?? String(localized: "a commit", bundle: .module)
            let title = picking ? String(localized: "Cherry-picking \(what)", bundle: .module) : String(localized: "Reverting \(what)", bundle: .module)
            let detail = conflicts > 0 ? String(localized: "\(n(conflicts, "conflict")) left to resolve.", bundle: .module) : String(localized: "Ready to continue.", bundle: .module)
            let actions = conflicts > 0 ? [resolve, abort] : [proceed(String(localized: "Continue", bundle: .module)), abort]
            var activity = paused(title, detail, icon: picking ? "arrow.turn.down.right" : "arrow.uturn.backward", badge: conflicts > 0 ? String(conflicts) : nil, actions: actions)
            activity.accessory = conflicts > 0 ? "exclamationmark.triangle.fill" : "checkmark"
            return (picking ? "pick" : "revert", activity)
        case .applyingPatches(let step, let total):
            let actions = conflicts > 0 ? [resolve, abort] : [proceed(String(localized: "Continue", bundle: .module)), abort]
            var activity = paused(String(localized: "Applying patches", bundle: .module), String(localized: "Stopped at patch \(step) of \(total).", bundle: .module), icon: "bandage", badge: String(step) + "/" + String(total), actions: actions)
            activity.progress = total > 0 ? Double(step) / Double(total) : nil
            return ("patches", activity)
        case .bisecting(_, _, let current, let remaining):
            func mark(_ verdict: BisectVerdict, _ title: String, prominent: Bool = false) -> IslandAction {
                IslandAction(title: title, prominent: prominent, activates: false) { [weak window] in
                    if let window { RewriteActions.markBisect(window, verdict) }
                }
            }
            let title = current.map { String(localized: "Bisect: test \($0.short)", bundle: .module) } ?? String(localized: "Bisecting \(head)", bundle: .module)
            let detail = remaining.map { String(localized: "About \(n($0, "step")) left. Try the build, then mark it.", bundle: .module) } ?? String(localized: "Try the build, then mark it.", bundle: .module)
            var activity = paused(title, detail, icon: "scope", badge: remaining.map { "~" + String($0) }, actions: [mark(.good, String(localized: "Good", bundle: .module), prominent: true), mark(.bad, String(localized: "Bad", bundle: .module)), mark(.skip, String(localized: "Skip", bundle: .module))])
            activity.tint = .accent
            activity.accessory = "questionmark.circle"
            return ("bisect", activity)
        default:
            return nil
        }
    }

    func progress(_ id: UUID?, _ progress: GitProgress?) {
        guard let id, routed.contains(id), let progress else { return }
        island.update(id) { activity in
            activity.progress = progress.fraction
            activity.badge = progress.percent.map { String($0) + "%" }
        }
    }

    func failed(_ id: UUID?, _ error: any Error) {
        guard let id, routed.contains(id) else { return }
        if case .cancelled? = (error as? GitError)?.code { return }
        let copy = (error as? GitError).map(ErrorCopy.init) ?? ErrorCopy(title: String(localized: "git stopped", bundle: .module), message: String(describing: error))
        routed.remove(id)
        handoffUntil = Date().addingTimeInterval(0.6)
        island.finish(id) { activity in
            activity.phase = .failure
            activity.title = copy.title
            activity.detail = nil
            activity.actions = [IslandAction(title: String(localized: "Show", bundle: .module)) {}]
            activity.progress = nil
            activity.badge = nil
            activity.linger = nil
        }
    }
}

struct IslandNotifier: Notifier {
    let fallback: any Notifier

    func post(_ notification: FetchNotification) async {
        let shown = await MainActor.run { IslandNotifier.show(notification) }
        if !shown { await fallback.post(notification) }
    }

    @MainActor static func show(_ notification: FetchNotification) -> Bool {
        let island = IslandCenter.shared
        guard island.allows(.fetch) else { return false }
        let model = SyncHub.shared.model(path: notification.repository)
        let lines = FetchNotification.lines(for: notification.newCommits)
        var actions: [IslandAction] = []
        if let model {
            let first = notification.newCommits.filter { $0.value > 0 }.keys.sorted().first
            actions.append(IslandAction(title: String(localized: "Show", bundle: .module)) { [weak model] in
                model?.window.show(.history)
                if let first { model?.store.showRef(first) }
            })
            if model.currentBranch?.upstream.map({ notification.newCommits[$0] ?? 0 > 0 }) == true {
                actions.append(IslandAction(title: String(localized: "Pull", bundle: .module), prominent: true, activates: false) { [weak model] in model?.pull() })
            }
        }
        var fetched = IslandActivity(
            phase: .info,
            title: lines.first ?? notification.title,
            detail: lines.count > 1 ? lines.dropFirst().joined(separator: ", ") : nil,
            icon: "arrow.triangle.2.circlepath",
            source: notification.title,
            badge: String(notification.newCommits.values.reduce(0, +)),
            tint: .accent,
            actions: actions,
            linger: 6
        )
        fetched.accessory = "arrow.down"
        island.show(fetched)
        return true
    }
}

@MainActor
enum ChecksAnnouncer {
    static func rows(_ checks: CommitChecks, now: Date) -> [IslandRow] {
        checks.sorted.map { run in
            IslandRow(id: run.id, title: run.title, detail: ChecksCopy.runDetail(run, now: now), state: run.state)
        }
    }

    static func handle(_ event: ChecksEvent, window: WindowModel) {
        guard window.preferences.checks, window.preferences.checksNotify else { return }
        let island = IslandCenter.shared
        let now = window.now ?? Date()
        switch event {
        case .started(let branch, let checks), .progressed(let branch, let checks):
            guard island.allows(.checks) else { return }
            let id = window.checksActivity(for: checks.sha)
            let activity = IslandActivity(
                id: id,
                phase: .running,
                title: String(localized: "Checks running on \(branch)", bundle: .module),
                detail: ChecksCopy.names(checks.runs),
                icon: "checklist",
                source: window.repositoryName,
                progress: checks.runs.isEmpty ? nil : Double(checks.finishedCount) / Double(checks.runs.count),
                badge: String(checks.finishedCount) + "/" + String(checks.runs.count),
                tint: checks.state == .failed ? .danger : .warning,
                rows: rows(checks, now: now)
            )
            if island.contains(id) {
                island.update(id) { current in
                    current.badge = activity.badge
                    current.progress = activity.progress
                    current.tint = activity.tint
                    current.rows = activity.rows
                    current.detail = activity.detail
                }
            } else if case .started = event {
                island.show(activity)
            }
        case .finished(let branch, let checks):
            finished(branch: branch, checks: checks, window: window, now: now)
        }
    }

    static func finished(branch: String, checks: CommitChecks, window: WindowModel, now: Date) {
        let island = IslandCenter.shared
        let id = window.checksActivity(for: checks.sha)
        window.forgetChecksActivity(checks.sha)
        let oid = OID(checks.sha)
        let failed = checks.state == .failed
        let title = failed
            ? String(localized: "\(ChecksCopy.names(checks.failed)) failed on \(branch)", bundle: .module)
            : (checks.state == .cancelled ? String(localized: "Checks cancelled on \(branch)", bundle: .module) : String(localized: "Checks passed on \(branch)", bundle: .module))
        let span = checks.runs.compactMap { $0.duration(now: now) }.max()
        let detail = [ChecksCopy.summary(checks), span.map(ChecksCopy.duration)].compactMap { $0 }.joined(separator: ", ")
        var actions: [IslandAction] = []
        if failed {
            if let url = checks.failed.first?.url ?? checks.url {
                actions.append(IslandAction(title: String(localized: "Logs", bundle: .module), activates: false) { NSWorkspace.shared.open(url) })
            }
            if window.checks.canWrite, !checks.rerunnable.isEmpty {
                actions.append(IslandAction(title: String(localized: "Re-run", bundle: .module), activates: false) { [weak window] in
                    guard let window, let oid else { return }
                    ChecksActions.rerun(window, id: oid, branch: branch)
                })
            }
        }
        actions.append(IslandAction(title: String(localized: "Show", bundle: .module), prominent: failed) { [weak window] in
            guard let window, let oid else { return }
            window.show(.history)
            window.store.selectCommit(oid, scroll: true)
        })
        if island.allows(.checks) {
            let activity = IslandActivity(
                id: id,
                phase: failed ? .failure : (checks.state == .cancelled ? .warning : .success),
                title: title,
                detail: detail,
                icon: "checklist",
                source: window.repositoryName,
                badge: failed ? String(localized: "CI failed", bundle: .module) : (checks.state == .cancelled ? String(localized: "CI stopped", bundle: .module) : String(localized: "CI passed", bundle: .module)),
                tint: failed ? .danger : (checks.state == .cancelled ? .warning : .success),
                rows: failed ? rows(CommitChecks(sha: checks.sha, runs: checks.failed), now: now) : [],
                actions: actions,
                linger: failed ? 12 : 4,
                attention: failed
            )
            if island.contains(id) {
                island.finish(id) { $0 = activity }
            } else {
                island.show(activity)
            }
            return
        }
        let toast = Toast(
            tone: failed ? .danger : .neutral,
            message: title,
            detail: detail,
            icon: failed ? "xmark.circle.fill" : "checkmark.circle",
            action: String(localized: "Show", bundle: .module)
        ) { [weak window] in
            guard let window, let oid else { return }
            window.show(.history)
            window.store.selectCommit(oid, scroll: true)
        }
        if window.sync.isKey {
            window.toasts.show(toast)
        } else if window.preferences.notifications {
            let note = FetchNotification(repository: window.reference.path, title: window.repositoryName, body: title + "\n" + detail, newCommits: [:])
            Task { await SyncHub.shared.notifier.post(note) }
        }
    }
}

extension SyncHub {
    func model(path: String) -> SyncModel? {
        allModels.first { $0.matches(context: path) }
    }
}

struct IslandWiring: ViewModifier {
    let window: WindowModel
    @Environment(\.appearsActive) private var active

    func body(content: Content) -> some View {
        let checks = window.checks
        content
            .onAppear {
                let model = window
                IslandCenter.shared.preferences = model.preferences
                IslandCenter.shared.mode = model.preferences.island
                model.router.syncState(model.store.snapshot)
                model.toasts.route = { [weak model] toast in model?.router.route(toast) ?? false }
                model.toasts.onDismiss = { [weak model] id in model?.router.dismissed(id) }
                checks.onEvent = { [weak model] event in
                    guard let model else { return }
                    ChecksAnnouncer.handle(event, window: model)
                }
                checks.enabled = window.preferences.checks
                if let snapshot = window.store.snapshot { checks.update(snapshot) }
                checks.start()
            }
            .onDisappear {
                window.router.clearState()
                checks.stop()
                window.toasts.route = nil
                window.toasts.onDismiss = nil
            }
            .onChange(of: window.preferences.island) { _, mode in
                IslandCenter.shared.mode = mode
                window.router.syncState(window.store.snapshot)
            }
            .onChange(of: window.preferences.checks) { _, on in checks.enabled = on }
            .onChange(of: window.preferences.islandStates) { _, _ in window.router.syncState(window.store.snapshot) }
            .onChange(of: active, initial: true) { _, value in checks.active = value }
            .onChange(of: window.store.snapshot) { _, snapshot in
                if let snapshot { checks.update(snapshot) }
                window.router.syncState(snapshot)
            }
            .onChange(of: window.store.selection) { _, selection in
                if case .commit(let id)? = selection { checks.request(id) }
            }
    }
}
