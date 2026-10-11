import SwiftUI
import VraiCore
import VraiGit

struct MenuItem: View {
    let title: String
    var icon: String?
    var enabled = false
    var destructive = false
    var action: (@MainActor () -> Void)?

    var body: some View {
        Button(role: destructive ? .destructive : nil) {
            action?()
        } label: {
            if let icon {
                Label(title, systemImage: icon)
            } else {
                Text(title)
            }
        }
        .disabled(!enabled)
    }
}

struct AlternateMenuItem: View {
    let primary: MenuItem
    let alternate: MenuItem

    var body: some View {
        primary.modifierKeyAlternate(.option) { alternate }
    }
}

struct CommitMenu: View {
    let id: OID
    let window: WindowModel

    var body: some View {
        let store = window.store
        let commit = window.store.history.index[id].map { store.history.commits[$0] } ?? (store.detail?.commit.id == id ? store.detail?.commit : nil)
        let head = window.headName
        let rewrite = RewriteMenuState(window: window, id: id)
        let bisecting: Bool = {
            if case .bisecting? = store.snapshot?.state { return true }
            return false
        }()
        AlternateMenuItem(
            primary: MenuItem(title: String(localized: "Check out \(id.short)", bundle: .module), icon: "mappin.and.ellipse", enabled: true) { window.sync.confirmDetach(id, subject: commit?.subject) },
            alternate: MenuItem(title: String(localized: "Create branch here and switch\u{2026}", bundle: .module), icon: "arrow.triangle.branch", enabled: true) { window.sync.newBranch(from: id.rawValue, checkout: true) }
        )
        MenuItem(title: String(localized: "New branch from here\u{2026}", bundle: .module), icon: "arrow.triangle.branch", enabled: true) { window.sync.newBranch(from: id.rawValue) }
        MenuItem(title: String(localized: "New tag here\u{2026}", bundle: .module), icon: "tag", enabled: true) { window.sync.newTag(target: id.rawValue) }
        Divider()
        AlternateMenuItem(
            primary: MenuItem(title: String(localized: "Cherry-pick onto \(head)", bundle: .module), icon: "arrow.turn.down.right", enabled: !rewrite.inHead) { RewriteActions.cherryPick(window, ids: [id]) },
            alternate: MenuItem(title: String(localized: "Cherry-pick with options\u{2026}", bundle: .module), icon: "arrow.turn.down.right", enabled: true) { RewriteActions.openCherryPick(window, ids: [id]) }
        )
        MenuItem(title: String(localized: "Revert commit", bundle: .module), icon: "arrow.uturn.backward", enabled: rewrite.inHead && !rewrite.isMerge) { RewriteActions.revert(window, id: id) }
        MenuItem(title: String(localized: "Reset \(head) to here\u{2026}", bundle: .module), icon: "arrow.counterclockwise", enabled: !rewrite.isTip) { RewriteActions.openReset(window, target: id) }
        MenuItem(title: String(localized: "Rebase \(head) onto here\u{2026}", bundle: .module), icon: "arrow.triangle.swap", enabled: !rewrite.inHead) { RewriteActions.openRebase(window, onto: id.rawValue) }
        MenuItem(title: String(localized: "Interactive rebase from here\u{2026}", bundle: .module), icon: "list.number", enabled: rewrite.inHead && !rewrite.isTip) { RewriteActions.openInteractive(window, onto: id.rawValue) }
        Divider()
        if bisecting {
            MenuItem(title: String(localized: "Mark as good", bundle: .module), icon: "checkmark.circle", enabled: true) { RewriteActions.markBisect(window, .good, at: id) }
            MenuItem(title: String(localized: "Mark as bad", bundle: .module), icon: "xmark.circle.fill", enabled: true) { RewriteActions.markBisect(window, .bad, at: id) }
        } else {
            MenuItem(title: String(localized: "Start bisect here\u{2026}", bundle: .module), icon: "scope", enabled: rewrite.inHead && !rewrite.isTip) { RewriteActions.openBisect(window, good: id.rawValue) }
        }
        if window.preferences.expert {
            Divider()
            MenuItem(title: String(localized: "Create fixup commit for this", bundle: .module), icon: "bandage", enabled: rewrite.inHead) { LongTailActions.fixup(window, id: id) }
            MenuItem(title: String(localized: "Reword in place\u{2026}", bundle: .module), icon: "pencil", enabled: rewrite.inHead) { LongTailActions.openReword(window, id: id) }
            MenuItem(title: String(localized: "Split commit\u{2026}", bundle: .module), icon: "rectangle.split.2x1", enabled: rewrite.inHead && !rewrite.isMerge) { LongTailActions.openSplit(window, id: id) }
            MenuItem(title: String(localized: "Show object", bundle: .module), icon: "cube", enabled: true) { window.showObject(id) }
        }
        Divider()
        AlternateMenuItem(
            primary: MenuItem(title: String(localized: "Copy hash", bundle: .module), icon: "doc.on.doc", enabled: true) { window.copy(id.short(expert: window.preferences.expert)) },
            alternate: MenuItem(title: String(localized: "Copy full hash", bundle: .module), icon: "doc.on.doc", enabled: true) { window.copy(id.rawValue, label: String(localized: "full hash", bundle: .module)) }
        )
        MenuItem(title: String(localized: "Copy subject", bundle: .module), icon: "text.alignleft", enabled: commit != nil) {
            if let commit { window.copy(commit.subject, label: String(localized: "subject", bundle: .module)) }
        }
        MenuItem(title: String(localized: "Save as patch\u{2026}", bundle: .module), icon: "square.and.arrow.down", enabled: true) { LongTailActions.savePatch(window, id: id) }
        MenuItem(title: String(localized: "Export archive\u{2026}", bundle: .module), icon: "archivebox", enabled: true) { LongTailActions.openArchive(window, ref: id.rawValue, label: id.short) }
    }
}

