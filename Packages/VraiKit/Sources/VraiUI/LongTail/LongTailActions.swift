import AppKit
import SwiftUI
import VraiCore
import VraiGit

@MainActor
enum LongTailActions {
    private static var running: Set<ObjectIdentifier> = []

    static func openArchive(_ window: WindowModel, ref: String, label: String? = nil) {
        window.sheets.present { ArchiveSheet(ref: ref, label: label) }
    }

    static func openBundle(_ window: WindowModel) {
        window.sheets.present { BundleSheet() }
    }

    static func openApplyPatches(_ window: WindowModel, files: [URL] = []) {
        window.sheets.present { ApplyPatchesSheet(initialFiles: files) }
    }

    static func openSparse(_ window: WindowModel) {
        window.sheets.present { SparseSheet() }
    }

    static func openInfo(_ window: WindowModel) {
        window.sheets.present { RepositoryInfoSheet() }
    }

    static func openTextFile(_ window: WindowModel, _ kind: TextFileKind) {
        window.sheets.present { TextFileSheet(kind: kind) }
    }

    static func openCompare(_ window: WindowModel, first: String? = nil, second: String? = nil) {
        window.sheets.present { CompareSheet(initialFirst: first, initialSecond: second) }
    }

    static func openReword(_ window: WindowModel, id: OID) {
        window.sheets.present { RewordSheet(id: id) }
    }

    static func openSplit(_ window: WindowModel, id: OID) {
        window.sheets.present { SplitSheet(id: id) }
    }

    static func openClean(_ window: WindowModel, ignored: Bool) {
        window.sheets.present { CleanSheet(ignored: ignored) }
    }

    static func openRename(_ window: WindowModel, path: String) {
        window.sheets.present { RenameFileSheet(path: path) }
    }

