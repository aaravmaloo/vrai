import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers
import VraiCore
import VraiGit

public struct ChangesPick: Hashable, Sendable {
    public var path: String
    public var side: LineSelection.Side
    public var conflict = false

    public init(path: String, side: LineSelection.Side, conflict: Bool = false) {
        self.path = path
        self.side = side
        self.conflict = conflict
    }
}

public struct CommitHookFailure: Hashable, Sendable {
    public var name: String
    public var output: String
}

struct ChangeGroups {
    enum Kind: String, CaseIterable {
        case conflicts
        case staged
        case unstaged
        case untracked
    }

    var conflicts: [WorkingFile] = []
    var staged: [WorkingFile] = []
    var unstaged: [WorkingFile] = []
    var untracked: [WorkingFile] = []

    init(_ working: [WorkingFile]) {
        for file in working {
            if file.status == .conflicted {
                conflicts.append(file)
                continue
            }
            if Self.isStaged(file) { staged.append(file) }
            if file.status == .untracked {
                untracked.append(file)
            } else if Self.hasUnstaged(file) {
                unstaged.append(file)
            }
        }
    }

    static func isStaged(_ file: WorkingFile) -> Bool {
        file.status != .conflicted && file.staged != .none
    }

    static func hasUnstaged(_ file: WorkingFile) -> Bool {
        file.status != .conflicted && (file.status == .untracked || file.worktreeStatus != nil || file.staged == .none)
    }

    func files(_ kind: Kind) -> [WorkingFile] {
        switch kind {
        case .conflicts: conflicts
        case .staged: staged
        case .unstaged: unstaged
        case .untracked: untracked
        }
    }

    static func side(of kind: Kind) -> LineSelection.Side {
        kind == .staged ? .staged : .unstaged
    }

    var picks: [ChangesPick] {
        conflicts.map { ChangesPick(path: $0.path, side: .unstaged, conflict: true) }
            + staged.map { ChangesPick(path: $0.path, side: .staged) }
            + unstaged.map { ChangesPick(path: $0.path, side: .unstaged) }
            + untracked.map { ChangesPick(path: $0.path, side: .unstaged) }
    }

    var isEmpty: Bool { conflicts.isEmpty && staged.isEmpty && unstaged.isEmpty && untracked.isEmpty }

    var changedFiles: Int {
        Set((staged + unstaged + untracked).map(\.path)).count
    }

    static func resolve(_ pick: ChangesPick?, in working: [WorkingFile]) -> ChangesPick? {
        let groups = ChangeGroups(working)
        if let pick, pick.conflict, working.first(where: { $0.path == pick.path })?.status != .conflicted, let next = groups.conflicts.first {
            return ChangesPick(path: next.path, side: .unstaged, conflict: true)
        }
        if let pick, let file = working.first(where: { $0.path == pick.path }) {
            if file.status == .conflicted { return ChangesPick(path: file.path, side: .unstaged, conflict: true) }
            switch pick.side {
            case .staged:
                if isStaged(file) { return ChangesPick(path: file.path, side: .staged) }
                return ChangesPick(path: file.path, side: .unstaged)
            case .unstaged:
                if hasUnstaged(file) { return ChangesPick(path: file.path, side: .unstaged) }
                return ChangesPick(path: file.path, side: .staged)
            }
        }
        return groups.picks.first
    }

    static func statusLetter(_ file: WorkingFile, side: LineSelection.Side) -> FileStatus {
        switch side {
        case .staged:
            if file.status == .renamed || file.status == .copied { return file.status }
            return file.indexStatus ?? file.status
        case .unstaged:
            if file.status == .untracked { return .untracked }
            return file.worktreeStatus ?? file.status
        }
    }
}

enum FilePicks {
    static func range(from start: ChangesPick, to end: ChangesPick, in order: [ChangesPick]) -> [ChangesPick] {
        guard let first = order.firstIndex(of: start), let last = order.firstIndex(of: end) else { return [end] }
        return Array(order[min(first, last)...max(first, last)])
    }

    static func toggled(_ target: ChangesPick, in selected: Set<ChangesPick>) -> Set<ChangesPick> {
        var next = selected
        if next.contains(target) {
            if next.count > 1 { next.remove(target) }
        } else {
            next.insert(target)
        }
        return next
    }

    static func resolve(_ selected: Set<ChangesPick>, in working: [WorkingFile]) -> Set<ChangesPick> {
        Set(selected.compactMap { pick in
            guard let next = ChangeGroups.resolve(pick, in: working), next.path == pick.path else { return nil }
            return next
        })
    }

    static func ordered(_ selected: Set<ChangesPick>, in order: [ChangesPick]) -> [ChangesPick] {
        order.filter { selected.contains($0) }
    }
}