struct WipMenu: View {
    let window: WindowModel

    var body: some View {
        MenuItem(title: String(localized: "Open Changes", bundle: .module), icon: "square.and.pencil", enabled: true) { window.show(.changes) }
        MenuItem(title: String(localized: "Stash changes\u{2026}", bundle: .module), icon: "tray.and.arrow.down", enabled: true) { RewriteActions.openStash(window) }
        MenuItem(title: String(localized: "Discard all changes\u{2026}", bundle: .module), icon: "arrow.uturn.backward", enabled: true, destructive: true) { window.confirmDiscardAll() }
    }
}

struct BranchMenu: View {
    let branch: Branch
    let window: WindowModel

    var body: some View {
        let head = window.headName
        let current = branch.isCurrent
        if current {
            Text("\(branch.name), checked out", bundle: .module)
        }
        AlternateMenuItem(
            primary: MenuItem(title: String(localized: "Switch to \(branch.name)", bundle: .module), icon: "arrow.triangle.branch", enabled: !current) { window.sync.switchTo(branch.name) },
            alternate: MenuItem(title: String(localized: "Switch and bring changes", bundle: .module), icon: "arrow.triangle.branch", enabled: !current) { window.sync.switchTo(branch.name, carry: .bring) }
        )
        AlternateMenuItem(
            primary: MenuItem(title: String(localized: "Merge \(branch.name) into \(head)\u{2026}", bundle: .module), icon: "arrow.triangle.merge", enabled: !current) { RewriteActions.openMerge(window, source: branch.name) },
            alternate: MenuItem(title: String(localized: "Merge \(branch.name) now", bundle: .module), icon: "arrow.triangle.merge", enabled: !current) { RewriteActions.merge(window, source: branch.name, mode: .auto) }
        )
        MenuItem(title: String(localized: "Rebase \(head) onto \(branch.name)\u{2026}", bundle: .module), icon: "arrow.triangle.swap", enabled: !current) { RewriteActions.openRebase(window, onto: branch.name) }
        Divider()
        if current {
            AlternateMenuItem(
                primary: MenuItem(title: branch.ahead > 0 ? String(localized: "Push \(n(branch.ahead, "commit"))", bundle: .module) : String(localized: "Push", bundle: .module), icon: "arrow.up.to.line", enabled: true) { window.sync.push() },
                alternate: MenuItem(title: String(localized: "Force push with lease", bundle: .module), icon: "arrow.up.to.line", enabled: true, destructive: true) { window.sync.push(force: .withLease) }
            )
            if branch.upstream != nil {
                AlternateMenuItem(
                    primary: MenuItem(title: branch.behind > 0 ? String(localized: "Pull \(n(branch.behind, "commit"))", bundle: .module) : String(localized: "Pull", bundle: .module), icon: "arrow.down.to.line", enabled: true) { window.sync.pull() },
                    alternate: MenuItem(title: String(localized: "Pull with rebase", bundle: .module), icon: "arrow.down.to.line", enabled: true) { window.sync.pull(mode: .rebase) }
                )
            }
        }
        MenuItem(title: String(localized: "New branch from \(branch.name)\u{2026}", bundle: .module), icon: "plus", enabled: true) { window.sync.newBranch(from: branch.name) }
        MenuItem(title: String(localized: "Rename\u{2026}", bundle: .module), icon: "pencil", enabled: true) { window.sync.rename(branch.name) }
        MenuItem(title: branch.upstream == nil ? String(localized: "Set upstream\u{2026}", bundle: .module) : String(localized: "Change upstream\u{2026}", bundle: .module), icon: "link", enabled: true) { window.sync.editUpstream(branch.name) }
        if let upstream = branch.upstream {
            AlternateMenuItem(
                primary: MenuItem(title: String(localized: "Delete \(branch.name)\u{2026}", bundle: .module), icon: "trash", enabled: !current, destructive: true) { window.sync.confirmDelete(branch) },
                alternate: MenuItem(title: String(localized: "Delete here and on \(upstream.split(separator: "/").first.map(String.init) ?? upstream)\u{2026}", bundle: .module), icon: "trash", enabled: !current, destructive: true) { window.sync.confirmDelete(branch, remoteToo: true) }
            )
        } else {
            MenuItem(title: String(localized: "Delete \(branch.name)\u{2026}", bundle: .module), icon: "trash", enabled: !current, destructive: true) { window.sync.confirmDelete(branch) }
        }
        Divider()
        MenuItem(title: String(localized: "Show in history", bundle: .module), icon: "clock.arrow.circlepath", enabled: true) { window.store.showRef(branch.name) }
        MenuItem(title: String(localized: "Copy name", bundle: .module), icon: "doc.on.doc", enabled: true) { window.copy(branch.name) }
        if window.preferences.expert {
            MenuItem(title: String(localized: "Copy pull request summary", bundle: .module), icon: "envelope", enabled: true) { LongTailActions.copyPullRequestSummary(window, branch: branch.name) }
            MenuItem(title: String(localized: "Compare with before rebase", bundle: .module), icon: "arrow.left.arrow.right", enabled: true) { CoverageActions.compareWithBeforeRebase(window, branch: branch.name) }
        }
    }
}

