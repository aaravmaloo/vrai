import SwiftUI
import VraiCore
import VraiGit

enum SyncTab: String, Hashable {
    case fetch
    case pull
    case push
}

extension SyncModel {
    func openSync(_ tab: SyncTab, publish: Bool = false) {
        showSheet { SyncSheet(sync: self, tab: tab, publish: publish) }
    }

    func noRemotes(branch: String? = nil) {
        toasts.show(Toast(
            message: String(localized: "This repository has no remotes", bundle: .module),
            detail: branch.map { String(localized: "Add one to push \($0).", bundle: .module) } ?? String(localized: "Add one to fetch, pull and push.", bundle: .module),
            action: String(localized: "Add remote", bundle: .module)
        ) { [weak self] in self?.addRemote() })
    }

    func fetch(remote: String? = nil, all: Bool = false, prune: Bool? = true, tags: Bool = false, depth: Int? = nil, unshallow: Bool = false) {
        guard running[.fetch] == nil else { return }
        guard let snapshot, !snapshot.remotes.isEmpty else {
            noRemotes()
            return
        }
        let target = all ? nil : (remote ?? defaultRemote)
        let busy = all ? String(localized: "Fetching every remote", bundle: .module) : String(localized: "Fetching \(target ?? "")", bundle: .module)
        let handle = store.fetchOperation(remote: target, all: all, prune: prune, tags: tags, depth: depth, unshallow: unshallow)
        run(.fetch, handle, busy: busy, retry: { [weak self] in self?.fetch(remote: remote, all: all, prune: prune, tags: tags, depth: depth, unshallow: unshallow) }) { [weak self] result in
            self?.fetched(result)
        }
    }

    func fetched(_ result: FetchResult) {
        let summary = result.summary
        if result.total > 0, let first = result.updatedRefs.first(where: { (result.newCommits[$0] ?? 0) > 0 }) {
            toast(summary, icon: "arrow.triangle.2.circlepath", action: String(localized: "Show", bundle: .module)) { [weak self] in
                self?.window.show(.history)
                self?.store.showRef(first)
            }
        } else if !result.prunedRefs.isEmpty, result.total == 0 {
            toasts.show(Toast(message: summary.message, detail: String(localized: "Removed \(n(result.prunedRefs.count, "branch", "branches")) that no longer exist on the remote.", bundle: .module), icon: "trash"))
        } else {
            toast(summary, icon: "checkmark.circle")
        }
    }

    func pull(mode: PullMode? = nil, autostash: Bool? = nil, remote: String? = nil, branch: String? = nil, then next: (@MainActor () -> Void)? = nil) {
        guard running[.pull] == nil, let snapshot else { return }
        guard let current = snapshot.currentBranch else {
            toasts.show(Toast(message: String(localized: "You're not on a branch", bundle: .module), detail: String(localized: "Switch to a branch to pull into it.", bundle: .module)))
            return
        }
        if remote == nil, current.upstream == nil {
            toasts.show(Toast(
                message: String(localized: "\(current.name) has no upstream", bundle: .module),
                detail: String(localized: "Push it first to set one, or choose a branch to pull from.", bundle: .module),
                action: String(localized: "Pull from\u{2026}", bundle: .module)
            ) { [weak self] in self?.openSync(.pull) })
            return
        }
        running[.pull] = SyncRun(cancel: {})
        Task { [weak self] in
            guard let self else { return }
            let defaults = await self.store.pullDefaults()
            self.running[.pull] = nil
            let source = remote.map { $0 + "/" + (branch ?? "") } ?? current.upstream ?? ""
            let handle = self.store.pullOperation(mode: mode ?? defaults.mode, autostash: autostash ?? defaults.autostash, remote: remote, branch: branch)
            self.run(.pull, handle, busy: String(localized: "Pulling from \(source)", bundle: .module), retry: { [weak self] in self?.pull(mode: mode, autostash: autostash, remote: remote, branch: branch, then: next) }) { [weak self] result in
                guard let self else { return }
                if result.upToDate {
                    self.toast(result.summary, icon: "checkmark.circle")
                } else {
                    self.toast(result.summary, icon: "arrow.down.to.line", action: String(localized: "Undo", bundle: .module)) { [weak self] in self?.undo() }
                    if let head = self.snapshot?.headOID { self.store.select(.commit(head), scroll: true) }
                }
                next?()
            }
        }
    }

