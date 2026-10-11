import Foundation
import SwiftUI
import VraiCore
import VraiGit

enum ChangesTiming {
    static let lineToast: TimeInterval = Toast.brief + 0.4
}

enum ChangesCopy {
    static let keptCopy = String(localized: "A copy stays in Undo history for 14 days.", bundle: .module)

    static func them(_ count: Int) -> String {
        count == 1 ? String(localized: "it", bundle: .module) : String(localized: "them", bundle: .module)
    }

    static func discardTitle(_ paths: [String]) -> String {
        paths.count == 1
            ? String(localized: "Discard changes to \(PathParts.split(paths[0]).name)?", bundle: .module)
            : String(localized: "Discard changes to \(n(paths.count, "file"))?", bundle: .module)
    }

    static func discardMessage(tracked: Int, lines: Int, untracked: Int) -> String {
        var parts: [String] = []
        if tracked > 0 {
            if lines == 0 {
                parts.append(tracked == 1 ? String(localized: "It goes back to the last commit", bundle: .module) : String(localized: "They go back to the last commit", bundle: .module))
            } else if lines == 1 {
                parts.append(String(localized: "1 changed line goes back to the last commit", bundle: .module))
            } else {
                parts.append(String(localized: "\(n(lines, "changed line")) go back to the last commit", bundle: .module))
            }
        }
        if untracked == 1 {
            parts.append(tracked > 0 ? String(localized: "1 untracked file is deleted", bundle: .module) : String(localized: "It's untracked, so the file is deleted", bundle: .module))
        } else if untracked > 1 {
            parts.append(String(localized: "\(n(untracked, "untracked file")) are deleted", bundle: .module))
        }
        return parts.joined(separator: String(localized: ", and ", bundle: .module)) + ". " + keptCopy
    }

    static func pathList(_ paths: [String]) -> String {
        let shown = paths.prefix(4).map { PathParts.split($0).name }
        var text = shown.joined(separator: "\n")
        if paths.count > shown.count { text += "\n" + String(localized: "and \(n(paths.count - shown.count, "more file"))", bundle: .module) }
        return text
    }

    static func cleanTitle(_ paths: [String]) -> String {
        paths.count == 1
            ? String(localized: "Delete \(PathParts.split(paths[0]).name)?", bundle: .module)
            : String(localized: "Delete \(n(paths.count, "untracked file"))?", bundle: .module)
    }

    static func cleanMessage(_ count: Int) -> String {
        String(localized: "Git doesn't track \(them(count)), so no commit has a copy. Undo history keeps one for 14 days.", bundle: .module)
    }

    static func undoMenuTitle(_ entry: UndoEntry?) -> String {
        guard let label = entry?.label, let first = label.first else { return String(localized: "Undo", bundle: .module) }
        return String(localized: "Undo \(first.lowercased() + label.dropFirst())", bundle: .module)
    }

    static func restoredDetail(short: String, inChanges: Bool, lines: Int) -> String {
        if !inChanges { return String(localized: "It matches \(short) again.", bundle: .module) }
        if lines > 0 { return String(localized: "\(n(lines, "changed line")) in Changes, ready to review.", bundle: .module) }
        return String(localized: "It's in Changes, ready to review.", bundle: .module)
    }
}

