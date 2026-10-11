import SwiftUI
import VraiCore
import VraiGit

@MainActor
enum RewriteActions {
    static func openMerge(_ window: WindowModel, source: String? = nil, mode: MergeMode = .auto) {
        window.sheets.present { MergeSheet(initialSource: source, initialMode: mode) }
    }

    static func openRebase(_ window: WindowModel, onto: String? = nil) {
        window.sheets.present { RebaseSheet(initialOnto: onto) }
    }

    static func openInteractive(_ window: WindowModel, onto: String? = nil) {
        guard let target = onto ?? defaultInteractiveBase(window) else {
            window.sheets.present { RebaseSheet(initialOnto: nil) }
            return
        }
        window.sheets.present { InteractiveRebaseSheet(initialOnto: target) }
    }

    static func openReset(_ window: WindowModel, target: OID, label: String? = nil) {
        window.sheets.present { ResetSheet(target: target, label: label) }
    }

    static func openCherryPick(_ window: WindowModel, ids: [OID]) {
        window.sheets.present { CherryPickSheet(ids: ids) }
    }

    static func openStash(_ window: WindowModel, paths: [String]? = nil) {
        guard !(window.store.snapshot?.working.isEmpty ?? true) else {
            window.toasts.show(Toast(message: String(localized: "Nothing to stash", bundle: .module), detail: String(localized: "The working tree is clean.", bundle: .module), icon: "tray.full"))
            return
        }
        window.sheets.present { StashSheet(paths: paths) }
    }

    static func openStashBranch(_ window: WindowModel, index: Int) {
        window.sheets.present { StashBranchSheet(index: index) }
    }

    static func openBisect(_ window: WindowModel, good: String? = nil, bad: String? = nil) {
        window.sheets.present { BisectSheet(initialGood: good, initialBad: bad) }
    }

    static func defaultBranchName(_ snapshot: RepositorySnapshot?) -> String? {
        guard let snapshot else { return nil }
        let current = snapshot.head.branchName
        for name in ["main", "master", "trunk"] where name != current && snapshot.branches.contains(where: { $0.name == name }) {
            return name
        }
        return nil
    }

    static func defaultInteractiveBase(_ window: WindowModel) -> String? {
        let snapshot = window.store.snapshot
        if let name = defaultBranchName(snapshot) { return name }
        return snapshot?.currentBranch?.upstream
    }

    static func defaultRebaseBase(_ window: WindowModel) -> String? {
        let snapshot = window.store.snapshot
        let local = defaultBranchName(snapshot)
        if snapshot?.currentBranch?.upstream != nil, let local {
            let remote = snapshot?.remoteBranches.first { $0.name == local && $0.remote == "origin" } ?? snapshot?.remoteBranches.first { $0.name == local }
            if let remote { return remote.fullName }
        }
        return local ?? snapshot?.currentBranch?.upstream
    }

    static func merge(_ window: WindowModel, source: String, mode: MergeMode, message: String? = nil, strategyOption: String? = nil, count: Int? = nil) {
        let store = window.store
        let head = window.headName
        Task {
            var squashed = count
            if mode == .squash, squashed == nil { squashed = await store.commitsBetween("HEAD", source).count }
            do {
                let outcome = try await store.merge(source: source, mode: mode, message: message, strategyOption: strategyOption)
                switch outcome {
                case .upToDate:
                    window.toasts.show(Toast(message: String(localized: "Already up to date", bundle: .module), detail: String(localized: "\(head) already has everything on \(source).", bundle: .module)))
                case .fastForwarded:
                    window.toasts.show(undoToast(window, message: String(localized: "Fast-forwarded \(head) to \(source)", bundle: .module), icon: "arrow.triangle.merge"))
                case .merged:
                    window.toasts.show(undoToast(window, message: String(localized: "Merged \(source) into \(head)", bundle: .module), icon: "arrow.triangle.merge"))
                case .squashed:
                    window.show(.changes)
                    window.toasts.show(Toast(message: String(localized: "Squashed \(n(squashed ?? 0, "commit")) from \(source)", bundle: .module), detail: String(localized: "They're staged. Commit to finish the merge.", bundle: .module), icon: "rectangle.compress.vertical"))
                }
            } catch let error as GitError where error.code == .notFastForward {
                window.toasts.show(Toast(tone: .danger, message: String(localized: "Can't fast-forward \(head)", bundle: .module), detail: String(localized: "The branches have diverged. Merge with a merge commit instead.", bundle: .module)))
            } catch {
                report(error, window, failure: String(localized: "The merge didn't finish", bundle: .module))
            }
        }
    }