    func push(force: PushForce = .none, remote: String? = nil, branch: String? = nil, remoteBranch: String? = nil, setUpstream: Bool = false, tags: Bool = false, noVerify: Bool = false, pushOptions: [String] = [], confirmed: Bool = false) {
        guard running[.push] == nil, let snapshot else { return }
        let local = branch.flatMap { name in snapshot.branches.first { $0.name == name } } ?? snapshot.currentBranch
        guard let local else {
            toasts.show(Toast(
                message: String(localized: "You're not on a branch", bundle: .module),
                detail: String(localized: "Create a branch here to push these commits.", bundle: .module),
                action: String(localized: "Create branch", bundle: .module)
            ) { [weak self] in self?.newBranch() })
            return
        }
        guard !snapshot.remotes.isEmpty else {
            noRemotes(branch: local.name)
            return
        }
        if local.upstream == nil, remote == nil {
            openSync(.push, publish: true)
            return
        }
        let target = remote ?? local.upstream.flatMap { upstream in snapshot.remotes.map(\.name).sorted { $0.count > $1.count }.first { upstream.hasPrefix($0 + "/") } } ?? defaultRemote ?? "origin"
        if !confirmed, force == .force || (force == .withLease && preferences.confirmForcePush) {
            confirmForce(force: force, remote: target, branch: local, retry: { [weak self] in
                self?.push(force: force, remote: remote, branch: branch, remoteBranch: remoteBranch, setUpstream: setUpstream, tags: tags, noVerify: noVerify, pushOptions: pushOptions, confirmed: true)
            })
            return
        }
        let retry: @MainActor () -> Void = { [weak self] in
            self?.push(force: force, remote: remote, branch: branch, remoteBranch: remoteBranch, setUpstream: setUpstream, tags: tags, noVerify: noVerify, pushOptions: pushOptions, confirmed: true)
        }
        let busy = String(localized: "Pushing \(local.name) to \(target)", bundle: .module)
        if let remoteBranch, !remoteBranch.isEmpty, remoteBranch != (local.upstream.map { String($0.dropFirst(target.count + 1)) } ?? local.name) {
            let command = SyncCommands.push(remote: target, refspec: "refs/heads/" + local.name + ":refs/heads/" + remoteBranch, force: force, setUpstream: setUpstream, tags: tags, noVerify: noVerify, pushOptions: pushOptions)
            let handle = store.start { [store] _ in
                try await store.perform("push") { _ = try await store.git.run(command) }
            }
            run(.push, handle, busy: busy, retry: retry) { [weak self] _ in
                self?.toasts.show(Toast(message: String(localized: "Pushed \(local.name) to \(target)/\(remoteBranch)", bundle: .module), icon: "arrow.up.to.line"))
                self?.window.checks.watch(local.tip, branch: remoteBranch)
            }
            return
        }
        let handle = store.pushOperation(remote: remote ?? (local.upstream == nil ? target : nil), branch: branch, force: force, setUpstream: setUpstream, tags: tags, noVerify: noVerify, pushOptions: pushOptions)
        run(.push, handle, busy: busy, retry: retry) { [weak self] result in
            self?.toast(result.summary, icon: "arrow.up.to.line")
            self?.window.checks.watch(local.tip, branch: local.name)
        }
    }

