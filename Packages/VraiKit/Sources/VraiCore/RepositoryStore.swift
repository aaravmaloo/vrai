import Foundation
import Observation
import VraiGit

@MainActor
@Observable
public final class RepositoryStore {
    public let git: GitProcess
    public let undo: UndoStore
    public let console: ConsoleLog
    public internal(set) var snapshot: RepositorySnapshot?
    public private(set) var busy: Set<String> = []
    public var branchColors: BranchColors

    public private(set) var snapshotError: GitError?
    public private(set) var isOpening = false
    public private(set) var history = HistoryState()
    public private(set) var signatures: [OID: SignatureState] = [:]
    public private(set) var selection: CommitSelection?
    public private(set) var detail: CommitDetail?
    public private(set) var detailState: LoadState = .idle
    public private(set) var selectedPath: String?
    public private(set) var patch: FileDiff?
    public private(set) var patchState: LoadState = .idle
    public private(set) var diffParent = 0
    public private(set) var contextLines = RepositoryStore.defaultContext
    public private(set) var inspectorInfo: InspectorInfo?
    public private(set) var stateDetails = StateDetails()
    public private(set) var scrollRequest: ScrollRequest?
    public private(set) var openedCount: Int?
    public var view: RepositoryView = .history
    public var sidebarSelection: String?
    public var fileFocus: FileFocus?
    public var renameThreshold = 50
    public var pageSize = 2000
    public private(set) var scope: HistoryScope = .all

    public static let defaultContext = 3
    public static let contextStep = 20
    public static let wipID = OID(String(repeating: "0", count: 40))!

    @ObservationIgnored private var pager: HistoryPager?
    @ObservationIgnored private var historyGeneration = 0
    @ObservationIgnored private var historyKey: HistoryKey?
    @ObservationIgnored private var historyActive = false
    @ObservationIgnored private var loadingMore = false
    @ObservationIgnored private var detailTask: Task<Void, Never>?
    @ObservationIgnored private var patchTask: Task<Void, Never>?
    @ObservationIgnored private var inspectorTask: Task<Void, Never>?
    @ObservationIgnored private var signatureTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSignatures: Set<OID> = []
    @ObservationIgnored private var requestedSignatures: Set<OID> = []
    @ObservationIgnored private var subjects: [OID: String] = [:]
    @ObservationIgnored private var continuations: [UUID: AsyncStream<RepositoryEvent>.Continuation] = [:]
    @ObservationIgnored private var watcher: RepositoryWatcher?
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var scrollSequence = 0

    public init(git: GitProcess, colors: BranchColors = BranchColors(), console: ConsoleLog = ConsoleLog()) {
        self.git = git
        self.undo = UndoStore(git: git)
        self.console = console
        self.branchColors = colors
    }

    public func refresh() async throws {
        let built: RepositorySnapshot
        do {
            built = try await SnapshotBuilder(git: git, renameThreshold: renameThreshold).build(colors: branchColors, network: snapshot?.network ?? .unknown)
        } catch let error as GitError {
            snapshotError = error
            throw error
        }
        let previousState = snapshot?.state
        snapshot = built
        branchColors = built.branchColors
        snapshotError = nil
        if let previousState, previousState != built.state { emit(.stateChanged(built.state)) }
        guard historyActive else { return }
        await updateStateDetails(built)
        if historyKey != HistoryKey(built, scope: scope) {
            await reloadHistory()
        } else {
            refreshWipSelection()
        }
    }

    public func perform<T: Sendable>(_ action: String, refresh shouldRefresh: Bool = true, _ body: () async throws -> T) async throws -> T {
        busy.insert(action)
        defer { busy.remove(action) }
        do {
            let value = try await body()
            if shouldRefresh { try await refresh() }
            emit(.operationFinished(id: action, outcome: .succeeded))
            return value
        } catch {
            if shouldRefresh { try? await refresh() }
            emit(.operationFinished(id: action, outcome: .failed(error as? GitError ?? GitError(.unknown(exit: -1, stderr: String(describing: error))))))
            throw error
        }
    }