struct SideCounts: Hashable {
    var unstaged: Int
    var staged: Int
}

enum DiffBody: Hashable {
    case lines
    case large(lines: Int)
    case binary(detail: String?)
    case empty
}

@MainActor
@Observable
public final class ChangesModel {
    public var subject = ""
    public var body = ""
    public internal(set) var amend = false
    public var signoff = false
    public var noVerify = false
    public internal(set) var pick: ChangesPick?
    public internal(set) var selected: Set<ChangesPick> = []
    @ObservationIgnored var anchor: ChangesPick?
    public internal(set) var diff: FileDiff?
    public internal(set) var diffState: LoadState = .idle
    public internal(set) var hookFailure: CommitHookFailure?
    public internal(set) var latestUndo: UndoEntry?
    public internal(set) var committing = false
    var lines: LineSelection?
    var counts: SideCounts?
    var focusRequest = 0
    @ObservationIgnored var focusHandled = 0
    var narrowDetail = false
    var listFocusRequest = 0
    var diffFocusRequest = 0
    var fileBytes: Int?

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored private var listening = false
    @ObservationIgnored private var mergeMessageFor: String?

    public static let largeLines = 20_000
    public static let largeBytes = 2 * 1024 * 1024

    public init() {}

    public var selectedConflict: String? {
        guard let pick, pick.conflict else { return nil }
        return pick.path
    }

    public func prefill(subject: String, body: String = "") {
        self.subject = subject
        self.body = body
    }

    var isLineLevel: Bool {
        guard let diff, case .lines = bodyKind else { return false }
        return diff.status == .modified && !diff.isBinary && !diff.isSubmodule && PatchBuilder.canBuild(for: diff)
    }

    var bodyKind: DiffBody {
        guard let diff else { return .empty }
        if diff.isBinary { return .binary(detail: binaryDetail) }
        let total = diff.hunks.reduce(0) { $0 + $1.lines.count }
        if total > Self.largeLines || (fileBytes ?? 0) > Self.largeBytes { return .large(lines: diff.additions + diff.deletions) }
        if diff.hunks.isEmpty { return .empty }
        return .lines
    }

    var binaryDetail: String? {
        guard let pick else { return nil }
        let ext = (pick.path as NSString).pathExtension
        let kind = UTType(filenameExtension: ext)?.localizedDescription
        let size = fileBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
        let parts = [kind, size].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    var isMultiple: Bool { selected.count > 1 }

    func isSelected(_ candidate: ChangesPick) -> Bool {
        isMultiple ? selected.contains(candidate) : pick == candidate
    }

    func select(_ next: ChangesPick, store: RepositoryStore, narrow: Bool) {
        if narrow { narrowDetail = true }
        listFocusRequest += 1
        selected = [next]
        anchor = next
        guard next != pick else { return }
        pick = next
        lines = nil
        reload(store, quiet: false)
    }

    func extend(to target: ChangesPick, order: [ChangesPick], store: RepositoryStore) {
        listFocusRequest += 1
        let start = anchor ?? pick ?? target
        anchor = start
        selected = Set(FilePicks.range(from: start, to: target, in: order))
        focus(target, store: store)
    }

    func toggle(_ target: ChangesPick, order: [ChangesPick], store: RepositoryStore) {
        listFocusRequest += 1
        let current = isMultiple ? selected : Set(pick.map { [$0] } ?? [])
        selected = FilePicks.toggled(target, in: current)
        anchor = target
        focus(selected.contains(target) ? target : FilePicks.ordered(selected, in: order).first ?? target, store: store)
    }

    func drag(from start: ChangesPick, to target: ChangesPick, order: [ChangesPick], keeping base: Set<ChangesPick>, store: RepositoryStore) {
        selected = base.union(FilePicks.range(from: start, to: target, in: order))
        anchor = start
        focus(target, store: store)
    }

    private func focus(_ target: ChangesPick, store: RepositoryStore) {
        guard target != pick else { return }
        pick = target
        lines = nil
        reload(store, quiet: false)
    }

    func sync(_ store: RepositoryStore) {
        let working = store.snapshot?.working ?? []
        let resolved = ChangeGroups.resolve(pick, in: working)
        let kept = FilePicks.resolve(selected, in: working)
        selected = kept.count > 1 ? kept : Set(resolved.map { [$0] } ?? [])
        if let current = anchor { anchor = FilePicks.resolve([current], in: working).first ?? resolved }
        if resolved != pick {
            let samePath = resolved?.path == pick?.path
            pick = resolved
            lines = nil
            reload(store, quiet: samePath)
        } else {
            reload(store, quiet: true)
        }
        prefillMerge(store)
    }

    func reload(_ store: RepositoryStore, quiet: Bool) {
        loadTask?.cancel()
        guard let pick, !pick.conflict else {
            diff = nil
            counts = nil
            diffState = .idle
            return
        }
        if !quiet || diff?.path != pick.path {
            diff = nil
            counts = nil
            diffState = .loading
        }
        let file = store.snapshot?.working.first { $0.path == pick.path }
        let root = store.snapshot?.root
        loadTask = Task { [weak self] in
            do {
                let loaded = try await store.workingDiff(path: pick.path, staged: pick.side == .staged)
                var counts: SideCounts?
                if let file, ChangeGroups.isStaged(file), ChangeGroups.hasUnstaged(file), file.status != .untracked {
                    let other = try await store.workingDiff(path: pick.path, staged: pick.side != .staged)
                    let mine = (loaded?.additions ?? 0) + (loaded?.deletions ?? 0)
                    let theirs = (other?.additions ?? 0) + (other?.deletions ?? 0)
                    counts = pick.side == .staged ? SideCounts(unstaged: theirs, staged: mine) : SideCounts(unstaged: mine, staged: theirs)
                }
                let bytes = root.flatMap { Self.size(of: $0.appending(path: pick.path)) }
                guard let self, !Task.isCancelled, self.pick == pick else { return }
                if loaded != self.diff { self.lines = nil }
                self.diff = loaded
                self.counts = counts
                self.fileBytes = bytes
                self.diffState = .loaded
            } catch {
                guard let self, !Task.isCancelled, self.pick == pick else { return }
                self.diffState = .failed(error as? GitError ?? GitError(.unknown(exit: -1, stderr: String(describing: error))))
            }
        }
    }

    nonisolated static func size(of url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? NSNumber)?.intValue
    }

