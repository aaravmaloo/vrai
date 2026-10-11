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
        let bisecting: Bool = {
            if case .bisecting? = store.snapshot?.state { return true }
            return false
        }()
        AlternateMenuItem(
            primary: MenuItem(title: String(localized: "Check out \(id.short)", bundle: .module), icon: "mappin.and.ellipse"),
            alternate: MenuItem(title: String(localized: "Create branch here and switch\u{2026}", bundle: .module), icon: "arrow.triangle.branch")
        )
        MenuItem(title: String(localized: "New branch from here\u{2026}", bundle: .module), icon: "arrow.triangle.branch")
        MenuItem(title: String(localized: "New tag here\u{2026}", bundle: .module), icon: "tag")
        Divider()
        AlternateMenuItem(
            primary: MenuItem(title: String(localized: "Cherry-pick onto \(head)", bundle: .module), icon: "arrow.turn.down.right"),
            alternate: MenuItem(title: String(localized: "Cherry-pick with options\u{2026}", bundle: .module), icon: "arrow.turn.down.right")
        )
        MenuItem(title: String(localized: "Revert commit", bundle: .module), icon: "arrow.uturn.backward")
        MenuItem(title: String(localized: "Reset \(head) to here\u{2026}", bundle: .module), icon: "arrow.counterclockwise")
        MenuItem(title: String(localized: "Rebase \(head) onto here\u{2026}", bundle: .module), icon: "arrow.triangle.swap")
        MenuItem(title: String(localized: "Interactive rebase from here\u{2026}", bundle: .module), icon: "list.number")
        Divider()
        if bisecting {
            MenuItem(title: String(localized: "Mark as good", bundle: .module), icon: "checkmark.circle")
            MenuItem(title: String(localized: "Mark as bad", bundle: .module), icon: "xmark.circle.fill")
        } else {
            MenuItem(title: String(localized: "Start bisect here\u{2026}", bundle: .module), icon: "scope")
        }
        if window.preferences.expert {
            Divider()
            MenuItem(title: String(localized: "Create fixup commit for this", bundle: .module), icon: "bandage")
            MenuItem(title: String(localized: "Reword in place\u{2026}", bundle: .module), icon: "pencil")
            MenuItem(title: String(localized: "Split commit\u{2026}", bundle: .module), icon: "rectangle.split.2x1")
            MenuItem(title: String(localized: "Show object", bundle: .module), icon: "cube")
        }
        Divider()
        AlternateMenuItem(
            primary: MenuItem(title: String(localized: "Copy hash", bundle: .module), icon: "doc.on.doc", enabled: true) { window.copy(id.short(expert: window.preferences.expert)) },
            alternate: MenuItem(title: String(localized: "Copy full hash", bundle: .module), icon: "doc.on.doc", enabled: true) { window.copy(id.rawValue, label: String(localized: "full hash", bundle: .module)) }
        )
        MenuItem(title: String(localized: "Copy subject", bundle: .module), icon: "text.alignleft", enabled: commit != nil) {
            if let commit { window.copy(commit.subject, label: String(localized: "subject", bundle: .module)) }
        }
        MenuItem(title: String(localized: "Save as patch\u{2026}", bundle: .module), icon: "square.and.arrow.down")
        MenuItem(title: String(localized: "Export archive\u{2026}", bundle: .module), icon: "archivebox")
    }
}

struct WipMenu: View {
    let window: WindowModel