    public var events: AsyncStream<RepositoryEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: RepositoryEvent.self)
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations.removeValue(forKey: id) }
        }
        return stream
    }

    public func emit(_ event: RepositoryEvent) {
        for continuation in continuations.values { continuation.yield(event) }
    }

    public func open(watch: Bool = true) async {
        historyActive = true
        isOpening = true
        defer { isOpening = false }
        do {
            try await refresh()
        } catch {
            return
        }
        if history.phase == .idle { await reloadHistory() }
        if selection == nil { selectDefault() }
        if watch { startWatching() }
    }

    public func close() {
        stopWatching()
        detailTask?.cancel()
        patchTask?.cancel()
        inspectorTask?.cancel()
        signatureTask?.cancel()
        for continuation in continuations.values { continuation.finish() }
        continuations.removeAll()
    }

    public func setScope(_ scope: HistoryScope) {
        guard scope != self.scope else { return }
        self.scope = scope
        Task { await reloadHistory() }
    }

    public func reloadHistory() async {
        guard let snapshot else { return }
        historyActive = true
        historyGeneration += 1
        let generation = historyGeneration
        if let old = pager { await old.cancel() }
        let key = HistoryKey(snapshot, scope: scope)
        let pager = HistoryPager(git: git, scope: scope, colors: snapshot.tipColors, head: snapshot.headOID, pageSize: pageSize, wip: wipCommit(for: snapshot))
        self.pager = pager
        loadingMore = false
        if history.phase != .loaded { history.phase = .loading }
        do {
            guard let page = try await pager.nextPage() else {
                guard generation == historyGeneration else { return }
                history = HistoryState(phase: .loaded, isComplete: true)
                historyKey = key
                return
            }
            guard generation == historyGeneration else { return }
            var next = HistoryState(phase: .loaded)
            next.append(page)
            next.wipRow = page.wipRow
            next.wipFiles = snapshot.working.count
            next.totalCount = page.isLast ? page.commits.count : nil
            history = next
            historyKey = key
            reconcileSelection()
            if !page.isLast { countHistory(generation: generation) }
        } catch let error as GitError {
            guard generation == historyGeneration else { return }
            if error.code == .cancelled { return }
            history.phase = .failed(error)
        } catch {
            guard generation == historyGeneration else { return }
            history.phase = .failed(GitError(.unknown(exit: -1, stderr: String(describing: error))))
        }
    }

    public func loadMoreHistory() async {
        guard !loadingMore, !history.isComplete, history.phase == .loaded, let pager else { return }
        loadingMore = true
        let generation = historyGeneration
        defer { if generation == historyGeneration { loadingMore = false } }
        do {
            guard let page = try await pager.nextPage() else {
                if generation == historyGeneration { history.isComplete = true }
                return
            }
            guard generation == historyGeneration else { return }
            history.append(page)
        } catch {
            return
        }
    }

    private func countHistory(generation: Int) {
        let arguments = ["rev-list", "--count"] + scope.arguments + ["--"]
        Task {
            guard let result = try? await git.run(.read(arguments), background: true) else { return }
            guard generation == historyGeneration, let count = Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            history.totalCount = count
        }
    }

    private func wipCommit(for snapshot: RepositorySnapshot) -> LayoutCommit? {
        guard !snapshot.working.isEmpty || !snapshot.conflicts.isEmpty, let head = snapshot.headOID else { return nil }
        switch scope {
        case .all, .current:
            break
        case .ref(let name):
            guard resolve(name) == head else { return nil }
        }
        return LayoutCommit(id: Self.wipID, parents: [head], color: headColor(snapshot))
    }

    public func headColor(_ snapshot: RepositorySnapshot) -> Int? {
        if let name = snapshot.head.branchName, let color = snapshot.branchColors.color(for: name) { return color }
        guard let head = snapshot.headOID else { return nil }
        return snapshot.tipColors[head]
    }

    public func requestSignatures(for ids: [OID]) {
        let fresh = ids.filter { !requestedSignatures.contains($0) && $0 != Self.wipID }
        guard !fresh.isEmpty else { return }
        requestedSignatures.formUnion(fresh)
        pendingSignatures.formUnion(fresh)
        guard signatureTask == nil else { return }
        signatureTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            await self?.flushSignatures()
        }
    }

    private func flushSignatures() async {
        while !pendingSignatures.isEmpty {
            let batch = Array(pendingSignatures.prefix(64))
            pendingSignatures.subtract(batch)
            let command = GitCommand.read(["log", "--no-walk=unsorted", "-z", "--format=" + LogParser.signatureFormat] + batch.map(\.rawValue) + ["--"])
            if let data = try? await git.run(command, background: true).stdout {
                for (id, state) in LogParser.signatures(data) { signatures[id] = state }
            }
        }
        signatureTask = nil
    }

    public func signature(of commit: Commit) -> SignatureState {
        signatures[commit.id] ?? commit.signature
    }

    public func select(_ selection: CommitSelection?, scroll: Bool = false) {
        if scroll, let selection { requestScroll(to: selection) }
        guard selection != self.selection else { return }
        self.selection = selection
        detailTask?.cancel()
        patchTask?.cancel()
        inspectorTask?.cancel()
        selectedPath = nil
        patch = nil
        patchState = .idle
        diffParent = 0
        contextLines = Self.defaultContext
        inspectorInfo = nil
        switch selection {
        case .commit(let id):
            if detail?.commit.id != id { detail = nil }
            detailState = .loading
            detailTask = Task { [weak self] in await self?.loadDetail(id) }
            inspectorTask = Task { [weak self] in await self?.loadInspector(id) }
        case .wip:
            detail = nil
            detailState = .loaded
            if let first = wipFiles.first { selectFile(first.path) }
        case nil:
            detail = nil
            detailState = .idle
        }
    }

    public func selectCommit(_ id: OID, scroll: Bool = false) {
        select(.commit(id), scroll: scroll)
    }

    public func showRef(_ name: String) {
        view = .history
        guard let id = resolve(name) else { return }
        if scope != .all, history.index[id] == nil { setScope(.all) }
        select(.commit(id), scroll: true)
        if history.index[id] == nil { Task { await loadUntilFound(id) } }
    }

    private func loadUntilFound(_ id: OID) async {
        var rounds = 0
        while history.index[id] == nil, !history.isComplete, rounds < 50 {
            rounds += 1
            await loadMoreHistory()
        }
        if history.index[id] != nil { requestScroll(to: .commit(id)) }
    }

    private func requestScroll(to selection: CommitSelection) {
        scrollSequence += 1
        scrollRequest = ScrollRequest(target: selection, sequence: scrollSequence)
    }

    public func resolve(_ name: String) -> OID? {
        guard let snapshot else { return nil }
        if name == "HEAD" { return snapshot.headOID }
        if let branch = snapshot.branches.first(where: { $0.name == name }) { return branch.tip }
        if let remote = snapshot.remoteBranches.first(where: { $0.fullName == name }) { return remote.tip }
        if let tag = snapshot.tags.first(where: { $0.name == name }) { return tag.target }
        return OID(name)
    }

    private func selectDefault() {
        guard let snapshot else { return }
        if case .bisecting(_, _, let current?, _) = snapshot.state {
            select(.commit(current), scroll: true)
        } else if let head = snapshot.headOID, snapshot.state.selectsHead {
            select(.commit(head), scroll: true)
        } else if history.wipRow != nil {
            select(.wip, scroll: true)
        } else if let head = snapshot.headOID {
            select(.commit(head), scroll: true)
        } else if !snapshot.working.isEmpty {
            select(.wip)
        }
    }

    private func reconcileSelection() {
        switch selection {
        case .wip:
            if history.wipRow == nil, snapshot?.headOID != nil {
                selection = nil
                selectDefault()
            } else {
                refreshWipSelection()
            }
        case .commit(let id):
            if history.index[id] == nil, resolveExists(id) == false {
                selection = nil
                selectDefault()
            }
        case nil:
            selectDefault()
        }
    }

    private func resolveExists(_ id: OID) -> Bool {
        detail?.commit.id == id
    }

    public var wipFiles: [WorkingFile] {
        guard let snapshot else { return [] }
        return snapshot.working.filter { $0.status != .conflicted }
    }

    private func refreshWipSelection() {
        history.wipFiles = snapshot?.working.count ?? 0
        guard selection == .wip else { return }
        let files = wipFiles
        if let path = selectedPath, let file = files.first(where: { $0.path == path }) {
            loadPatch(for: .wip, path: file.path, quiet: true)
        } else if let first = files.first {
            selectFile(first.path)
        } else {
            selectedPath = nil
            patch = nil
            patchState = .idle
        }
    }

    private func loadDetail(_ id: OID) async {
        do {
            let loaded = try await commitDetail(id: id)
            guard selection == .commit(id), !Task.isCancelled else { return }
            detail = loaded
            detailState = .loaded
            if let first = loaded.files.first { selectFile(first.path) }
        } catch {
            guard selection == .commit(id), !Task.isCancelled else { return }
            detailState = .failed(error as? GitError ?? GitError(.refNotFound))
        }
    }

    private func loadInspector(_ id: OID) async {
        async let describe = try? self.describe(id: id)
        async let branches = try? self.branchesContaining(id: id)
        let info = InspectorInfo(id: id, describe: await describe, branches: await branches ?? [])
        guard selection == .commit(id), !Task.isCancelled else { return }
        inspectorInfo = info
    }

    public func selectFile(_ path: String) {
        guard let selection else { return }
        if selectedPath != path { contextLines = Self.defaultContext }
        selectedPath = path
        loadPatch(for: selection, path: path, quiet: false)
    }

    public func selectParent(_ index: Int) {
        guard case .commit(let id)? = selection, let current = detail, current.commit.id == id, current.commit.parents.indices.contains(index), index != diffParent else { return }
        diffParent = index
        detailTask?.cancel()
        detailState = .loading
        detailTask = Task { [weak self] in
            guard let self else { return }
            do {
                let files = index == 0 ? try await self.commitDetail(id: id).files : try await self.changedFiles(from: current.commit.parents[index], to: id)
                guard self.selection == .commit(id), self.diffParent == index else { return }
                var updated = current
                updated.files = files
                self.detail = updated
                self.detailState = .loaded
                let path = files.first(where: { $0.path == self.selectedPath })?.path ?? files.first?.path
                if let path { self.selectFile(path) } else {
                    self.selectedPath = nil
                    self.patch = nil
                }
            } catch {
                guard self.selection == .commit(id) else { return }
                self.detailState = .failed(error as? GitError ?? GitError(.refNotFound))
            }
        }
    }

    public func showMoreContext() {
        guard let selection, let path = selectedPath else { return }
        contextLines += Self.contextStep
        loadPatch(for: selection, path: path, quiet: true)
    }

    private func loadPatch(for selection: CommitSelection, path: String, quiet: Bool) {
        patchTask?.cancel()
        if !quiet || patch?.path != path {
            patch = nil
            patchState = .loading
        }
        let context = contextLines
        patchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded: FileDiff?
                switch selection {
                case .commit(let id):
                    let file = self.detail?.files.first { $0.path == path }
                    let parent = self.detail.flatMap { $0.commit.parents.indices.contains(self.diffParent) && self.diffParent > 0 ? $0.commit.parents[self.diffParent] : nil }
                    loaded = try await self.diff(for: path, in: id, oldPath: file?.oldPath, parent: parent, context: context)
                case .wip:
                    guard let file = self.snapshot?.working.first(where: { $0.path == path }) else {
                        loaded = nil
                        break
                    }
                    loaded = try await self.uncommittedDiff(file, context: context)
                }
                guard self.selection == selection, self.selectedPath == path, !Task.isCancelled else { return }
                self.patch = loaded
                self.patchState = .loaded
            } catch {
                guard self.selection == selection, self.selectedPath == path, !Task.isCancelled else { return }
                self.patchState = .failed(error as? GitError ?? GitError(.refNotFound))
            }
        }
    }

    public func commitDetail(id: OID) async throws -> CommitDetail {
        let data = try await git.run(LogParser.detailCommand(id, renameThreshold: renameThreshold), background: true).stdout
        guard let parsed = LogParser.detail(data) else { throw GitError(.refNotFound) }
        return parsed
    }

    public func changedFiles(from parent: OID, to id: OID) async throws -> [ChangedFile] {
        let data = try await git.run(.read(["diff", "-z", "--raw", "--numstat", "--no-ext-diff", "--find-renames=\(renameThreshold)%", parent.rawValue, id.rawValue, "--"]), background: true).stdout
        return LogParser.changedFiles(ParseSupportBridge.nulFields(data))
    }

    public func diff(for path: String, in id: OID, oldPath: String? = nil, parent: OID? = nil, context: Int = RepositoryStore.defaultContext) async throws -> FileDiff? {
        var paths = [path]
        if let oldPath, oldPath != path { paths.append(oldPath) }
        let common = ["--no-color", "--no-ext-diff", "--find-renames=\(renameThreshold)%", "-U\(context)"]
        let arguments: [String]
        if let parent {
            arguments = ["diff"] + common + [parent.rawValue, id.rawValue, "--"] + paths
        } else {
            arguments = ["show", "--format=", "--patch", "--diff-merges=first-parent"] + common + [id.rawValue, "--"] + paths
        }
        let data = try await git.run(.read(arguments), background: true).stdout
        let files = PatchParser.parse(data)
        return files.first { $0.path == path } ?? files.first
    }

    public func uncommittedDiff(_ file: WorkingFile, context: Int = RepositoryStore.defaultContext) async throws -> FileDiff? {
        let common = ["--no-color", "--no-ext-diff", "-U\(context)"]
        let arguments: [String]
        let unborn: Bool
        if case .unborn = snapshot?.head { unborn = true } else { unborn = false }
        if file.status == .untracked || (unborn && !file.isSubmodule) {
            arguments = ["diff", "--no-index"] + common + ["--", "/dev/null", file.path]
            let data = try await git.run(.read(arguments, acceptedExitCodes: [0, 1]), background: true).stdout
            guard var parsed = PatchParser.parse(data).first else { return nil }
            parsed.path = file.path
            parsed.oldPath = nil
            parsed.status = file.status == .untracked ? .untracked : .added
            return parsed
        }
        var paths = [file.path]
        if let old = file.oldPath, old != file.path { paths.append(old) }
        arguments = ["diff", "HEAD", "--find-renames=\(renameThreshold)%"] + common + ["--"] + paths
        let data = try await git.run(.read(arguments), background: true).stdout
        let files = PatchParser.parse(data)
        return files.first { $0.path == file.path } ?? files.first
    }

    public func describe(id: OID) async throws -> String {
        try await git.run(.read(["describe", "--tags", "--always", id.rawValue]), background: true).output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func branchesContaining(id: OID) async throws -> [String] {
        let output = try await git.run(.read(["for-each-ref", "--contains=" + id.rawValue, "--format=%(refname)", "refs/heads"]), background: true).output
        return output.split(separator: "\n").map { String($0.dropFirst("refs/heads/".count)) }
    }

    public func subject(of id: OID) async -> String? {
        if let cached = subjects[id] { return cached }
        if let index = history.index[id] {
            subjects[id] = history.commits[index].subject
            return history.commits[index].subject
        }
        guard let result = try? await git.run(.read(["show", "-s", "--format=%s", id.rawValue, "--"]), background: true) else { return nil }
        let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        subjects[id] = text
        return text
    }

    private func updateStateDetails(_ snapshot: RepositorySnapshot) async {
        var details = StateDetails()
        switch snapshot.state {
        case .detached:
            if let result = try? await git.runAllowingFailure(.read(["rev-parse", "--symbolic-full-name", "@{-1}"]), background: true), result.exitCode == 0 {
                let name = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if name.hasPrefix("refs/heads/") {
                    let branch = String(name.dropFirst("refs/heads/".count))
                    if snapshot.branches.contains(where: { $0.name == branch }) { details.previousBranch = branch }
                }
            }
        case .rebasing(_, _, let stopped, _, _, let onto):
            if let stopped { details.subject = await subject(of: stopped) }
            if let onto { details.ontoName = refName(for: onto, in: snapshot) ?? onto.short }
        case .cherryPicking(let id?), .reverting(let id?):
            details.subject = await subject(of: id)
        case .bisecting(let good, let bad, let current, _):
            if let current { details.subject = await subject(of: current) }
            details.bisect = await bisectProgress(good: good, bad: bad, gitDir: snapshot.gitDir)
            if let found = details.bisect?.found { details.foundSubject = await subject(of: found) }
        default:
            break
        }
        stateDetails = details
    }

    private func bisectProgress(good: [OID], bad: OID?, gitDir: URL) async -> BisectProgress {
        var progress = BisectProgress()
        let log = (try? String(contentsOf: gitDir.appending(path: "BISECT_LOG"), encoding: .utf8)) ?? ""
        for line in log.split(separator: "\n") {
            if line.firstMatch(of: /^git bisect (good|bad|skip|old|new)\b/) != nil { progress.done += 1 }
            if let match = line.firstMatch(of: /^# first bad commit: \[([0-9a-f]{40,64})\]/) { progress.found = OID(String(match.output.1)) }
        }
        guard let bad, !good.isEmpty, progress.found == nil else { return progress }
        let command = GitCommand.read(["rev-list", "--bisect-vars", bad.rawValue, "--not"] + good.map(\.rawValue) + ["--"])
        if let result = try? await git.runAllowingFailure(command, background: true), result.exitCode == 0 {
            for line in result.output.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let value = Int(parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "'")))
                if parts[0] == "bisect_steps", let value { progress.steps = value + 1 }
            }
        }
        return progress
    }

    public func refName(for id: OID, in snapshot: RepositorySnapshot) -> String? {
        if let branch = snapshot.branches.first(where: { $0.tip == id }) { return branch.name }
        if let remote = snapshot.remoteBranches.first(where: { $0.tip == id }) { return remote.fullName }
        if let tag = snapshot.tags.first(where: { $0.target == id }) { return tag.name }
        return nil
    }

    public func startWatching() {
        guard watcher == nil, let snapshot else { return }
        let watcher = RepositoryWatcher(root: snapshot.root, gitDir: snapshot.gitDir, commonDir: snapshot.commonDir) { [weak self] changes in
            Task { @MainActor in await self?.outsideChanged(changes) }
        }
        if watcher.start() { self.watcher = watcher }
    }

    public func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    public var isWatching: Bool { watcher != nil }

    private func outsideChanged(_ changes: Set<RepositoryChange>) async {
        guard busy.isEmpty else { return }
        emit(.changedOutside(changes))
        if refreshing {
            refreshAgain = true
            return
        }
        refreshing = true
        defer { refreshing = false }
        repeat {
            refreshAgain = false
            try? await refresh()
        } while refreshAgain
    }
}