extension String {
    var trimmedForCommit: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension WindowModel {
    public func undoLast() {
        Task { await performUndoLast() }
    }

    public func restoreUndo(_ entry: UndoEntry) {
        Task {
            do {
                try await store.restore(entry)
                changes.clearLines()
                toasts.show(Toast(message: String(localized: "Undid: \(entry.label)", bundle: .module), icon: "arrow.uturn.backward"))
            } catch {
                presentChangesError(error)
            }
            changes.reloadUndo(store)
        }
    }

    public func showUndoHistory() {
        sheets.present { UndoHistorySheet() }
    }

    public func undoToastAction() -> @MainActor () -> Void {
        { [weak self] in self?.undoLast() }
    }

    func performUndoLast() async {
        do {
            if let entry = try await store.undoLast() {
                changes.clearLines()
                toasts.show(Toast(message: String(localized: "Undid: \(entry.label)", bundle: .module), icon: "arrow.uturn.backward"))
            } else {
                toasts.show(Toast(message: String(localized: "Nothing to undo", bundle: .module), detail: String(localized: "Edit, Undo history lists older changes you can restore.", bundle: .module)))
            }
        } catch {
            presentChangesError(error)
        }
        changes.reloadUndo(store)
    }

    func presentChangesError(_ error: Error) {
        let gitError = error as? GitError ?? GitError(.unknown(exit: -1, stderr: String(describing: error)))
        if case .cancelled = gitError.code { return }
        if case .patchDoesNotApply = gitError.code { changes.reload(store, quiet: false) }
        alerts.present(gitError)
    }

    func runChange(_ body: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await body()
            } catch {
                presentChangesError(error)
            }
        }
    }

    var changeGroups: ChangeGroups { ChangeGroups(store.snapshot?.working ?? []) }

    func toggleStage(_ file: WorkingFile) {
        if file.staged == .full { unstageFiles([file.path]) } else { stageFiles([file.path]) }
    }

    func stageFiles(_ paths: [String]) {
        runChange { [store] in try await store.stage(paths: paths) }
    }

    func unstageFiles(_ paths: [String]) {
        runChange { [store] in try await store.unstage(paths: paths) }
    }

    func stageEverything(includeUntracked: Bool) {
        runChange { [store] in try await store.stageAll(includeUntracked: includeUntracked) }
    }

    func unstageEverything() {
        runChange { [store] in try await store.unstageAll() }
    }

    func toggleStageAll(includeUntracked: Bool) {
        let groups = changeGroups
        let files = groups.staged + groups.unstaged + groups.untracked
        let allStaged = !files.isEmpty && files.allSatisfy { $0.staged == .full }
        if allStaged { unstageEverything() } else { stageEverything(includeUntracked: includeUntracked) }
    }

    func applyLines(_ action: StagingService.LineAction, selection: LineSelection, what: String? = nil, announce: Bool = true) {
        guard !selection.isEmpty else { return }
        let name = PathParts.split(selection.path).name
        let count = selection.count
        changes.clearLines()
        runChange { [weak self, store] in
            switch action {
            case .stage:
                try await store.stage(lines: selection)
                if announce { self?.toasts.show(Toast(message: String(localized: "Staged \(n(count, "line"))", bundle: .module), detail: name, timeout: ChangesTiming.lineToast)) }
            case .unstage:
                try await store.unstage(lines: selection)
                if announce { self?.toasts.show(Toast(message: String(localized: "Unstaged \(n(count, "line"))", bundle: .module), detail: name, timeout: ChangesTiming.lineToast)) }
            case .discard:
                try await store.discard(lines: selection)
                guard let self else { return }
                self.toasts.show(Toast(message: String(localized: "Discarded \(what ?? n(count, "line"))", bundle: .module), detail: name, icon: "arrow.uturn.backward", action: String(localized: "Undo", bundle: .module), onAction: self.undoToastAction()))
            }
        }
    }

    func applySelectedLines(_ action: StagingService.LineAction, hunk: Int? = nil) {
        guard var selection = changes.lines, !selection.isEmpty else { return }
        if let hunk { selection = selection.limited(toHunk: hunk) }
        applyLines(action, selection: selection)
    }

    func hunkAction(_ action: StagingService.LineAction, hunk index: Int) {
        guard let diff = changes.diff, let pick = changes.pick else { return }
        if changes.isLineLevel {
            let selection = LineSelection.hunk(index, in: diff, side: pick.side)
            applyLines(action, selection: selection, what: action == .discard ? String(localized: "a hunk", bundle: .module) : nil)
            return
        }
        switch action {
        case .stage: stageFiles([pick.path])
        case .unstage: unstageFiles([pick.path])
        case .discard: discardFiles([pick.path], hunk: true)
        }
    }

    func toggleSelectionStaging() {
        if let selection = changes.lines, !selection.isEmpty {
            applyLines(selection.side == .staged ? .unstage : .stage, selection: selection)
            return
        }
        guard let pick = changes.pick, !pick.conflict, let file = store.snapshot?.working.first(where: { $0.path == pick.path }) else { return }
        toggleStage(file)
    }

    func confirmDiscard(_ paths: [String]) {
        let working = store.snapshot?.working ?? []
        let files = paths.compactMap { path in working.first { $0.path == path && $0.status != .conflicted } }
        guard !files.isEmpty else { return }
        let untracked = files.filter { $0.status == .untracked }
        let tracked = files.filter { $0.status != .untracked }
        let lines = tracked.reduce(0) { $0 + $1.additions + $1.deletions }
        let shown = files.map(\.path)
        var message = ChangesCopy.discardMessage(tracked: tracked.count, lines: lines, untracked: untracked.count)
        if shown.count > 1 { message += "\n\n" + ChangesCopy.pathList(shown) }
        let label = shown.count == 1 ? String(localized: "Discard changes", bundle: .module) : String(localized: "Discard \(n(shown.count, "file"))", bundle: .module)
        alerts.present(AlertRequest(title: ChangesCopy.discardTitle(shown), message: message, actions: [
            AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel),
            AlertAction(title: label, role: .destructive) { [weak self] in self?.discardFiles(shown) }
        ]))
    }

    func confirmClean() {
        let paths = changeGroups.untracked.map(\.path)
        guard !paths.isEmpty else { return }
        let label = paths.count == 1 ? String(localized: "Delete file", bundle: .module) : String(localized: "Delete \(n(paths.count, "file"))", bundle: .module)
        alerts.present(AlertRequest(title: ChangesCopy.cleanTitle(paths), message: ChangesCopy.cleanMessage(paths.count) + "\n\n" + ChangesCopy.pathList(paths), actions: [
            AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel),
            AlertAction(title: label, role: .destructive) { [weak self] in self?.discardFiles(paths) }
        ]))
    }

    func confirmDiscardAll() {
        let groups = changeGroups
        let paths = (groups.staged + groups.unstaged + groups.untracked).map(\.path)
        var seen = Set<String>()
        confirmDiscard(paths.filter { seen.insert($0).inserted })
    }

    func discardFiles(_ paths: [String], hunk: Bool = false) {
        let working = store.snapshot?.working ?? []
        let files = paths.compactMap { path in working.first { $0.path == path } }
        let staged = files.filter { $0.staged != .none }.map(\.path)
        var targets = paths
        for file in files {
            if let old = file.oldPath, !targets.contains(old) { targets.append(old) }
        }
        let name = paths.count == 1 ? PathParts.split(paths[0]).name : n(paths.count, "file")
        runChange { [weak self, store] in
            if !staged.isEmpty { try await store.unstage(paths: staged) }
            try await store.discard(paths: targets)
            guard let self else { return }
            let message = hunk ? String(localized: "Discarded a hunk", bundle: .module) : String(localized: "Discarded changes to \(name)", bundle: .module)
            self.toasts.show(Toast(message: message, detail: hunk ? name : ChangesCopy.keptCopy, icon: "arrow.uturn.backward", action: String(localized: "Undo", bundle: .module), onAction: self.undoToastAction()))
        }
    }

    func confirmRestore(path: String, from id: OID) {
        let deletedThere = store.detail.map { $0.commit.id == id && $0.files.contains { $0.path == path && $0.status == .deleted } } ?? false
        let name = PathParts.split(path).name
        let short = id.short(expert: preferences.expert)
        let title = String(localized: "Restore \(name) from \(short)?", bundle: .module)
        let cancel = AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel)
        if deletedThere {
            alerts.present(AlertRequest(title: title, message: String(localized: "\(name) doesn't exist at \(short), so this deletes it from your working tree. A copy stays in Undo history for 14 days.", bundle: .module), actions: [
                cancel,
                AlertAction(title: String(localized: "Delete file", bundle: .module), role: .destructive) { [weak self] in self?.restoreFile(path: path, from: id) }
            ]))
            return
        }
        let dirty = store.snapshot?.working.contains { $0.path == path } ?? false
        let message = dirty
            ? String(localized: "This throws away your uncommitted changes to it. A copy stays in Undo history for 14 days.", bundle: .module)
            : String(localized: "This puts back the version from \(short). The result shows up in Changes for you to review.", bundle: .module)
        alerts.present(AlertRequest(title: title, message: message, actions: [
            cancel,
            AlertAction(title: String(localized: "Restore file", bundle: .module)) { [weak self] in self?.restoreFile(path: path, from: id) }
        ]))
    }

    func restoreFile(path: String, from id: OID) {
        let name = PathParts.split(path).name
        let short = id.short(expert: preferences.expert)
        runChange { [weak self, store] in
            try await store.restoreFile(path: path, from: id)
            guard let self else { return }
            let file = store.snapshot?.working.first { $0.path == path }
            let detail = ChangesCopy.restoredDetail(short: short, inChanges: file != nil, lines: (file?.additions ?? 0) + (file?.deletions ?? 0))
            self.toasts.show(Toast(message: String(localized: "Restored \(name) from \(short)", bundle: .module), detail: detail, icon: "arrow.counterclockwise", action: String(localized: "Undo", bundle: .module), onAction: self.undoToastAction()))
        }
    }

    func focusComposer() {
        show(.changes)
        changes.focusRequest += 1
    }

    func startAmend() {
        show(.changes)
        changes.setAmend(true, store: store)
        changes.focusRequest += 1
    }

    func commitFromMenu() {
        if store.view == .changes, !changes.subject.trimmedForCommit.isEmpty {
            commitNow(andPush: false)
        } else {
            focusComposer()
        }
    }

    var mergeSource: String? {
        if case .merging(let source) = store.snapshot?.state { return source ?? "" }
        return nil
    }

    var composerStaged: Int {
        let groups = changeGroups
        if mergeSource != nil { return groups.conflicts.isEmpty ? max(1, groups.staged.count) : 0 }
        return groups.staged.count
    }

    var canCommit: Bool {
        guard store.snapshot != nil else { return false }
        return composerStaged > 0 || changes.amend
    }

    func commitNow(andPush: Bool) {
        let model = changes
        guard !model.committing else { return }
        let subject = model.subject.trimmedForCommit
        guard !subject.isEmpty else {
            toasts.show(Toast(message: String(localized: "Write a summary to commit", bundle: .module), icon: "pencil"))
            focusComposer()
            return
        }
        let groups = changeGroups
        let merging = mergeSource
        if merging != nil, !groups.conflicts.isEmpty {
            let count = groups.conflicts.count
            let detail = count == 1 ? String(localized: "1 file still has conflicts.", bundle: .module) : String(localized: "\(n(count, "file")) still have conflicts.", bundle: .module)
            toasts.show(Toast(tone: .danger, message: String(localized: "Resolve every conflict first", bundle: .module), detail: detail))
            return
        }
        if merging == nil, groups.staged.isEmpty, !model.amend {
            toasts.show(Toast(message: String(localized: "Stage at least one file to commit", bundle: .module), detail: String(localized: "Check a file or press Space.", bundle: .module), icon: "checkmark.circle"))
            return
        }
        let amend = model.amend
        let head = headName
        model.committing = true
        model.hookFailure = nil
        Task { [weak self, store] in
            defer { model.committing = false }
            do {
                try await store.commit(subject: model.subject, body: model.body, amend: amend, signoff: model.signoff, noVerify: model.noVerify)
                guard let self else { return }
                let toast: Toast
                if let merging {
                    toast = Toast(message: String(localized: "Merged \(merging) into \(head)", bundle: .module), detail: subject, icon: "arrow.triangle.merge", action: String(localized: "Undo", bundle: .module), onAction: self.undoToastAction())
                } else {
                    let message = amend ? String(localized: "Amended the last commit on \(head)", bundle: .module) : String(localized: "Committed to \(head)", bundle: .module)
                    toast = Toast(message: message, detail: subject, icon: "checkmark.circle", action: String(localized: "Undo", bundle: .module), onAction: self.undoToastAction())
                }
                model.resetComposer()
                model.clearLines()
                self.toasts.show(toast)
                if andPush { await self.pushAfterCommit() }
            } catch let error as GitError {
                if case .hookFailed(let name, let output) = error.code, error.result?.command.subcommand == "commit" {
                    model.hookFailure = CommitHookFailure(name: name, output: output)
                    if let kept = error.commitMessage, model.subject.trimmedForCommit.isEmpty {
                        model.subject = kept.subject
                        model.body = kept.body
                    }
                    return
                }
                self?.presentChangesError(error)
            } catch {
                self?.presentChangesError(error)
            }
        }
    }

    func pushAfterCommit() async {
        do {
            let result = try await store.push()
            toasts.show(Toast(message: result.summary.message, detail: result.summary.detail, icon: "arrow.up.to.line"))
        } catch {
            presentChangesError(error)
        }
    }
}