struct RemoteBranchMenu: View {
    let remote: RemoteBranch
    let window: WindowModel

    var body: some View {
        let head = window.headName
        let local = window.store.snapshot?.branches.contains { $0.name == remote.name } ?? false
        MenuItem(title: local ? String(localized: "Switch to \(remote.name)", bundle: .module) : String(localized: "Check out as \(remote.name)", bundle: .module), icon: "arrow.triangle.branch", enabled: true) { window.sync.checkOut(remote: remote) }
        MenuItem(title: String(localized: "Merge \(remote.fullName) into \(head)\u{2026}", bundle: .module), icon: "arrow.triangle.merge", enabled: true) { RewriteActions.openMerge(window, source: remote.fullName) }
        MenuItem(title: String(localized: "Rebase \(head) onto \(remote.fullName)\u{2026}", bundle: .module), icon: "arrow.triangle.swap", enabled: true) { RewriteActions.openRebase(window, onto: remote.fullName) }
        MenuItem(title: String(localized: "New branch from \(remote.fullName)\u{2026}", bundle: .module), icon: "plus", enabled: true) { window.sync.newBranch(from: remote.fullName) }
        Divider()
        MenuItem(title: String(localized: "Show in history", bundle: .module), icon: "clock.arrow.circlepath", enabled: true) { window.store.showRef(remote.fullName) }
        MenuItem(title: String(localized: "Copy name", bundle: .module), icon: "doc.on.doc", enabled: true) { window.copy(remote.fullName) }
        Divider()
        MenuItem(title: String(localized: "Delete \(remote.name) on \(remote.remote)\u{2026}", bundle: .module), icon: "trash", enabled: true, destructive: true) { window.sync.confirmDeleteRemote(remote: remote.remote, name: remote.name) }
    }
}

struct TagMenu: View {
    let tag: Tag
    let window: WindowModel