extension RepoState {
    var selectsHead: Bool {
        switch self {
        case .detached, .rebasing: true
        default: false
        }
    }
}

public enum CommitSelection: Sendable, Hashable {
    case wip
    case commit(OID)

    public var commitID: OID? {
        if case .commit(let id) = self { return id }
        return nil
    }
}

public enum LoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded
    case failed(GitError)
}

public enum RepositoryView: String, Sendable, Hashable, CaseIterable {
    case history
    case changes
    case stashes
    case reflog
    case refs
    case worktrees
    case submodules
    case blame
    case fileHistory
}

public struct FileFocus: Sendable, Hashable {
    public var path: String
    public var revision: String?

    public init(path: String, revision: String? = nil) {
        self.path = path
        self.revision = revision
    }
}

public struct ScrollRequest: Sendable, Hashable {
    public var target: CommitSelection
    public var sequence: Int
}

public struct InspectorInfo: Sendable, Hashable {
    public var id: OID
    public var describe: String?
    public var branches: [String]
}

public struct BisectProgress: Sendable, Hashable {
    public var steps = 0
    public var done = 0
    public var found: OID?

    public init(steps: Int = 0, done: Int = 0, found: OID? = nil) {
        self.steps = steps
        self.done = done
        self.found = found
    }
}