    func confirmForce(force: PushForce, remote: String, branch: Branch, retry: @escaping @MainActor () -> Void) {
        let lease = force == .withLease
        let full = remote + "/" + branch.name
        let behind = branch.upstream == full ? branch.behind : 0
        let them = behind == 1 ? String(localized: "it", bundle: .module) : String(localized: "them", bundle: .module)
        var message = behind > 0
            ? String(localized: "\(full) has \(n(behind, "commit")) you don't have. Force pushing replaces \(them) with your version.", bundle: .module)
            : String(localized: "This replaces \(full) with your version of \(branch.name).", bundle: .module)
        message += " " + (lease
            ? String(localized: "The push stops if anyone pushed to it since your last fetch.", bundle: .module)
            : String(localized: "Commits anyone pushed since your last fetch are lost too.", bundle: .module))
        let request = SensitiveRequest(
            title: lease ? String(localized: "Force push \(branch.name) to \(remote) with lease", bundle: .module) : String(localized: "Force push \(branch.name) to \(remote)", bundle: .module),
            detail: message,
            reason: String(localized: "force push \(branch.name) to \(remote)", bundle: .module),
            icon: "arrow.up.to.line"
        )
        Sensitive.confirm(request, preferences: preferences, source: window.repositoryName, alert: { [weak self] in
            self?.present(SyncAlert(
                icon: "exclamationmark.triangle",
                title: lease ? String(localized: "Force push \(branch.name) with lease?", bundle: .module) : String(localized: "Force push \(branch.name)?", bundle: .module),
                message: message,
                toggle: lease ? String(localized: "Don't ask again", bundle: .module) : nil,
                actions: [
                    AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel),
                    AlertAction(title: String(localized: "Force push", bundle: .module), role: .destructive) { [weak self] in
                        if lease, self?.toggleOn == true { self?.preferences.confirmForcePush = false }
                        retry()
                    }
                ]
            ))
        }, perform: retry)
    }

    func failed(_ error: any Error, kind: SyncKind?, retry: (@MainActor () -> Void)?) {
        guard let error = error as? GitError else {
            window.alerts.present(GitError(.unknown(exit: -1, stderr: String(describing: error))))
            return
        }
        switch error.code {
        case .cancelled:
            let verb = kind.map(\.rawValue) ?? ""
            toasts.show(Toast(message: String(localized: "Stopped \(verb)", bundle: .module), detail: String(localized: "git was cancelled before it finished.", bundle: .module), icon: "xmark", timeout: Toast.brief))
        case .authFailed:
            surfaced = true
            presentAuth(error, retry: retry)
        case .networkUnreachable(let host):
            surfaced = true
            offline(host: host ?? error.host, kind: kind, retry: retry)
        case .pushRejected(let behind):
            rejected(behind: behind, remote: SyncCopy.remote(of: error) ?? defaultRemote ?? "origin")
        case .noUpstream:
            if kind == .push {
                openSync(.push, publish: true)
            } else {
                window.alerts.present(error)
            }
        case .divergentBranches:
            diverged()
        case .localChangesWouldBeOverwritten(let paths) where kind == .pull:
            present(SyncAlert(
                icon: "exclamationmark.triangle",
                title: String(localized: "Pulling would overwrite your changes", bundle: .module),
                message: SyncCopy.overwritten(paths),
                actions: [
                    AlertAction(title: String(localized: "Pull with changes set aside", bundle: .module)) { [weak self] in self?.pull(autostash: true) },
                    AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel)
                ]
            ))
        case .conflicts(let paths):
            toasts.show(Toast(
                tone: .warning,
                message: String(localized: "Stopped on \(n(max(1, paths.count), "conflict"))", bundle: .module),
                detail: String(localized: "Resolve them in Changes, then commit to finish.", bundle: .module),
                action: String(localized: "Resolve conflicts", bundle: .module)
            ) { [weak self] in self?.window.showConflicts() })
        case .remoteNotFound:
            noRemotes()
        case .hookFailed(let name, let output) where name == "pre-push":
            present(SyncAlert(
                icon: "exclamationmark.octagon",
                title: String(localized: "The pre-push hook stopped the push", bundle: .module),
                message: SyncCopy.trimmed(output),
                actions: [
                    AlertAction(title: String(localized: "Close", bundle: .module), role: .cancel),
                    AlertAction(title: String(localized: "Push without the hook", bundle: .module)) { [weak self] in self?.push(noVerify: true, confirmed: true) }
                ]
            ))
        default:
            window.alerts.present(error, retry: retry)
        }
    }

    func rejected(behind: Int?, remote: String) {
        let copy = SyncCopy.rejected(remote: remote, behind: behind)
        let alert = SyncAlert(
            icon: "exclamationmark.triangle",
            title: copy.title,
            message: copy.message,
            actions: [
                AlertAction(title: String(localized: "Pull and push", bundle: .module)) { [weak self] in self?.pull { [weak self] in self?.push() } },
                AlertAction(title: String(localized: "Force push with lease", bundle: .module)) { [weak self] in self?.push(force: .withLease, remote: remote, confirmed: true) },
                AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel)
            ]
        )
        if !island(alert) { present(alert) }
    }

    func diverged() {
        let branch = currentBranch
        let ahead = branch?.ahead ?? 0
        let behind = branch?.behind ?? 0
        let upstream = branch?.upstream ?? String(localized: "its upstream", bundle: .module)
        let alert = SyncAlert(
            icon: "arrow.triangle.merge",
            title: String(localized: "Can't fast-forward \(headName)", bundle: .module),
            message: String(localized: "You have \(n(ahead, "commit")) that \(upstream) doesn't, and it has \(behind) you don't. Merge them, or rebase your \(ahead == 1 ? String(localized: "commit", bundle: .module) : String(localized: "commits", bundle: .module)) on top of it.", bundle: .module),
            actions: [
                AlertAction(title: String(localized: "Pull and merge", bundle: .module)) { [weak self] in self?.pull(mode: .merge) },
                AlertAction(title: String(localized: "Pull and rebase", bundle: .module)) { [weak self] in self?.pull(mode: .rebase) },
                AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel)
            ]
        )
        if !island(alert, tone: .warning) { present(alert) }
    }

    func offline(host: String?, kind: SyncKind?, retry: (@MainActor () -> Void)?) {
        let name = host ?? String(localized: "the remote", bundle: .module)
        let verb = kind?.rawValue ?? String(localized: "it", bundle: .module)
        toasts.show(Toast(
            tone: .danger,
            message: String(localized: "Couldn't reach \(name)", bundle: .module),
            detail: retry == nil ? String(localized: "Check your connection, then try again.", bundle: .module) : String(localized: "Check your connection. Vrai retries \(verb) when you're back online.", bundle: .module),
            icon: "wifi.slash",
            action: retry == nil ? nil : String(localized: "Retry", bundle: .module),
            onAction: retry
        ))
        if let retry {
            retryWhenOnline = retry
            watchConnection()
        }
    }

    func authTarget(_ error: GitError?) -> (remote: String?, url: String?, host: String, repository: String) {
        let remotes = snapshot?.remotes ?? []
        var url = error?.remoteURL
        var remote = url.flatMap { value in remotes.first { SyncCopy.sameURL($0.fetchURL, value) || $0.pushURL.map { SyncCopy.sameURL($0, value) } == true }?.name }
        if url == nil || remote == nil {
            let fallback = remotes.first { $0.name == (remote ?? defaultRemote) }
            remote = fallback?.name
            url = url ?? fallback.map { $0.pushURL ?? $0.fetchURL }
        }
        let parsed = url.flatMap(RemoteURL.init)
        var host = error?.host ?? parsed?.host
        if host == nil, case .authFailed(let failing)? = snapshot?.network { host = failing }
        return (remote, url, host ?? String(localized: "The server", bundle: .module), parsed?.repositoryPath ?? (remote ?? ""))
    }

    func presentAuth(_ error: GitError?, retry: (@MainActor () -> Void)?) {
        let target = authTarget(error)
        let parsed = target.url.flatMap(RemoteURL.init)
        let web = parsed?.scheme == "https" || parsed?.scheme == "http"
        var actions = [AlertAction(title: String(localized: "Sign in again\u{2026}", bundle: .module)) { [weak self] in self?.signIn(error, retry: retry) }]
        if web, let remote = target.remote, let url = target.url {
            actions.append(AlertAction(title: String(localized: "Use SSH instead", bundle: .module)) { [weak self] in self?.useSSH(remote: remote, url: url) })
        }
        actions.append(AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel))
        let alert = SyncAlert(
            icon: "key",
            title: SyncCopy.authTitle(host: target.host, repository: target.repository),
            message: web ? String(localized: "The token Vrai uses for \(target.repository) was rejected, so fetch, pull and push can't reach \(target.host). Sign in again, or switch to SSH.", bundle: .module) : String(localized: "The credentials Vrai uses for \(target.repository) were rejected, so fetch, pull and push can't reach \(target.host). Sign in again.", bundle: .module),
            actions: actions
        )
        if !island(alert) { present(alert) }
    }

    func signIn(_ error: GitError?, retry: (@MainActor () -> Void)?) {
        let target = authTarget(error)
        let user = target.url.flatMap { RemoteURL($0)?.user }
        showSheet {
            SignInSheet(again: SignInTarget(remote: target.remote, url: target.url, host: target.host, repository: target.repository, username: user ?? ""), retry: retry)
        }
    }

    func signedIn(_ target: SignInTarget, username: String, retry: (@MainActor () -> Void)?) {
        SettingsAccounts.record(target, username: username, preferences: preferences)
        let stored = String(localized: "Git saved the token with your credential helper.", bundle: .module)
        let again = retry == nil ? "" : " " + String(localized: "Trying again.", bundle: .module)
        toasts.show(Toast(message: String(localized: "Signed in to \(target.host) as \(username)", bundle: .module), detail: stored + again, icon: "checkmark.seal"))
        surfaced = false
        retry?()
    }

    func useSSH(remote: String, url: String) {
        guard let parsed = RemoteURL(url), let host = parsed.host else { return }
        let ssh = "git@" + host + ":" + parsed.repositoryPath + ".git"
        perform({ [weak self] in
            guard let self else { return }
            try await self.store.editRemote(name: remote, fetchURL: ssh)
            self.surfaced = false
            self.toasts.show(Toast(message: String(localized: "\(remote) now uses SSH", bundle: .module), detail: ssh, icon: "key", action: String(localized: "Fetch", bundle: .module)) { [weak self] in self?.fetch(remote: remote) })
        })
    }

    func undo() {
        perform({ [weak self] in
            guard let self else { return }
            if let entry = try await self.store.undoLast() {
                self.toasts.show(Toast(message: String(localized: "Undid: \(entry.label)", bundle: .module), icon: "arrow.uturn.backward"))
            } else {
                self.toasts.show(Toast(message: String(localized: "Nothing to undo", bundle: .module), detail: String(localized: "Edit, Undo history lists older changes you can restore.", bundle: .module)))
            }
        })
    }
}