    var body: some View {
        MenuItem(title: String(localized: "Open Changes", bundle: .module), icon: "square.and.pencil", enabled: true) { window.show(.changes) }
        MenuItem(title: String(localized: "Stash changes\u{2026}", bundle: .module), icon: "tray.and.arrow.down")
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
            primary: MenuItem(title: String(localized: "Switch to \(branch.name)", bundle: .module), icon: "arrow.triangle.branch"),
            alternate: MenuItem(title: String(localized: "Switch and bring changes", bundle: .module), icon: "arrow.triangle.branch")
        )
        AlternateMenuItem(
            primary: MenuItem(title: String(localized: "Merge \(branch.name) into \(head)\u{2026}", bundle: .module), icon: "arrow.triangle.merge"),
            alternate: MenuItem(title: String(localized: "Merge \(branch.name) now", bundle: .module), icon: "arrow.triangle.merge")
        )
        MenuItem(title: String(localized: "Rebase \(head) onto \(branch.name)\u{2026}", bundle: .module), icon: "arrow.triangle.swap")
        Divider()
        if current {
            AlternateMenuItem(
                primary: MenuItem(title: branch.ahead > 0 ? String(localized: "Push \(n(branch.ahead, "commit"))", bundle: .module) : String(localized: "Push", bundle: .module), icon: "arrow.up.to.line"),
                alternate: MenuItem(title: String(localized: "Force push with lease", bundle: .module), icon: "arrow.up.to.line", destructive: true)
            )
            if branch.upstream != nil {
                AlternateMenuItem(
                    primary: MenuItem(title: branch.behind > 0 ? String(localized: "Pull \(n(branch.behind, "commit"))", bundle: .module) : String(localized: "Pull", bundle: .module), icon: "arrow.down.to.line"),
                    alternate: MenuItem(title: String(localized: "Pull with rebase", bundle: .module), icon: "arrow.down.to.line")
                )
            }
        }
        MenuItem(title: String(localized: "New branch from \(branch.name)\u{2026}", bundle: .module), icon: "plus")
        MenuItem(title: String(localized: "Rename\u{2026}", bundle: .module), icon: "pencil")
        MenuItem(title: branch.upstream == nil ? String(localized: "Set upstream\u{2026}", bundle: .module) : String(localized: "Change upstream\u{2026}", bundle: .module), icon: "link")
        if let upstream = branch.upstream {
            AlternateMenuItem(
                primary: MenuItem(title: String(localized: "Delete \(branch.name)\u{2026}", bundle: .module), icon: "trash", destructive: true),
                alternate: MenuItem(title: String(localized: "Delete here and on \(upstream.split(separator: "/").first.map(String.init) ?? upstream)\u{2026}", bundle: .module), icon: "trash", destructive: true)
            )
        } else {
            MenuItem(title: String(localized: "Delete \(branch.name)\u{2026}", bundle: .module), icon: "trash", destructive: true)
        }
        Divider()
        MenuItem(title: String(localized: "Show in history", bundle: .module), icon: "clock.arrow.circlepath", enabled: true) { window.store.showRef(branch.name) }
        MenuItem(title: String(localized: "Copy name", bundle: .module), icon: "doc.on.doc", enabled: true) { window.copy(branch.name) }
        if window.preferences.expert {
            MenuItem(title: String(localized: "Copy pull request summary", bundle: .module), icon: "envelope")
        }
    }
}

struct RemoteBranchMenu: View {
    let remote: RemoteBranch
    let window: WindowModel

    var body: some View {
        let head = window.headName
        let local = window.store.snapshot?.branches.contains { $0.name == remote.name } ?? false
        MenuItem(title: local ? String(localized: "Switch to \(remote.name)", bundle: .module) : String(localized: "Check out as \(remote.name)", bundle: .module), icon: "arrow.triangle.branch")
        MenuItem(title: String(localized: "Merge \(remote.fullName) into \(head)\u{2026}", bundle: .module), icon: "arrow.triangle.merge")
        MenuItem(title: String(localized: "Rebase \(head) onto \(remote.fullName)\u{2026}", bundle: .module), icon: "arrow.triangle.swap")
        MenuItem(title: String(localized: "New branch from \(remote.fullName)\u{2026}", bundle: .module), icon: "plus")
        Divider()
        MenuItem(title: String(localized: "Show in history", bundle: .module), icon: "clock.arrow.circlepath", enabled: true) { window.store.showRef(remote.fullName) }
        MenuItem(title: String(localized: "Copy name", bundle: .module), icon: "doc.on.doc", enabled: true) { window.copy(remote.fullName) }
        Divider()
        MenuItem(title: String(localized: "Delete \(remote.name) on \(remote.remote)\u{2026}", bundle: .module), icon: "trash", destructive: true)
    }
}

struct TagMenu: View {
    let tag: Tag
    let window: WindowModel

    var body: some View {
        MenuItem(title: String(localized: "Show in history", bundle: .module), icon: "clock.arrow.circlepath", enabled: true) { window.store.showRef(tag.name) }
        MenuItem(title: String(localized: "Check out \(tag.name)", bundle: .module), icon: "mappin.and.ellipse")
        MenuItem(title: String(localized: "New branch from \(tag.name)\u{2026}", bundle: .module), icon: "arrow.triangle.branch")
        MenuItem(title: String(localized: "Push \(tag.name) to origin", bundle: .module), icon: "arrow.up.to.line")
        MenuItem(title: String(localized: "Export archive\u{2026}", bundle: .module), icon: "archivebox")
        Divider()
        MenuItem(title: String(localized: "Copy name", bundle: .module), icon: "doc.on.doc", enabled: true) { window.copy(tag.name) }
        AlternateMenuItem(
            primary: MenuItem(title: String(localized: "Delete \(tag.name)\u{2026}", bundle: .module), icon: "trash", destructive: true),
            alternate: MenuItem(title: String(localized: "Delete here and on origin\u{2026}", bundle: .module), icon: "trash", destructive: true)
        )
    }
}

