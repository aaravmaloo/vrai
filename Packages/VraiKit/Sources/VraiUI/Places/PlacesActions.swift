import AppKit
import SwiftUI
import VraiCore
import VraiGit

struct PlacesOpener {
    let app: AppModel
    let openWindow: OpenWindowAction

    @MainActor func open(_ path: String, window: WindowModel) {
        let name = PlacesCopy.name(path)
        Task { @MainActor in
            do {
                let reference = try await app.open(path: path)
                openWindow(value: reference)
                window.toasts.show(Toast(message: String(localized: "Opened \(name) in a new window", bundle: .module), icon: "macwindow"))
            } catch {
                PlacesActions.report(error, window, failure: String(localized: "\(name) didn't open", bundle: .module))
            }
        }
    }
}

@MainActor
enum PlacesActions {
    static func worktreeKey(_ path: String) -> String { "worktree:" + path }
    static func submoduleKey(_ path: String) -> String { "submodule:" + path }

    static func selectedWorktree(_ store: RepositoryStore) -> String? {
        guard store.view == .worktrees else { return nil }
        if let key = store.sidebarSelection, key.hasPrefix("worktree:") { return String(key.dropFirst("worktree:".count)) }
        return store.snapshot?.worktrees.first?.path
    }

    static func selectedSubmodule(_ store: RepositoryStore) -> String? {
        guard store.view == .submodules else { return nil }
        if let key = store.sidebarSelection, key.hasPrefix("submodule:") { return String(key.dropFirst("submodule:".count)) }
        return store.snapshot?.submodules.first?.path
    }

    static func showWorktree(_ window: WindowModel, path: String? = nil) {
        window.show(.worktrees)
        if let path { window.store.sidebarSelection = worktreeKey(path) }
        if window.widthClass.isNarrow { window.columns = .detailOnly }
    }

    static func showSubmodule(_ window: WindowModel, path: String? = nil) {
        window.show(.submodules)
        if let path { window.store.sidebarSelection = submoduleKey(path) }
        if window.widthClass.isNarrow { window.columns = .detailOnly }
    }

    static func showInHistory(_ window: WindowModel, id: OID) {
        window.show(.history)
        window.store.selectCommit(id, scroll: true)
        if window.widthClass == .compact { window.pane = .detail }
    }

    static func openAddWorktree(_ window: WindowModel, branch: String? = nil) {
        window.sheets.present { WorktreeSheet(initialBranch: branch) }
    }