extension SyncModel {
    func newBranch(from: String? = nil, checkout: Bool = true, name: String = "") {
        showSheet { BranchSheet(from: from ?? "HEAD", checkout: checkout, name: name) }
    }

    func createBranch(name: String, from: String, switchTo: Bool, publish: Bool) {
        perform(network: publish, { [weak self] in
            guard let self else { return }
            let summary = try await self.store.createBranch(name: name, from: from, switchTo: switchTo, publish: publish)
            self.toast(summary, icon: "arrow.triangle.branch")
            if switchTo { self.selectHead() }
        }, kind: publish ? .push : nil)
    }

    func selectHead() {
        guard let snapshot else { return }
        if !snapshot.working.isEmpty {
            store.select(.wip, scroll: true)
        } else if let head = snapshot.headOID {
            store.select(.commit(head), scroll: true)
        }
    }

    func switchTo(_ name: String, carry: SwitchCarry = .none) {
        guard let snapshot, snapshot.head.branchName != name else { return }
        switch snapshot.state {
        case .merging:
            toasts.show(Toast(tone: .danger, message: String(localized: "Finish the merge first", bundle: .module), detail: String(localized: "Continue or abort it from the banner.", bundle: .module)))
            return
        case .rebasing:
            toasts.show(Toast(tone: .danger, message: String(localized: "Finish the rebase first", bundle: .module), detail: String(localized: "Continue or abort it from the banner.", bundle: .module)))
            return
        default:
            break
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await self.store.switchTo(branch: name, carry: carry)
                if carry == .stash {
                    self.toast(summary, icon: "arrow.triangle.branch", action: String(localized: "Show stash", bundle: .module)) { [weak self] in self?.window.show(.stashes) }
                } else {
                    self.toast(summary, icon: "arrow.triangle.branch")
                }
                self.selectHead()
            } catch let error as GitError {
                if case .localChangesWouldBeOverwritten = error.code, carry == .none {
                    self.bringOrStash(name)
                } else {
                    self.failed(error, kind: nil, retry: nil)
                }
            } catch {
                self.failed(error, kind: nil, retry: nil)
            }
        }
    }

    func checkOut(remote branch: RemoteBranch) {
        if snapshot?.branches.contains(where: { $0.name == branch.name }) == true {
            switchTo(branch.name)
        } else {
            switchTo(branch.fullName)
        }
    }

    func bringOrStash(_ name: String) {
        let count = snapshot?.working.count ?? 0
        let isLocal = snapshot?.branches.contains { $0.name == name } ?? true
        let remote = snapshot?.remoteBranches.first { $0.fullName == name }
        let target = !isLocal ? (remote?.name ?? name) : name
        let yours = count == 1 ? String(localized: "Your uncommitted change", bundle: .module) : String(localized: "Your \(n(count, "uncommitted change"))", bundle: .module)
        present(SyncAlert(
            icon: "arrow.triangle.branch",
            title: String(localized: "Bring your changes to \(target)?", bundle: .module),
            message: String(localized: "\(yours) on \(headName) can come along, or wait in a stash until you come back.", bundle: .module),
            actions: [
                AlertAction(title: String(localized: "Bring changes", bundle: .module)) { [weak self] in self?.switchTo(name, carry: .bring) },
                AlertAction(title: String(localized: "Stash and switch", bundle: .module)) { [weak self] in self?.switchTo(name, carry: .stash) },
                AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel)
            ]
        ))
    }

    func confirmDelete(_ branch: Branch, remoteToo: Bool = false) {
        Task { [weak self] in
            guard let self else { return }
            let unmerged = (try? await self.store.unmergedCount(branch: branch.name)) ?? 0
            let head = self.headName
            let upstream = branch.upstreamGone ? nil : branch.upstream
            var message: String
            if unmerged == 0 {
                message = String(localized: "Everything on it is already in \(head).", bundle: .module)
            } else {
                message = unmerged == 1
                    ? String(localized: "1 of its commits isn't in \(head)", bundle: .module)
                    : String(localized: "\(unmerged) of its commits aren't in \(head)", bundle: .module)
                if let upstream, branch.ahead == 0 {
                    message += unmerged == 1 ? String(localized: ", but it's on \(upstream).", bundle: .module) : String(localized: ", but they're on \(upstream).", bundle: .module)
                } else {
                    message += String(localized: " yet.", bundle: .module)
                }
            }
            message += " " + String(localized: "Undo history keeps the branch for 14 days.", bundle: .module)
            let force = unmerged > 0
            self.present(SyncAlert(
                icon: "trash",
                title: String(localized: "Delete \(branch.name)?", bundle: .module),
                message: message,
                toggle: upstream.map { String(localized: "Also delete \($0)", bundle: .module) },
                toggleDefault: remoteToo && upstream != nil,
                actions: [
                    AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel),
                    AlertAction(title: String(localized: "Delete branch", bundle: .module), role: .destructive) { [weak self] in
                        guard let self else { return }
                        self.deleteBranch(branch.name, force: force, alsoOnRemote: upstream != nil && self.toggleOn)
                    }
                ]
            ))
        }
    }

    func deleteBranch(_ name: String, force: Bool, alsoOnRemote: Bool) {
        perform(network: alsoOnRemote, { [weak self] in
            guard let self else { return }
            let summary = try await self.store.deleteBranch(name: name, force: force, alsoOnRemote: alsoOnRemote)
            self.toast(summary, icon: "trash", action: String(localized: "Undo", bundle: .module)) { [weak self] in self?.undo() }
        }, kind: alsoOnRemote ? .push : nil)
    }

    func confirmDeleteRemote(remote: String, name: String) {
        guard let snapshot else { return }
        let full = remote + "/" + name
        let tracking = snapshot.branches.filter { $0.upstream == full }.map(\.name)
        var message = String(localized: "This removes \(full) for everyone who uses \(remote).", bundle: .module)
        message += " " + String(localized: "Your local branches keep their commits.", bundle: .module)
        if !tracking.isEmpty {
            message += " " + (tracking.count == 1 ? String(localized: "\(tracking[0]) loses its upstream.", bundle: .module) : String(localized: "\(tracking.joined(separator: ", ")) lose their upstream.", bundle: .module))
        }
        let delete: @MainActor () -> Void = { [weak self] in
            self?.perform(network: true, { [weak self] in
                guard let self else { return }
                let summary = try await self.store.deleteRemoteBranch(remote: remote, name: name)
                self.toast(summary, icon: "trash")
            }, kind: .push)
        }
        let request = SensitiveRequest(
            title: String(localized: "Delete \(name) on \(remote)", bundle: .module),
            detail: message,
            reason: String(localized: "delete \(full) for everyone", bundle: .module),
            icon: "trash"
        )
        Sensitive.confirm(request, preferences: preferences, source: window.repositoryName, alert: { [weak self] in
            self?.present(SyncAlert(
                icon: "cloud",
                title: String(localized: "Delete \(name) on \(remote)?", bundle: .module),
                message: message,
                actions: [
                    AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel),
                    AlertAction(title: String(localized: "Delete on \(remote)", bundle: .module), role: .destructive, action: delete)
                ]
            ))
        }, perform: delete)
    }

    func rename(_ name: String) {
        showSheet { BranchRenameSheet(name: name) }
    }

    func editUpstream(_ name: String) {
        showSheet { BranchUpstreamSheet(name: name) }
    }

    func stopTracking(_ name: String) {
        perform({ [weak self] in
            guard let self else { return }
            let summary = try await self.store.setUpstream(branch: name, upstream: nil)
            self.toasts.show(Toast(message: summary.message, detail: summary.detail))
        })
    }

    func confirmDetach(_ id: OID, subject: String?) {
        guard let snapshot else { return }
        let short = id.short(expert: preferences.expert)
        switch snapshot.state {
        case .merging, .rebasing:
            let kind: String = if case .merging = snapshot.state { String(localized: "merge", bundle: .module) } else { String(localized: "rebase", bundle: .module) }
            present(SyncAlert(
                icon: "exclamationmark.triangle",
                title: String(localized: "Finish the \(kind) first", bundle: .module),
                message: String(localized: "Continue or abort it from the banner, then check out \(short).", bundle: .module),
                actions: [AlertAction(title: String(localized: "Close", bundle: .module), role: .cancel)]
            ))
            return
        default:
            break
        }
        let dirty = snapshot.working.count
        var message = String(localized: "You won't be on a branch. Commits you make there are easy to lose unless you create a branch for them.", bundle: .module)
        if dirty == 1 {
            message += " " + String(localized: "Your uncommitted change comes along.", bundle: .module)
        } else if dirty > 1 {
            message += " " + String(localized: "Your \(n(dirty, "uncommitted change")) come along.", bundle: .module)
        }
        if let subject { message += "\n\n" + short + "  " + subject }
        present(SyncAlert(
            icon: "mappin.and.ellipse",
            title: String(localized: "Check out \(short)?", bundle: .module),
            message: message,
            actions: [
                AlertAction(title: String(localized: "Check out \(short)", bundle: .module)) { [weak self] in self?.detach(id) },
                AlertAction(title: String(localized: "Create branch here\u{2026}", bundle: .module)) { [weak self] in self?.newBranch(from: id.rawValue, checkout: true) },
                AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel)
            ]
        ))
    }

    func detach(_ id: OID) {
        perform({ [weak self] in
            guard let self else { return }
            let summary = try await self.store.detach(at: id.rawValue)
            self.toast(summary, icon: "mappin.and.ellipse")
            self.store.select(.commit(id), scroll: true)
        })
    }
}