    static func savePatch(_ window: WindowModel, id: OID) {
        if window.preferences.expert {
            window.sheets.present { SavePatchSheet(id: id) }
            return
        }
        let store = window.store
        let folder = desktop()
        Task {
            do {
                let files = try await store.savePatches(ids: [id], to: folder)
                let name = files.first?.lastPathComponent ?? ""
                window.toasts.show(Toast(message: String(localized: "Saved a patch to the Desktop", bundle: .module), detail: name, icon: "square.and.arrow.down", action: String(localized: "Show in Finder", bundle: .module)) {
                    LongTailReveal.show(files)
                })
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "The patch wasn't saved", bundle: .module))
            }
        }
    }

    static func fixup(_ window: WindowModel, id: OID) {
        let store = window.store
        Task {
            let subject = await store.subject(of: id) ?? id.short
            guard await store.hasStagedChanges() else {
                window.changes.prefill(subject: "fixup! " + subject)
                window.show(.changes)
                window.toasts.show(Toast(message: String(localized: "Fixup message ready in Changes", bundle: .module), detail: String(localized: "Stage the fix and commit; autosquash folds it in on the next interactive rebase.", bundle: .module), icon: "bandage"))
                return
            }
            do {
                let made = try await store.fixupCommit(for: id)
                window.toasts.show(RewriteActions.undoToast(window, message: String(localized: "Created fixup commit \(made.short)", bundle: .module), detail: String(localized: "It folds into \(id.short) on the next interactive rebase with autosquash.", bundle: .module), icon: "bandage"))
                RewriteActions.selectHead(store)
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "The fixup commit wasn't made", bundle: .module))
            }
        }
    }

    static func copyPullRequestSummary(_ window: WindowModel, branch: String) {
        let store = window.store
        Task {
            do {
                let summary = try await store.pullRequestSummary(branch: branch)
                Clipboard.copy(summary.text)
                if summary.published {
                    window.toasts.show(Toast(message: String(localized: "Copied the pull request summary", bundle: .module), detail: String(localized: "For \(branch), ready to paste.", bundle: .module), icon: "envelope"))
                } else {
                    window.toasts.show(Toast(tone: .warning, message: String(localized: "Copied the pull request summary", bundle: .module), detail: String(localized: "\(branch) isn't pushed yet, so others can't fetch it. Push it first.", bundle: .module), icon: "envelope", action: String(localized: "Push", bundle: .module)) {
                        window.sync.push()
                    })
                }
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "The summary wasn't made", bundle: .module))
            }
        }
    }

    static func ignore(_ window: WindowModel, pattern: String) {
        let store = window.store
        Task {
            do {
                let result = try await store.ignore(pattern: pattern)
                window.toasts.show(Toast(
                    message: result.added ? String(localized: "Added \(result.pattern) to .gitignore", bundle: .module) : String(localized: ".gitignore already has \(result.pattern)", bundle: .module),
                    detail: String(localized: "Commit .gitignore to share the rule.", bundle: .module),
                    icon: "eye.slash"
                ))
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "The rule wasn't added", bundle: .module))
            }
        }
    }

    static func assumeUnchanged(_ window: WindowModel, path: String, on: Bool = true) {
        let store = window.store
        let name = PathParts.split(path).name
        Task {
            do {
                try await store.setAssumeUnchanged(paths: [path], on: on)
                if on {
                    window.toasts.show(Toast(message: String(localized: "Git will assume \(name) is unchanged", bundle: .module), detail: String(localized: "Its edits stay out of Changes until you undo this.", bundle: .module), icon: "lock", action: String(localized: "Undo", bundle: .module)) {
                        assumeUnchanged(window, path: path, on: false)
                    })
                } else {
                    window.toasts.show(Toast(message: String(localized: "Git watches \(name) again", bundle: .module), icon: "eye"))
                }
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "The index flag wasn't changed", bundle: .module))
            }
        }
    }

    static func intentToAdd(_ window: WindowModel, path: String) {
        let store = window.store
        let name = PathParts.split(path).name
        Task {
            do {
                try await store.intentToAdd(paths: [path])
                window.toasts.show(Toast(message: String(localized: "Git now tracks \(name)", bundle: .module), detail: String(localized: "Its contents aren't staged yet, so it shows in diffs.", bundle: .module), icon: "plus", timeout: Toast.brief))
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "The file wasn't added", bundle: .module))
            }
        }
    }

    static func confirmDeleteFile(_ window: WindowModel, path: String) {
        let name = PathParts.split(path).name
        window.alerts.present(AlertRequest(
            title: String(localized: "Delete \(name)?", bundle: .module),
            message: String(localized: "Git removes it from the folder and stages the deletion. A copy stays in Undo history for 14 days.", bundle: .module),
            actions: [
                AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel),
                AlertAction(title: String(localized: "Delete", bundle: .module), role: .destructive) { removeFile(window, path: path, keepFile: false) }
            ]
        ))
    }

    static func removeFile(_ window: WindowModel, path: String, keepFile: Bool) {
        let store = window.store
        let name = PathParts.split(path).name
        Task {
            do {
                try await store.removeFile(path: path, keepFile: keepFile)
                if keepFile {
                    window.toasts.show(Toast(message: String(localized: "Stopped tracking \(name)", bundle: .module), detail: String(localized: "The file stays in the folder. Commit to record it; add it to .gitignore to keep it out.", bundle: .module), icon: "eye.slash"))
                } else {
                    window.toasts.show(Toast(message: String(localized: "Deleted \(name)", bundle: .module), detail: String(localized: "The deletion is staged.", bundle: .module), icon: "trash", action: String(localized: "Undo", bundle: .module)) {
                        window.undoLast()
                    })
                }
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "The file wasn't removed", bundle: .module))
            }
        }
    }

    static func checkTagSignature(_ window: WindowModel, tag: String) {
        let store = window.store
        Task {
            let report = await store.verifySignature(tag: tag)
            if report.good {
                window.toasts.show(Toast(tone: .success, message: String(localized: "\(tag) is signed by \(report.signer ?? String(localized: "a trusted key", bundle: .module))", bundle: .module), detail: [report.keyType, report.fingerprint].compactMap { $0 }.joined(separator: " "), icon: "checkmark.seal"))
            } else {
                let reason = report.message.split(separator: "\n").first.map(String.init) ?? ""
                window.toasts.show(Toast(tone: .warning, message: String(localized: "\(tag) has no signature git can verify", bundle: .module), detail: reason.isEmpty ? nil : reason, icon: "xmark.seal"))
            }
        }
    }

    static func openInTerminal(_ window: WindowModel) {
        guard let root = window.store.snapshot?.root else { return }
        let terminal = window.preferences.terminal
        if TerminalLauncher.open(root, terminal: terminal) {
            window.toasts.show(Toast(message: String(localized: "Opened \(window.repositoryName) in \(TerminalLauncher.name(for: terminal))", bundle: .module), icon: "terminal", timeout: Toast.brief))
        } else {
            window.toasts.show(Toast(tone: .warning, message: String(localized: "\(terminal) isn't installed", bundle: .module), detail: String(localized: "Pick another in Settings, General.", bundle: .module), icon: "terminal"))
        }
    }

    static func maintenance(_ window: WindowModel, _ task: MaintenanceTask) {
        let key = ObjectIdentifier(window)
        guard !running.contains(key) else {
            window.toasts.show(Toast(message: String(localized: "Maintenance is already running", bundle: .module), detail: String(localized: "Vrai runs one task at a time.", bundle: .module), icon: "wrench.and.screwdriver", timeout: Toast.brief))
            return
        }
        running.insert(key)
        let store = window.store
        let busy = window.toasts.show(Toast(message: busyTitle(task), detail: String(localized: "You can keep working.", bundle: .module), icon: "wrench.and.screwdriver", timeout: 3600, busy: true))
        Task {
            defer {
                running.remove(key)
                window.toasts.dismiss(busy)
            }
            do {
                let result = try await store.maintenance(task)
                window.toasts.show(Toast(message: doneTitle(task), detail: detail(result), icon: icon(task), action: String(localized: "Show console", bundle: .module)) {
                    window.console.open = true
                })
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "Maintenance didn't finish", bundle: .module))
            }
        }
    }

    static func verifyIntegrity(_ window: WindowModel) {
        let key = ObjectIdentifier(window)
        guard !running.contains(key) else { return }
        running.insert(key)
        let store = window.store
        let busy = window.toasts.show(Toast(message: String(localized: "Verifying integrity\u{2026}", bundle: .module), detail: String(localized: "git fsck reads every object.", bundle: .module), icon: "stethoscope", timeout: 3600, busy: true))
        Task {
            defer {
                running.remove(key)
                window.toasts.dismiss(busy)
            }
            do {
                let report = try await store.verifyIntegrity(packs: window.preferences.expert)
                if report.isHealthy {
                    let dangling = report.fsck.dangling.count
                    let detail = dangling == 0
                        ? String(localized: "Every object is reachable and intact.", bundle: .module)
                        : String(localized: "\(n(dangling, "dangling object")), which the reflog or Undo history may still keep.", bundle: .module)
                    window.toasts.show(Toast(message: String(localized: "No problems found", bundle: .module), detail: detail, icon: "stethoscope", action: String(localized: "Show console", bundle: .module)) {
                        window.console.open = true
                    })
                } else {
                    var lines = report.fsck.problems
                    lines += report.fsck.missing.map { String(localized: "missing \($0.type) \($0.oid)", bundle: .module) }
                    lines += report.badPacks.map { String(localized: "pack \($0) failed verify-pack", bundle: .module) }
                    let shown = lines.prefix(8).joined(separator: "\n")
                    var actions = [AlertAction(title: String(localized: "Close", bundle: .module), role: .cancel)]
                    for pack in report.badPacks.prefix(1) {
                        actions.insert(AlertAction(title: String(localized: "Rebuild the pack index", bundle: .module)) { repairPack(window, pack: pack) }, at: 0)
                    }
                    actions.insert(AlertAction(title: String(localized: "Report a git problem\u{2026}", bundle: .module)) { AppSheets.present(.bugReport, window: window) }, at: 0)
                    window.alerts.present(AlertRequest(
                        title: String(localized: "git found \(n(lines.count, "problem")) in \(window.repositoryName)", bundle: .module),
                        message: shown + (lines.count > 8 ? "\n" + String(localized: "and \(lines.count - 8) more in the console", bundle: .module) : ""),
                        actions: actions
                    ))
                }
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "The check didn't finish", bundle: .module))
            }
        }
    }

    static func repairPack(_ window: WindowModel, pack: String) {
        let store = window.store
        Task {
            do {
                try await store.repairPackIndex(pack)
                window.toasts.show(Toast(message: String(localized: "Rebuilt the index for \(pack)", bundle: .module), detail: String(localized: "Verify integrity again to confirm.", bundle: .module), icon: "wrench.and.screwdriver"))
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "The pack index wasn't rebuilt", bundle: .module))
            }
        }
    }

    static func busyTitle(_ task: MaintenanceTask) -> String {
        switch task {
        case .gc, .gcAggressive, .gcPruneNow: String(localized: "Cleaning up\u{2026}", bundle: .module)
        case .fsck: String(localized: "Verifying integrity\u{2026}", bundle: .module)
        case .prune, .prunePacked: String(localized: "Pruning unreachable objects\u{2026}", bundle: .module)
        case .repack: String(localized: "Repacking\u{2026}", bundle: .module)
        case .commitGraph: String(localized: "Writing the commit graph\u{2026}", bundle: .module)
        case .backfill: String(localized: "Downloading missing files\u{2026}", bundle: .module)
        case .packRefs: String(localized: "Packing refs\u{2026}", bundle: .module)
        case .multiPackIndex: String(localized: "Writing the multi-pack index\u{2026}", bundle: .module)
        }
    }

    static func doneTitle(_ task: MaintenanceTask) -> String {
        switch task {
        case .gc, .gcAggressive, .gcPruneNow: String(localized: "Cleaned up the repository", bundle: .module)
        case .fsck: String(localized: "No problems found", bundle: .module)
        case .prune, .prunePacked: String(localized: "Pruned unreachable objects", bundle: .module)
        case .repack: String(localized: "Repacked the repository", bundle: .module)
        case .commitGraph: String(localized: "Wrote the commit graph", bundle: .module)
        case .backfill: String(localized: "Downloaded the missing files", bundle: .module)
        case .packRefs: String(localized: "Packed refs", bundle: .module)
        case .multiPackIndex: String(localized: "Wrote the multi-pack index", bundle: .module)
        }
    }

    static func icon(_ task: MaintenanceTask) -> String {
        switch task {
        case .prune, .prunePacked: "trash"
        case .repack: "archivebox"
        case .commitGraph: "point.3.connected.trianglepath.dotted"
        case .fsck: "stethoscope"
        case .backfill: "arrow.down.to.line"
        default: "wrench.and.screwdriver"
        }
    }

    static func detail(_ result: MaintenanceResult) -> String {
        let saved = result.before - result.after
        var parts: [String] = []
        parts.append(String(localized: "\(LongTailReveal.bytes(result.after)) in \(n(result.packsAfter, "pack"))", bundle: .module))
        if result.looseAfter > 0 { parts.append(String(localized: "\(n(result.looseAfter, "loose object"))", bundle: .module)) }
        if saved > 0 { parts.append(String(localized: "saved \(LongTailReveal.bytes(saved))", bundle: .module)) }
        if result.task == .prune, result.after == result.before {
            return String(localized: "Objects younger than 2 weeks were kept.", bundle: .module)
        }
        return parts.joined(separator: ", ") + "."
    }

    static func desktop() -> URL {
        AppSheets.app?.desktopFolder ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop", directoryHint: .isDirectory)
    }

    static func downloads() -> URL {
        AppSheets.app?.downloadsFolder ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads", directoryHint: .isDirectory)
    }
}