    var body: some View {
        MenuItem(title: String(localized: "Show in history", bundle: .module), icon: "clock.arrow.circlepath", enabled: true) { window.store.showRef(tag.name) }
        MenuItem(title: String(localized: "Check out \(tag.name)", bundle: .module), icon: "mappin.and.ellipse", enabled: true) { window.sync.confirmDetach(tag.target, subject: nil) }
        MenuItem(title: String(localized: "New branch from \(tag.name)\u{2026}", bundle: .module), icon: "arrow.triangle.branch", enabled: true) { window.sync.newBranch(from: tag.name) }
        MenuItem(title: String(localized: "Push \(tag.name) to \(window.sync.defaultRemote ?? "origin")", bundle: .module), icon: "arrow.up.to.line", enabled: window.sync.defaultRemote != nil) { window.sync.pushTag(tag.name) }
        MenuItem(title: String(localized: "Export archive\u{2026}", bundle: .module), icon: "archivebox", enabled: true) { LongTailActions.openArchive(window, ref: tag.name, label: tag.name) }
        if tag.annotated {
            MenuItem(title: String(localized: "Check signature", bundle: .module), icon: "checkmark.seal", enabled: true) { LongTailActions.checkTagSignature(window, tag: tag.name) }
        }
        Divider()
        MenuItem(title: String(localized: "Copy name", bundle: .module), icon: "doc.on.doc", enabled: true) { window.copy(tag.name) }
        AlternateMenuItem(
            primary: MenuItem(title: String(localized: "Delete \(tag.name)\u{2026}", bundle: .module), icon: "trash", enabled: true, destructive: true) { window.sync.confirmDeleteTag(tag) },
            alternate: MenuItem(title: String(localized: "Delete here and on \(window.sync.defaultRemote ?? "origin")\u{2026}", bundle: .module), icon: "trash", enabled: window.sync.defaultRemote != nil, destructive: true) { window.sync.confirmDeleteTag(tag, remoteToo: true) }
        )
    }
}

struct RemoteMenu: View {
    let remote: Remote
    let window: WindowModel

    var body: some View {
        MenuItem(title: String(localized: "Fetch \(remote.name)", bundle: .module), icon: "arrow.triangle.2.circlepath", enabled: true) { window.sync.fetch(remote: remote.name) }
        MenuItem(title: String(localized: "Edit \(remote.name)\u{2026}", bundle: .module), icon: "pencil", enabled: true) { window.sync.editRemote(remote.name) }
        MenuItem(title: String(localized: "Prune stale branches", bundle: .module), icon: "trash", enabled: true) { window.sync.pruneRemote(remote.name) }
        Divider()
        MenuItem(title: String(localized: "Copy URL", bundle: .module), icon: "doc.on.doc", enabled: true) { window.copy(remote.fetchURL, label: String(localized: "URL", bundle: .module)) }
        MenuItem(title: String(localized: "Remove \(remote.name)\u{2026}", bundle: .module), icon: "trash", enabled: true, destructive: true) { window.sync.confirmRemoveRemote(remote.name) }
    }
}

struct StashMenu: View {
    let stash: Stash
    let window: WindowModel

    var body: some View {
        AlternateMenuItem(
            primary: MenuItem(title: String(localized: "Apply", bundle: .module), icon: "tray.and.arrow.up", enabled: true) { RewriteActions.applyStash(window, index: stash.index, pop: false) },
            alternate: MenuItem(title: String(localized: "Apply and drop (pop)", bundle: .module), icon: "tray.and.arrow.up", enabled: true) { RewriteActions.applyStash(window, index: stash.index, pop: true) }
        )
        MenuItem(title: String(localized: "Pop", bundle: .module), icon: "tray.and.arrow.up", enabled: true) { RewriteActions.applyStash(window, index: stash.index, pop: true) }
        MenuItem(title: String(localized: "New branch from stash\u{2026}", bundle: .module), icon: "arrow.triangle.branch", enabled: true) { RewriteActions.openStashBranch(window, index: stash.index) }
        Divider()
        MenuItem(title: String(localized: "Copy name", bundle: .module), icon: "doc.on.doc", enabled: true) { window.copy(stash.selector) }
        MenuItem(title: String(localized: "Drop\u{2026}", bundle: .module), icon: "trash", enabled: true, destructive: true) { RewriteActions.confirmDropStash(window, index: stash.index) }
    }
}

struct WorkingFileMenu: View {
    let file: WorkingFile
    let window: WindowModel