extension SyncModel {
    func newTag(target: String? = nil) {
        showSheet { TagSheet(target: target ?? "HEAD") }
    }

    func createTag(name: String, target: String, message: String?, sign: Bool, push: Bool) {
        perform(network: push, { [weak self] in
            guard let self else { return }
            let summary = try await self.store.createTag(name: name, target: target, message: message, sign: sign)
            self.toast(summary, icon: "tag")
            if push { self.pushTag(name) }
        })
    }

    func pushTag(_ name: String) {
        guard let remote = defaultRemote else {
            noRemotes()
            return
        }
        perform(network: true, { [weak self] in
            guard let self else { return }
            let summary = try await self.store.pushTag(name: name, remote: remote)
            self.toast(summary, icon: "tag")
        }, retry: { [weak self] in self?.pushTag(name) }, kind: .push)
    }

    func confirmDeleteTag(_ tag: Tag, remoteToo: Bool = false) {
        let remote = defaultRemote
        let subject = store.history.index[tag.target].map { store.history.commits[$0].subject }
        var message = String(localized: "It points at \(tag.target.short(expert: preferences.expert))", bundle: .module)
        if let subject { message += ", " + subject }
        message += ". " + String(localized: "The commit stays; only the name goes. Undo history keeps it for 14 days.", bundle: .module)
        present(SyncAlert(
            icon: "tag",
            title: String(localized: "Delete the tag \(tag.name)?", bundle: .module),
            message: message,
            toggle: remote.map { String(localized: "Also delete it on \($0)", bundle: .module) },
            toggleDefault: remoteToo && remote != nil,
            actions: [
                AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel),
                AlertAction(title: String(localized: "Delete tag", bundle: .module), role: .destructive) { [weak self] in
                    guard let self else { return }
                    let also = remote != nil && self.toggleOn
                    self.perform(network: also, { [weak self] in
                        guard let self else { return }
                        let summary = try await self.store.deleteTag(name: tag.name, alsoOnRemote: also, remote: remote)
                        self.toast(summary, icon: "trash", action: String(localized: "Undo", bundle: .module)) { [weak self] in self?.undo() }
                    }, kind: also ? .push : nil)
                }
            ]
        ))
    }

    func addRemote() {
        showSheet { RemoteSheet(editing: nil) }
    }

    func editRemote(_ name: String) {
        let remote = snapshot?.remotes.first { $0.name == name }
        showSheet { RemoteSheet(editing: remote) }
    }

    func confirmRemoveRemote(_ name: String) {
        guard let snapshot, let remote = snapshot.remotes.first(where: { $0.name == name }) else { return }
        let count = snapshot.remoteBranches.filter { $0.remote == name }.count
        let tracking = snapshot.branches.filter { $0.upstream?.hasPrefix(name + "/") == true }.map(\.name)
        let parsed = RemoteURL(remote.fetchURL)
        let host = parsed?.host ?? String(localized: "the server", bundle: .module)
        let place = parsed?.displayName ?? PathText.remoteDetail(remote.fetchURL)
        var message = String(localized: "Vrai stops fetching from \(place) and forgets its \(n(count, "remote branch", "remote branches")).", bundle: .module)
        if !tracking.isEmpty {
            message += " " + (tracking.count == 1 ? String(localized: "\(tracking[0]) loses its upstream.", bundle: .module) : String(localized: "\(tracking.joined(separator: ", ")) lose their upstream.", bundle: .module))
        }
        message += " " + String(localized: "Nothing changes on \(host).", bundle: .module)
        present(SyncAlert(
            icon: "network",
            title: String(localized: "Remove the remote \(name)?", bundle: .module),
            message: message,
            actions: [
                AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel),
                AlertAction(title: String(localized: "Remove \(name)", bundle: .module), role: .destructive) { [weak self] in
                    self?.perform({ [weak self] in
                        guard let self else { return }
                        let summary = try await self.store.removeRemote(name: name)
                        self.toast(summary, icon: "trash")
                    })
                }
            ]
        ))
    }

    func pruneRemote(_ name: String) {
        guard running[.fetch] == nil else { return }
        let handle = store.fetchOperation(remote: name, prune: true)
        run(.fetch, handle, busy: String(localized: "Pruning \(name)", bundle: .module), retry: { [weak self] in self?.pruneRemote(name) }) { [weak self] result in
            guard let self else { return }
            if result.prunedRefs.isEmpty {
                self.toasts.show(Toast(message: String(localized: "Nothing to prune on \(name)", bundle: .module), detail: String(localized: "Every remote branch still exists on \(name).", bundle: .module), icon: "checkmark.circle"))
            } else {
                self.toasts.show(Toast(message: String(localized: "Pruned \(name)", bundle: .module), detail: String(localized: "Removed \(n(result.prunedRefs.count, "branch", "branches")) that no longer exist on \(name).", bundle: .module), icon: "trash"))
            }
        }
    }
}