struct RemoteMenu: View {
    let remote: Remote
    let window: WindowModel

    var body: some View {
        MenuItem(title: String(localized: "Fetch \(remote.name)", bundle: .module), icon: "arrow.triangle.2.circlepath")
        MenuItem(title: String(localized: "Edit \(remote.name)\u{2026}", bundle: .module), icon: "pencil")
        MenuItem(title: String(localized: "Prune stale branches", bundle: .module), icon: "trash")
        Divider()
        MenuItem(title: String(localized: "Copy URL", bundle: .module), icon: "doc.on.doc", enabled: true) { window.copy(remote.fetchURL, label: String(localized: "URL", bundle: .module)) }
        MenuItem(title: String(localized: "Remove \(remote.name)\u{2026}", bundle: .module), icon: "trash", destructive: true)
    }
}

struct StashMenu: View {
    let stash: Stash
    let window: WindowModel

    var body: some View {
        AlternateMenuItem(
            primary: MenuItem(title: String(localized: "Apply", bundle: .module), icon: "tray.and.arrow.up"),
            alternate: MenuItem(title: String(localized: "Apply and drop (pop)", bundle: .module), icon: "tray.and.arrow.up")
        )
        MenuItem(title: String(localized: "Pop", bundle: .module), icon: "tray.and.arrow.up")
        MenuItem(title: String(localized: "New branch from stash\u{2026}", bundle: .module), icon: "arrow.triangle.branch")
        Divider()
        MenuItem(title: String(localized: "Copy name", bundle: .module), icon: "doc.on.doc", enabled: true) { window.copy(stash.selector) }
        MenuItem(title: String(localized: "Drop\u{2026}", bundle: .module), icon: "trash", destructive: true)
    }
}

struct WorkingFileMenu: View {
    let file: WorkingFile
    let window: WindowModel

    var body: some View {
        let name = PathParts.split(file.path).name
        let ext = name.firstMatch(of: /\.[A-Za-z0-9]+$/).map { String($0.output) }
        if file.status == .conflicted {
            MenuItem(title: String(localized: "Open in merge tool", bundle: .module), icon: "arrow.triangle.merge")
        } else {
            MenuItem(title: file.staged == .full ? String(localized: "Unstage", bundle: .module) : String(localized: "Stage", bundle: .module), icon: file.staged == .full ? "minus" : "plus", enabled: true) { window.toggleStage(file) }
            MenuItem(title: String(localized: "Discard changes\u{2026}", bundle: .module), icon: "arrow.uturn.backward", enabled: true, destructive: true) { window.confirmDiscard([file.path]) }
            MenuItem(title: String(localized: "Stash this file\u{2026}", bundle: .module), icon: "tray.and.arrow.down")
        }
        Divider()
        if file.status != .untracked {
            MenuItem(title: String(localized: "Blame", bundle: .module), icon: "person.text.rectangle")
            MenuItem(title: String(localized: "File history", bundle: .module), icon: "clock")
            Divider()
        }
        MenuItem(title: String(localized: "Ignore \(name)", bundle: .module), icon: "eye.slash")
        if let ext {
            MenuItem(title: String(localized: "Ignore all \(ext) files", bundle: .module), icon: "eye.slash")
        }
        if window.preferences.expert, file.status == .modified {
            MenuItem(title: String(localized: "Assume unchanged", bundle: .module), icon: "lock")
        }
        if window.preferences.expert, file.status == .untracked {
            MenuItem(title: String(localized: "Intent to add", bundle: .module), icon: "plus")
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
        MenuItem(title: String(localized: "Blame at \(id.short)", bundle: .module), icon: "person.text.rectangle")
        MenuItem(title: String(localized: "File history", bundle: .module), icon: "clock")
        MenuItem(title: String(localized: "Open \(name) at \(id.short)", bundle: .module), icon: "doc.text")
        MenuItem(title: String(localized: "Restore \(name) from \(id.short)\u{2026}", bundle: .module), icon: "arrow.counterclockwise", enabled: true) { window.confirmRestore(path: path, from: id) }
        Divider()
        MenuItem(title: String(localized: "Copy path", bundle: .module), icon: "doc.on.doc", enabled: true) { window.copy(path, label: String(localized: "path", bundle: .module)) }
    }
}