    func listen(_ store: RepositoryStore) {
        guard !listening else { return }
        listening = true
        reloadUndo(store)
        undoTask = Task { [weak self] in
            for await event in store.events {
                guard let self else { return }
                switch event {
                case .operationFinished, .changedOutside:
                    self.reloadUndo(store)
                default:
                    break
                }
            }
        }
    }

    func reloadUndo(_ store: RepositoryStore) {
        Task { [weak self] in
            let latest = try? await store.undoHistory(limit: 1).first
            self?.latestUndo = latest
        }
    }

    func resetComposer() {
        subject = ""
        body = ""
        amend = false
        hookFailure = nil
        mergeMessageFor = nil
    }

    func setAmend(_ on: Bool, store: RepositoryStore) {
        hookFailure = nil
        guard on else {
            amend = false
            subject = ""
            body = ""
            return
        }
        amend = true
        Task { [weak self] in
            guard let message = try? await store.lastCommitMessage() else { return }
            guard let self, self.amend else { return }
            self.subject = message.subject
            self.body = message.body
        }
    }

    private func prefillMerge(_ store: RepositoryStore) {
        guard let snapshot = store.snapshot, case .merging = snapshot.state else {
            mergeMessageFor = nil
            return
        }
        let key = snapshot.headOID?.rawValue ?? ""
        guard mergeMessageFor != key, subject.isEmpty, !amend else { return }
        mergeMessageFor = key
        guard let text = try? String(contentsOf: snapshot.gitDir.appending(path: "MERGE_MSG"), encoding: .utf8) else { return }
        Task { [weak self] in
            let cleaned = await store.cleanMessage(text)
            guard let self, self.mergeMessageFor == key, self.subject.isEmpty, self.body.isEmpty, !self.amend else { return }
            let message = CommitMessage(text: cleaned)
            self.subject = message.subject
            self.body = message.body
        }
    }

    func present(_ diff: FileDiff, for pick: ChangesPick) {
        loadTask?.cancel()
        self.pick = pick
        selected = [pick]
        anchor = pick
        self.diff = diff
        lines = nil
        diffState = .loaded
    }

    func clearLines() {
        lines = nil
    }

    func click(_ id: LineID, extending: Bool, toggling: Bool) {
        guard let diff, isLineLevel, let pick else { return }
        var selection = lines ?? LineSelection(file: diff, side: pick.side)
        selection.click(id, extending: extending, toggling: toggling)
        lines = selection.isEmpty ? nil : selection
    }

    func drag(from start: LineID, to end: LineID, keeping base: Set<LineID>) {
        guard let diff, isLineLevel, let pick else { return }
        var selection = lines ?? LineSelection(file: diff, side: pick.side)
        selection.drag(from: start, to: end, keeping: base)
        lines = selection.isEmpty ? nil : selection
    }
}