    static func openAddSubmodule(_ window: WindowModel) {
        window.sheets.present { SubmoduleSheet() }
    }

    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
    }

    static func revealToast(_ window: WindowModel, path: String) {
        reveal(path)
        window.toasts.show(Toast(message: String(localized: "Revealed \(PathText.abbreviated(path)) in Finder", bundle: .module), icon: "folder", timeout: Toast.brief))
    }

    static func addWorktree(_ window: WindowModel, path: String, branch: String, createBranch: Bool, startPoint: String? = nil, opener: PlacesOpener?) {
        let store = window.store
        Task {
            do {
                let summary = try await store.addWorktree(path: path, branch: branch, createBranch: createBranch, startPoint: startPoint)
                let resolved = store.resolvedPath(path)
                let listed = store.snapshot?.worktrees.first { RepositoryStore.isSamePath($0.path, resolved) }?.path ?? resolved
                window.toasts.show(Toast(message: summary.message, detail: summary.detail, icon: "rectangle.on.rectangle", action: opener == nil ? nil : String(localized: "Open", bundle: .module)) {
                    opener?.open(listed, window: window)
                })
                if store.view == .worktrees { store.sidebarSelection = worktreeKey(listed) }
            } catch {
                report(error, window, failure: String(localized: "The worktree wasn't added", bundle: .module))
            }
        }
    }

    static func confirmRemoveWorktree(_ window: WindowModel, worktree: Worktree) {
        let name = PlacesCopy.name(worktree.path)
        if worktree.isMain {
            window.alerts.present(AlertRequest(
                title: String(localized: "This is the main worktree", bundle: .module),
                message: String(localized: "\(name) holds the repository itself, so it can't be removed. Remove the other worktrees instead.", bundle: .module),
                actions: [AlertAction(title: String(localized: "Close", bundle: .module), role: .cancel)]
            ))
            return
        }
        var message = String(localized: "This deletes the folder \(PathText.abbreviated(worktree.path)).", bundle: .module)
        if let branch = worktree.branch {
            message += " " + String(localized: "The branch \(branch) and its commits stay in the repository.", bundle: .module)
        } else {
            message += " " + String(localized: "Its commits stay in the repository.", bundle: .module)
        }
        let changes = worktree.changes ?? 0
        if changes > 0 {
            message += " " + String(localized: "Its \(n(changes, "uncommitted change")) are deleted with it. A copy stays in Undo history for 14 days.", bundle: .module)
        }
        if worktree.locked {
            message += " " + (worktree.lockReason.map { String(localized: "It's locked (\($0)); removing it unlocks it first.", bundle: .module) } ?? String(localized: "It's locked; removing it unlocks it first.", bundle: .module))
        }
        window.alerts.present(AlertRequest(
            title: String(localized: "Remove the worktree \(name)?", bundle: .module),
            message: message,
            actions: [
                AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel),
                AlertAction(title: String(localized: "Remove worktree", bundle: .module), role: .destructive) {
                    removeWorktree(window, worktree: worktree, force: changes > 0)
                }
            ]
        ))
    }

    static func removeWorktree(_ window: WindowModel, worktree: Worktree, force: Bool) {
        let store = window.store
        Task {
            do {
                let summary = try await store.removeWorktree(path: worktree.path, force: force)
                if store.sidebarSelection == worktreeKey(worktree.path) { store.sidebarSelection = nil }
                if force, (worktree.changes ?? 0) > 0 {
                    window.toasts.show(RewriteActions.undoToast(window, message: summary.message, detail: summary.detail, icon: "trash"))
                } else {
                    window.toasts.show(Toast(message: summary.message, detail: summary.detail, icon: "trash"))
                }
            } catch let error as GitError where error.code == .worktreeDirty && !force {
                window.alerts.present(AlertRequest(
                    title: ErrorCopy.places(error)?.title ?? ErrorCopy(error).title,
                    message: ErrorCopy.places(error)?.message,
                    actions: [
                        AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel),
                        AlertAction(title: String(localized: "Remove anyway", bundle: .module), role: .destructive) {
                            removeWorktree(window, worktree: worktree, force: true)
                        }
                    ]
                ))
            } catch {
                report(error, window, failure: String(localized: "The worktree wasn't removed", bundle: .module))
            }
        }
    }

    static func setLocked(_ window: WindowModel, worktree: Worktree, locked: Bool) {
        let store = window.store
        Task {
            do {
                let summary = try await store.setWorktreeLocked(path: worktree.path, locked: locked)
                window.toasts.show(Toast(message: summary.message, detail: summary.detail, icon: "lock"))
            } catch {
                report(error, window, failure: locked ? String(localized: "The worktree wasn't locked", bundle: .module) : String(localized: "The worktree wasn't unlocked", bundle: .module))
            }
        }
    }

    static func prune(_ window: WindowModel) {
        let store = window.store
        Task {
            do {
                let summary = try await store.pruneWorktrees()
                window.toasts.show(Toast(message: summary.message, detail: summary.detail, icon: "trash"))
            } catch {
                report(error, window, failure: String(localized: "Prune didn't finish", bundle: .module))
            }
        }
    }

    static func submodule(_ window: WindowModel, path: String, action: SubmoduleAction) {
        let store = window.store
        Task {
            do {
                let summary = try await store.submodule(path: path, action: action)
                switch action {
                case .record:
                    window.toasts.show(Toast(message: summary.message, detail: summary.detail, icon: "shippingbox", action: String(localized: "Show changes", bundle: .module)) { window.show(.changes) })
                case .sync:
                    window.toasts.show(Toast(message: summary.message, detail: summary.detail, icon: "arrow.triangle.2.circlepath"))
                case .deinit:
                    window.toasts.show(Toast(message: summary.message, detail: summary.detail, icon: "trash"))
                default:
                    window.toasts.show(Toast(message: summary.message, detail: summary.detail, icon: "shippingbox"))
                }
            } catch {
                let failure: String
                switch action {
                case .deinit: failure = String(localized: "The submodule wasn't deinitialized", bundle: .module)
                case .sync: failure = String(localized: "The submodule URLs didn't sync", bundle: .module)
                case .record: failure = String(localized: "The new commit wasn't staged", bundle: .module)
                default: failure = String(localized: "The submodule didn't update", bundle: .module)
                }
                report(error, window, failure: failure)
            }
        }
    }

    static func confirmDeinit(_ window: WindowModel, module: Submodule) {
        let name = PlacesCopy.name(module.path)
        var message = String(localized: "This removes its files from your working tree and stops updating it. It stays in .gitmodules, so you can initialize it again later.", bundle: .module)
        if module.state == .ahead, module.ahead > 0 {
            message += " " + String(localized: "Its \(n(module.ahead, "new commit")) aren't recorded in \(window.repositoryName) yet.", bundle: .module)
        }
        if module.state == .modified {
            message += " " + String(localized: "Changes you made inside it are lost.", bundle: .module)
        }
        window.alerts.present(AlertRequest(
            title: String(localized: "Deinitialize \(name)?", bundle: .module),
            message: message,
            actions: [
                AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel),
                AlertAction(title: String(localized: "Deinitialize", bundle: .module), role: .destructive) {
                    submodule(window, path: module.path, action: .deinit)
                }
            ]
        ))
    }

    static func addSubmodule(_ window: WindowModel, url: String, path: String, branch: String?) {
        let store = window.store
        Task {
            do {
                let summary = try await store.addSubmodule(url: url, path: path, branch: branch)
                window.toasts.show(Toast(message: summary.message, detail: summary.detail, icon: "shippingbox", action: String(localized: "Show changes", bundle: .module)) { window.show(.changes) })
            } catch {
                report(error, window, failure: String(localized: "The submodule wasn't added", bundle: .module))
            }
        }
    }

    static func confirmRemoveReplacement(_ window: WindowModel, entry: RefEntry) {
        guard let object = entry.replacedObject else { return }
        let short = String(object.prefix(window.preferences.expert ? 10 : 7))
        window.alerts.present(AlertRequest(
            title: String(localized: "Remove the replacement for \(short)?", bundle: .module),
            message: String(localized: "git shows the original object again everywhere. A copy stays in Undo history for 14 days.", bundle: .module),
            actions: [
                AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel),
                AlertAction(title: String(localized: "Remove replacement", bundle: .module), role: .destructive) {
                    let store = window.store
                    Task {
                        do {
                            let summary = try await store.removeReplacement(object: object)
                            window.toasts.show(RewriteActions.undoToast(window, message: summary.message, detail: summary.detail, icon: "trash"))
                        } catch {
                            report(error, window, failure: String(localized: "The replacement wasn't removed", bundle: .module))
                        }
                    }
                }
            ]
        ))
    }

    static func openFile(_ window: WindowModel, path: String, at id: OID) {
        let store = window.store
        let name = PathParts.split(path).name
        let short = id.short(expert: window.preferences.expert)
        Task {
            do {
                let url = try await store.exportFile(path: path, at: id)
                NSWorkspace.shared.open(url)
                window.toasts.show(Toast(message: String(localized: "Opened \(name) at \(short)", bundle: .module), detail: String(localized: "A read-only copy.", bundle: .module), icon: "doc.text"))
            } catch {
                report(error, window, failure: String(localized: "\(name) at \(short) didn't open", bundle: .module))
            }
        }
    }

    static func report(_ error: Error, _ window: WindowModel, failure: String) {
        guard let error = error as? GitError else {
            window.alerts.present(AlertRequest(title: failure, message: String(describing: error), actions: [AlertAction(title: String(localized: "Close", bundle: .module), role: .cancel)]))
            return
        }
        if error.code == .cancelled { return }
        let copy = ErrorCopy.places(error) ?? ErrorCopy(error)
        let title: String
        if case .unknown = error.code, ErrorCopy.places(error) == nil { title = failure } else { title = copy.title }
        window.alerts.present(AlertRequest(title: title, message: copy.message, actions: [AlertAction(title: String(localized: "Close", bundle: .module), role: .cancel)]))
    }
}