    static func rebase(_ window: WindowModel, onto: String, autostash: Bool, updateRefs: Bool, inBackground: Bool) {
        let store = window.store
        let head = window.headName
        let shown = shortName(onto)
        Task {
            do {
                let outcome = try await store.rebase(onto: onto, autostash: autostash, updateRefs: updateRefs, inBackground: inBackground)
                switch outcome {
                case .upToDate:
                    window.toasts.show(Toast(message: String(localized: "Already up to date", bundle: .module), detail: String(localized: "\(head) already contains \(shown).", bundle: .module)))
                case .fastForwarded:
                    window.toasts.show(undoToast(window, message: String(localized: "Rebased \(head) onto \(shown)", bundle: .module), detail: String(localized: "Fast-forwarded.", bundle: .module), icon: "arrow.triangle.swap"))
                case .rebased(let commits):
                    window.toasts.show(undoToast(window, message: String(localized: "Rebased \(head) onto \(shown)", bundle: .module), detail: String(localized: "\(n(commits, "commit")) rewritten.", bundle: .module) + forcePushNote(store), icon: "arrow.triangle.swap"))
                }
                selectHead(store)
            } catch {
                selectHead(store)
                report(error, window, failure: String(localized: "The rebase didn't finish", bundle: .module))
            }
        }
    }

    static func interactiveRebase(_ window: WindowModel, onto: String, steps: [RebaseStep]) {
        let store = window.store
        let head = window.headName
        let shown = shortName(onto)
        Task {
            do {
                try await store.interactiveRebase(onto: onto, plan: steps)
                let reworded = steps.count { $0.action == .reword }
                let squashed = steps.count { $0.action.foldsIntoPrevious }
                let dropped = steps.count { $0.action == .drop }
                var parts: [String] = []
                if reworded > 0 { parts.append(String(localized: "\(n(reworded, "commit")) reworded", bundle: .module)) }
                if squashed > 0 { parts.append(String(localized: "\(n(squashed, "commit")) squashed", bundle: .module)) }
                if dropped > 0 { parts.append(String(localized: "\(n(dropped, "commit")) dropped", bundle: .module)) }
                let detail = parts.isEmpty ? String(localized: "\(n(steps.count, "commit")) replayed.", bundle: .module) : parts.joined(separator: ", ")
                window.toasts.show(undoToast(window, message: String(localized: "Rebased \(head) onto \(shown)", bundle: .module), detail: detail, icon: "arrow.triangle.swap"))
                selectHead(store)
            } catch {
                selectHead(store)
                report(error, window, failure: String(localized: "The rebase didn't finish", bundle: .module))
            }
        }
    }

    static func cherryPick(_ window: WindowModel, ids: [OID], recordOrigin: Bool = false, noCommit: Bool = false, mainline: Int? = nil) {
        let store = window.store
        let head = window.headName
        Task {
            let what = ids.count == 1 ? ids[0].short : n(ids.count, "commit")
            let subject = ids.count == 1 ? await store.subject(of: ids[0]) : nil
            do {
                try await store.cherryPick(ids: ids, recordOrigin: recordOrigin, noCommit: noCommit, mainline: mainline)
                if noCommit {
                    window.toasts.show(Toast(message: String(localized: "Cherry-picked \(what) onto \(head)", bundle: .module), detail: String(localized: "The changes are staged, not committed yet.", bundle: .module), icon: "arrow.turn.down.right", action: String(localized: "Show changes", bundle: .module)) { window.show(.changes) })
                } else {
                    window.toasts.show(undoToast(window, message: String(localized: "Cherry-picked \(what) onto \(head)", bundle: .module), detail: subject, icon: "arrow.turn.down.right"))
                    selectHead(store)
                }
            } catch {
                report(error, window, failure: String(localized: "The cherry-pick didn't finish", bundle: .module))
            }
        }
    }