    var body: some View {
        let name = PathParts.split(file.path).name
        let ext = name.firstMatch(of: /\.[A-Za-z0-9]+$/).map { String($0.output) }
        if file.status == .conflicted {
            MenuItem(title: String(localized: "Open in merge tool", bundle: .module), icon: "arrow.triangle.merge", enabled: true) { RewriteActions.openMergeTool(window, path: file.path) }
        } else {
            MenuItem(title: file.staged == .full ? String(localized: "Unstage", bundle: .module) : String(localized: "Stage", bundle: .module), icon: file.staged == .full ? "minus" : "plus", enabled: true) { window.toggleStage(file) }
            MenuItem(title: String(localized: "Discard changes\u{2026}", bundle: .module), icon: "arrow.uturn.backward", enabled: true, destructive: true) { window.confirmDiscard([file.path]) }
            MenuItem(title: String(localized: "Stash this file\u{2026}", bundle: .module), icon: "tray.and.arrow.down", enabled: true) { RewriteActions.openStash(window, paths: [file.path]) }
            if file.status != .untracked {
                MenuItem(title: String(localized: "Open in diff tool", bundle: .module), icon: "plusminus", enabled: true) { CoverageActions.openDiffTool(window, file: file) }
            }
        }
        Divider()
        if file.status != .untracked {
            MenuItem(title: String(localized: "Blame", bundle: .module), icon: "person.text.rectangle", enabled: true) { window.openBlame(path: file.path) }
            MenuItem(title: String(localized: "File history", bundle: .module), icon: "clock", enabled: true) { window.openFileHistory(path: file.path) }
            Divider()
        }
        MenuItem(title: String(localized: "Ignore \(name)", bundle: .module), icon: "eye.slash", enabled: true) { LongTailActions.ignore(window, pattern: RepositoryStore.ignorePattern(forPath: file.path)) }
        if let ext {
            MenuItem(title: String(localized: "Ignore all \(ext) files", bundle: .module), icon: "eye.slash", enabled: true) { LongTailActions.ignore(window, pattern: RepositoryStore.ignorePattern(forExtension: ext)) }
        }
        if window.preferences.expert, file.status == .modified {
            MenuItem(title: String(localized: "Assume unchanged", bundle: .module), icon: "lock", enabled: true) { LongTailActions.assumeUnchanged(window, path: file.path) }
            MenuItem(title: String(localized: "Skip worktree", bundle: .module), icon: "lock", enabled: true) { LongTailActions.skipWorktree(window, path: file.path) }
        }
        if window.preferences.expert, file.status == .untracked {
            MenuItem(title: String(localized: "Intent to add", bundle: .module), icon: "plus", enabled: true) { LongTailActions.intentToAdd(window, path: file.path) }
        }
        if file.status == .modified || file.status == .added || file.status == .renamed || file.status == .typeChanged {
            Divider()
            MenuItem(title: String(localized: "Rename\u{2026}", bundle: .module), icon: "pencil", enabled: true) { LongTailActions.openRename(window, path: file.path) }
            MenuItem(title: String(localized: "Stop tracking", bundle: .module), icon: "eye.slash", enabled: true) { LongTailActions.removeFile(window, path: file.path, keepFile: true) }
            MenuItem(title: String(localized: "Delete file\u{2026}", bundle: .module), icon: "trash", enabled: true, destructive: true) { LongTailActions.confirmDeleteFile(window, path: file.path) }
        }
        Divider()
        MenuItem(title: String(localized: "Reveal in Finder", bundle: .module), icon: "folder", enabled: file.status != .deleted) { window.reveal(file.path) }
        MenuItem(title: String(localized: "Copy path", bundle: .module), icon: "doc.on.doc", enabled: true) { window.copy(file.path, label: String(localized: "path", bundle: .module)) }
    }
}

struct CommitFileMenu: View {
    let id: OID
    let path: String
    let window: WindowModel

    var body: some View {
        let name = PathParts.split(path).name
        MenuItem(title: String(localized: "Blame at \(id.short)", bundle: .module), icon: "person.text.rectangle", enabled: true) { window.openBlame(path: path, revision: id.rawValue) }
        MenuItem(title: String(localized: "File history", bundle: .module), icon: "clock", enabled: true) { window.openFileHistory(path: path, selecting: id) }
        MenuItem(title: String(localized: "Open \(name) at \(id.short)", bundle: .module), icon: "doc.text", enabled: true) { PlacesActions.openFile(window, path: path, at: id) }
        MenuItem(title: String(localized: "Restore \(name) from \(id.short)\u{2026}", bundle: .module), icon: "arrow.counterclockwise", enabled: true) { window.confirmRestore(path: path, from: id) }
        Divider()
        MenuItem(title: String(localized: "Copy path", bundle: .module), icon: "doc.on.doc", enabled: true) { window.copy(path, label: String(localized: "path", bundle: .module)) }
    }
}