public struct StateDetails: Sendable, Hashable {
    public var previousBranch: String?
    public var subject: String?
    public var ontoName: String?
    public var bisect: BisectProgress?
    public var foundSubject: String?

    public init() {}
}

public enum OperationOutcome: Sendable {
    case succeeded
    case failed(GitError)
}

public enum RepositoryEvent: Sendable {
    case changedOutside(Set<RepositoryChange>)
    case fetched(newCommits: [String: Int])
    case operationProgress(id: String, fraction: Double?, label: String)
    case operationFinished(id: String, outcome: OperationOutcome)
    case stateChanged(RepoState)
}

public struct HistoryState: Sendable {
    public var commits: [Commit] = []
    public var rows: [GraphRow] = []
    public var index: [OID: Int] = [:]
    public var wipRow: GraphRow?
    public var wipFiles = 0
    public var lanes = 1
    public var phase: LoadState = .idle
    public var isComplete = false
    public var totalCount: Int?

    public init(phase: LoadState = .idle, isComplete: Bool = false) {
        self.phase = phase
        self.isComplete = isComplete
    }

    mutating func append(_ page: HistoryPage) {
        let start = commits.count
        commits.append(contentsOf: page.commits)
        rows.append(contentsOf: page.rows)
        for (offset, commit) in page.commits.enumerated() { index[commit.id] = start + offset }
        lanes = max(lanes, page.lanes)
        if page.isLast {
            isComplete = true
            totalCount = commits.count
        }
    }

    public var authors: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for commit in commits { counts[commit.authorName, default: 0] += 1 }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }
}

struct HistoryKey: Hashable {
    var head: OID?
    var headName: String?
    var tips: [String: OID]
    var dirty: Bool
    var scope: HistoryScope
    var bisect: [OID]

    init(_ snapshot: RepositorySnapshot, scope: HistoryScope) {
        head = snapshot.headOID
        headName = snapshot.head.branchName
        var tips: [String: OID] = [:]
        for branch in snapshot.branches { tips["b:" + branch.name] = branch.tip }
        for remote in snapshot.remoteBranches { tips["r:" + remote.fullName] = remote.tip }
        for tag in snapshot.tags { tips["t:" + tag.name] = tag.target }
        self.tips = tips
        dirty = !snapshot.working.isEmpty || !snapshot.conflicts.isEmpty
        self.scope = scope
        if case .bisecting(let good, let bad, _, _) = snapshot.state { bisect = good + (bad.map { [$0] } ?? []) } else { bisect = [] }
    }
}