    static func revert(_ window: WindowModel, id: OID) {
        let store = window.store
        Task {
            var mainline: Int?
            if await store.isMergeCommit(id) { mainline = 1 }
            do {
                try await store.revert(id: id, mainline: mainline)
                let made = store.snapshot?.headOID?.short ?? ""
                window.toasts.show(undoToast(window, message: String(localized: "Reverted \(id.short)", bundle: .module), detail: String(localized: "Made \(made), which undoes its changes.", bundle: .module), icon: "arrow.uturn.backward"))
                selectHead(store)
            } catch {
                report(error, window, failure: String(localized: "The revert didn't finish", bundle: .module))
            }
        }
    }

    static func reset(_ window: WindowModel, target: OID, mode: ResetMode, count: Int) {
        let store = window.store
        let head = window.headName
        Task {
            do {
                try await store.reset(to: target.rawValue, mode: mode)
                let detail: String
                switch mode {
                case .soft: detail = String(localized: "\(n(count, "commit")) back in staged changes.", bundle: .module)
                case .mixed: detail = String(localized: "\(n(count, "commit")) back in unstaged changes.", bundle: .module)
                case .hard: detail = String(localized: "A copy of what was discarded stays in Undo history.", bundle: .module)
                case .keep: detail = String(localized: "Your uncommitted changes were kept.", bundle: .module)
                }
                window.toasts.show(undoToast(window, message: String(localized: "Reset \(head) to \(target.short)", bundle: .module), detail: detail, icon: "arrow.counterclockwise"))
                if store.snapshot?.working.isEmpty == false, mode != .hard { store.select(.wip) } else { selectHead(store) }
            } catch {
                report(error, window, failure: String(localized: "The reset didn't finish", bundle: .module))
            }
        }
    }

    static func stash(_ window: WindowModel, message: String?, includeUntracked: Bool, keepIndex: Bool, onlyStaged: Bool, paths: [String], count: Int) {
        let store = window.store
        Task {
            do {
                try await store.stash(message: message, includeUntracked: includeUntracked, keepIndex: keepIndex, onlyStaged: onlyStaged, paths: paths)
                let saved = store.snapshot?.stashes.first.map { StashesView.title($0.message) }
                window.toasts.show(Toast(message: String(localized: "Stashed \(n(count, "change"))", bundle: .module), detail: saved, icon: "tray.and.arrow.down", action: String(localized: "Show", bundle: .module)) { window.show(.stashes) })
            } catch let error as GitError where error.code == .nothingToStash {
                window.toasts.show(Toast(message: String(localized: "No local changes to save", bundle: .module), icon: "tray.full"))
            } catch {
                report(error, window, failure: String(localized: "The stash didn't finish", bundle: .module))
            }
        }
    }

    static func applyStash(_ window: WindowModel, index: Int, pop: Bool) {
        let store = window.store
        Task {
            let files = (try? await store.stashDetail(index: index))?.files.count
            do {
                try await store.applyStash(index: index, pop: pop)
                let selector = "stash@{\(index)}"
                window.toasts.show(Toast(
                    message: pop ? String(localized: "Popped \(selector)", bundle: .module) : String(localized: "Applied \(selector)", bundle: .module),
                    detail: files.map { String(localized: "\(n($0, "file")) back in Changes.", bundle: .module) },
                    icon: "tray.and.arrow.up",
                    action: String(localized: "Show changes", bundle: .module)
                ) { window.show(.changes) })
            } catch {
                report(error, window, failure: String(localized: "The stash didn't apply", bundle: .module))
            }
        }
    }