enum SyncCopy {
    static func them(_ count: Int?) -> String {
        count == 1 ? String(localized: "it", bundle: .module) : String(localized: "them", bundle: .module)
    }

    static func rejected(remote: String, behind: Int?) -> (title: String, message: String) {
        let has = behind.map { $0 > 0 ? n($0, "commit") : String(localized: "commits", bundle: .module) } ?? String(localized: "commits", bundle: .module)
        let it = them(behind)
        return (
            String(localized: "Push rejected", bundle: .module),
            String(localized: "\(remote) has \(has) you don't have. Pull \(it) first, or force push with lease to replace \(it).", bundle: .module)
        )
    }

    static func authTitle(host: String, repository: String) -> String {
        repository.isEmpty
            ? String(localized: "\(host) didn't accept your credentials.", bundle: .module)
            : String(localized: "\(host) didn't accept your credentials for \(repository).", bundle: .module)
    }

    static func remote(of error: GitError) -> String? {
        guard let command = error.result?.command, command.subcommand == "push" else { return nil }
        let words = command.arguments.drop { $0 != "push" }.dropFirst()
        var skip = false
        for word in words {
            if skip {
                skip = false
                continue
            }
            if word == "-o" || word == "--push-option" {
                skip = true
                continue
            }
            if word.hasPrefix("-") { continue }
            return word
        }
        return nil
    }

    static func overwritten(_ paths: [String]) -> String {
        if paths.isEmpty {
            return String(localized: "git stopped because files you changed would be overwritten. Set your changes aside while pulling, or commit them first.", bundle: .module)
        }
        let shown = paths.prefix(3).map { PathParts.split($0).name }.joined(separator: ", ")
        let more = paths.count > 3 ? " " + String(localized: "and \(n(paths.count - 3, "more file"))", bundle: .module) : ""
        return String(localized: "git stopped because \(n(paths.count, "file")) you changed would be overwritten: \(shown)\(more). Set your changes aside while pulling, or commit them first.", bundle: .module)
    }

    static func trimmed(_ output: String) -> String {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).suffix(12)
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? String(localized: "The hook exited with an error and printed nothing.", bundle: .module) : text
    }

    static func sameURL(_ a: String, _ b: String) -> Bool {
        func clean(_ value: String) -> String {
            var text = value.trimmingCharacters(in: .whitespaces)
            while text.hasSuffix("/") { text.removeLast() }
            return text
        }
        return clean(a) == clean(b)
    }
}