    static func confirmDropStash(_ window: WindowModel, index: Int) {
        let store = window.store
        guard let stash = store.snapshot?.stashes.first(where: { $0.index == index }) else { return }
        Task {
            let files = (try? await store.stashDetail(index: index))?.files.count ?? 0
            let label = "\u{201C}" + StashesView.title(stash.message) + "\u{201D}"
            window.alerts.present(AlertRequest(
                title: String(localized: "Drop stash@{\(index)}?", bundle: .module),
                message: String(localized: "\(label) holds changes to \(n(files, "file")). A copy stays in Undo history for 14 days.", bundle: .module),
                actions: [
                    AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel),
                    AlertAction(title: String(localized: "Drop stash", bundle: .module), role: .destructive) { dropStash(window, index: index) }
                ]
            ))
        }
    }

    static func dropStash(_ window: WindowModel, index: Int) {
        let store = window.store
        Task {
            do {
                try await store.dropStash(index: index)
                window.toasts.show(undoToast(window, message: String(localized: "Dropped stash@{\(index)}", bundle: .module), detail: String(localized: "A copy stays in Undo history for 14 days.", bundle: .module), icon: "trash"))
            } catch {
                report(error, window, failure: String(localized: "The stash wasn't dropped", bundle: .module))
            }
        }
    }

    static func branchFromStash(_ window: WindowModel, index: Int, name: String) {
        let store = window.store
        Task {
            do {
                try await store.branchFromStash(index: index, name: name)
                window.show(.changes)
                window.toasts.show(Toast(message: String(localized: "Created \(name) from stash@{\(index)}", bundle: .module), detail: String(localized: "Its changes are in Changes.", bundle: .module), icon: "arrow.triangle.branch"))
            } catch {
                report(error, window, failure: String(localized: "The branch wasn't created", bundle: .module))
            }
        }
    }

    static func startBisect(_ window: WindowModel, bad: String, good: String) {
        let store = window.store
        Task {
            do {
                let outcome = try await store.startBisect(bad: bad, good: good)
                window.show(.history)
                showBisect(outcome, window: window)
            } catch {
                report(error, window, failure: String(localized: "Bisect didn't start", bundle: .module))
            }
        }
    }

    static func markBisect(_ window: WindowModel, _ verdict: BisectVerdict, at commit: OID? = nil) {
        let store = window.store
        RewriteActivity.shared.begin(window, "bisect-" + verdict.rawValue)
        Task {
            defer { RewriteActivity.shared.end(window) }
            do {
                let outcome = if let commit { try await store.markBisect(verdict, at: commit) } else { try await store.markBisect(verdict) }
                showBisect(outcome, window: window)
            } catch {
                report(error, window, failure: String(localized: "Bisect didn't move on", bundle: .module))
            }
        }
    }

    static func showBisect(_ outcome: BisectOutcome, window: WindowModel) {
        let store = window.store
        switch outcome {
        case .found(let id):
            store.selectCommit(id, scroll: true)
            Task {
                let subject = await store.subject(of: id)
                window.toasts.show(Toast(message: String(localized: "\(id.short) is the first bad commit", bundle: .module), detail: subject, icon: "scope", action: String(localized: "Show", bundle: .module)) { store.showRef(id.rawValue) })
            }
        case .testing(let current, _):
            if let current = current ?? store.snapshot?.headOID { store.selectCommit(current, scroll: true) }
        case .inconclusive:
            selectHead(store)
        }
    }

    static func endBisect(_ window: WindowModel) {
        let store = window.store
        RewriteActivity.shared.begin(window, "end")
        Task {
            defer { RewriteActivity.shared.end(window) }
            do {
                try await store.endBisect()
                window.toasts.show(Toast(message: String(localized: "Ended bisect", bundle: .module), detail: String(localized: "Back on \(window.headName).", bundle: .module), icon: "flag.checkered"))
                selectHead(store)
            } catch {
                report(error, window, failure: String(localized: "Bisect didn't end", bundle: .module))
            }
        }
    }

    static func continueOperation(_ window: WindowModel, skip: Bool = false) {
        let store = window.store
        guard let state = store.snapshot?.state else { return }
        let head = window.headName
        let onto = store.stateDetails.ontoName
        RewriteActivity.shared.begin(window, skip ? "skip" : "continue")
        Task {
            defer { RewriteActivity.shared.end(window) }
            do {
                if skip { try await store.skipStep() } else { try await store.continueOperation() }
                guard store.snapshot?.state.isOperationInProgress != true else {
                    selectHead(store)
                    return
                }
                switch state {
                case .rebasing(_, _, _, _, let branch, _):
                    let name = branch ?? window.headName
                    let detail = onto.map { String(localized: "\(name) now sits on \($0).", bundle: .module) } ?? ""
                    window.toasts.show(undoToast(window, message: String(localized: "Rebase finished", bundle: .module), detail: detail + forcePushNote(store), icon: "checkmark.circle"))
                case .merging(let source):
                    let message = source.map { String(localized: "Merged \($0) into \(head)", bundle: .module) } ?? String(localized: "Committed the merge", bundle: .module)
                    window.toasts.show(undoToast(window, message: message, icon: "arrow.triangle.merge"))
                case .cherryPicking(let id):
                    let what = id?.short ?? String(localized: "the commit", bundle: .module)
                    window.toasts.show(undoToast(window, message: String(localized: "Cherry-picked \(what) onto \(head)", bundle: .module), icon: "arrow.turn.down.right"))
                case .reverting(let id):
                    let what = id?.short ?? String(localized: "the commit", bundle: .module)
                    window.toasts.show(undoToast(window, message: String(localized: "Reverted \(what)", bundle: .module), icon: "arrow.uturn.backward"))
                case .applyingPatches:
                    window.toasts.show(Toast(message: String(localized: "Applied the patches", bundle: .module), icon: "checkmark.circle"))
                default:
                    break
                }
                selectHead(store)
            } catch {
                selectHead(store)
                report(error, window, failure: skip ? String(localized: "Skip didn't finish", bundle: .module) : String(localized: "Continue didn't finish", bundle: .module))
            }
        }
    }

    static func abort(_ window: WindowModel) {
        let store = window.store
        guard let state = store.snapshot?.state else { return }
        if case .bisecting = state {
            endBisect(window)
            return
        }
        RewriteActivity.shared.begin(window, "abort")
        Task {
            defer { RewriteActivity.shared.end(window) }
            do {
                try await store.abort()
                let message: String
                switch state {
                case .merging: message = String(localized: "Aborted the merge", bundle: .module)
                case .rebasing: message = String(localized: "Aborted the rebase", bundle: .module)
                case .cherryPicking: message = String(localized: "Aborted the cherry-pick", bundle: .module)
                case .reverting: message = String(localized: "Aborted the revert", bundle: .module)
                default: message = String(localized: "Aborted", bundle: .module)
                }
                window.toasts.show(Toast(message: message, detail: String(localized: "\(window.headName) is back where it was.", bundle: .module), icon: "arrow.uturn.backward"))
                selectHead(store)
            } catch {
                report(error, window, failure: String(localized: "Abort didn't finish", bundle: .module))
            }
        }
    }

    static func markResolved(_ window: WindowModel, path: String, done: (@MainActor (Bool) -> Void)? = nil) {
        let store = window.store
        Task {
            do {
                try await store.markResolved(path: path)
                let left = store.snapshot?.working.count { $0.status == .conflicted } ?? 0
                let name = PathParts.split(path).name
                window.toasts.show(Toast(
                    message: String(localized: "Marked \(name) as resolved", bundle: .module),
                    detail: left > 0 ? String(localized: "\(n(left, "conflict")) left.", bundle: .module) : String(localized: "All conflicts resolved. Commit the merge to finish.", bundle: .module),
                    icon: "checkmark.circle"
                ))
                done?(true)
            } catch {
                report(error, window, failure: String(localized: "The file wasn't marked resolved", bundle: .module))
                done?(false)
            }
        }
    }

    static func openMergeTool(_ window: WindowModel, path: String) {
        let store = window.store
        let name = PathParts.split(path).name
        window.toasts.show(Toast(message: String(localized: "Opened \(name) in FileMerge", bundle: .module), icon: "arrow.triangle.merge"))
        Task {
            do {
                try await store.openMergeTool(path: path)
            } catch {
                report(error, window, failure: String(localized: "The merge tool didn't open", bundle: .module))
            }
        }
    }

    static func undo(_ window: WindowModel) {
        let store = window.store
        Task {
            do {
                if let entry = try await store.undoLast() {
                    window.toasts.show(Toast(message: String(localized: "Undid: \(entry.label)", bundle: .module), icon: "arrow.uturn.backward"))
                    selectHead(store)
                } else {
                    window.toasts.show(Toast(message: String(localized: "Nothing to undo", bundle: .module), detail: String(localized: "Edit, Undo history lists older changes you can restore.", bundle: .module)))
                }
            } catch {
                report(error, window, failure: String(localized: "Undo didn't finish", bundle: .module))
            }
        }
    }

    static func confirmDropBranch(_ window: WindowModel, name: String) {
        let head = window.headName
        guard name != head, window.store.snapshot?.head.branchName != nil else { return }
        window.alerts.present(AlertRequest(
            title: String(localized: "Drop \(name) on \(head)", bundle: .module),
            message: String(localized: "Merge its commits into \(head), or replay \(head) on top of it.", bundle: .module),
            actions: [
                AlertAction(title: String(localized: "Merge \(name) into \(head)\u{2026}", bundle: .module)) { openMerge(window, source: name) },
                AlertAction(title: String(localized: "Rebase \(head) onto \(name)\u{2026}", bundle: .module)) { openRebase(window, onto: name) },
                AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel)
            ]
        ))
    }

    static func confirmDropCommit(_ window: WindowModel, id: OID) {
        let head = window.headName
        guard window.store.snapshot?.headOID != id else { return }
        Task {
            let subject = await window.store.subject(of: id)
            let inHead = await HeadReach.contains(id, store: window.store)
            if inHead {
                window.toasts.show(Toast(message: String(localized: "\(head) already has \(id.short)", bundle: .module), detail: subject))
                return
            }
            window.alerts.present(AlertRequest(
                title: String(localized: "Drop \(id.short) on \(head)", bundle: .module),
                message: subject.map { String(localized: "Copy \u{201C}\($0)\u{201D} onto \(head) as a new commit.", bundle: .module) },
                actions: [
                    AlertAction(title: String(localized: "Cherry-pick onto \(head)", bundle: .module)) { cherryPick(window, ids: [id]) },
                    AlertAction(title: String(localized: "Cherry-pick with options\u{2026}", bundle: .module)) { openCherryPick(window, ids: [id]) },
                    AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel)
                ]
            ))
        }
    }

    static func presentAfterSheet(_ window: WindowModel, _ request: AlertRequest) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            window.alerts.present(request)
        }
    }

    static func undoToast(_ window: WindowModel, message: String, detail: String? = nil, icon: String) -> Toast {
        Toast(message: message, detail: detail, icon: icon, action: String(localized: "Undo", bundle: .module)) { undo(window) }
    }

    static func forcePushNote(_ store: RepositoryStore) -> String {
        guard let branch = store.snapshot?.currentBranch, branch.behind > 0, let upstream = branch.upstream else { return "" }
        return " " + String(localized: "Force push with lease to update \(upstream).", bundle: .module)
    }

    static func selectHead(_ store: RepositoryStore) {
        guard let head = store.snapshot?.headOID else { return }
        store.selectCommit(head, scroll: true)
    }

    static func shortName(_ revision: String) -> String {
        guard let oid = OID(revision) else { return revision }
        return oid.short
    }

    static func report(_ error: Error, _ window: WindowModel, failure: String) {
        guard let error = error as? GitError else {
            window.alerts.present(AlertRequest(title: failure, message: String(describing: error), actions: [AlertAction(title: String(localized: "Close", bundle: .module), role: .cancel)]))
            return
        }
        switch error.code {
        case .conflicts:
            window.show(.changes)
        case .stoppedForEdit, .cancelled:
            break
        default:
            let copy = ErrorCopy(error)
            let title: String
            if case .unknown = error.code { title = failure } else { title = copy.title }
            window.alerts.present(AlertRequest(title: title, message: copy.message, actions: [AlertAction(title: String(localized: "Close", bundle: .module), role: .cancel)]))
        }
    }
}

@MainActor
@Observable
final class RewriteActivity {
    static let shared = RewriteActivity()
    private(set) var running: [ObjectIdentifier: String] = [:]

    func begin(_ window: WindowModel, _ key: String) {
        running[ObjectIdentifier(window)] = key
    }

    func end(_ window: WindowModel) {
        running[ObjectIdentifier(window)] = nil
    }

    func key(for window: WindowModel) -> String? {
        running[ObjectIdentifier(window)]
    }
}

@MainActor
enum HeadReach {
    private static var cache: [ObjectIdentifier: (key: String, ids: Set<OID>)] = [:]

    static func reachable(_ store: RepositoryStore) -> Set<OID> {
        let history = store.history
        guard let head = store.snapshot?.headOID else { return [] }
        let key = head.rawValue + ":" + String(history.commits.count)
        if let hit = cache[ObjectIdentifier(store)], hit.key == key { return hit.ids }
        var reached: Set<OID> = [head]
        for commit in history.commits where reached.contains(commit.id) {
            for parent in commit.parents { reached.insert(parent) }
        }
        cache[ObjectIdentifier(store)] = (key, reached)
        return reached
    }

    static func contains(_ id: OID, store: RepositoryStore) async -> Bool {
        if reachable(store).contains(id) { return true }
        guard let head = store.snapshot?.headOID, store.history.index[id] == nil else { return false }
        return (try? await store.isAncestor(id, of: head)) ?? false
    }
}
