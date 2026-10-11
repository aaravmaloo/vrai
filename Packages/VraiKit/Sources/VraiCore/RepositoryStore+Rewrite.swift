import Foundation
import VraiGit

struct RewriteRefs: Sendable, Hashable {
    var head: String?
    var headOID: OID?
    var branches: [String: OID]

    var headRef: String? {
        guard let head, head.hasPrefix("refs/") else { return nil }
        return head
    }

    var name: String {
        if let headRef { return headRef.hasPrefix("refs/heads/") ? String(headRef.dropFirst("refs/heads/".count)) : headRef }
        return headOID?.short ?? "HEAD"
    }

    func movingHead(to oid: OID) -> RewriteRefs {
        var copy = self
        copy.headOID = oid
        if let headRef { copy.branches[headRef] = oid } else { copy.head = oid.rawValue }
        return copy
    }

    func changes(comparedTo after: RewriteRefs) -> [String: OID] {
        var refs: [String: OID] = [:]
        for (name, oid) in branches where after.branches[name] != oid { refs[name] = oid }
        return refs
    }

    func refsBefore(changed: [String: OID]) -> [String: OID] {
        var refs = changed
        if let headRef, let tip = branches[headRef] ?? headOID {
            refs[headRef] = tip
        } else if headRef == nil, let headOID {
            refs["HEAD"] = headOID
        }
        return refs
    }
}

struct ConflictFileText {
    var text: String
    var encoding: String.Encoding

    static func read(_ url: URL) throws -> ConflictFileText {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw GitError(.unknown(exit: 1, stderr: error.localizedDescription))
        }
        if let text = String(data: data, encoding: .utf8) { return ConflictFileText(text: text, encoding: .utf8) }
        return ConflictFileText(text: String(data: data, encoding: .isoLatin1) ?? "", encoding: .isoLatin1)
    }

    func write(_ text: String, to url: URL) throws {
        guard let data = text.data(using: encoding) else { throw GitError(.unknown(exit: 1, stderr: url.lastPathComponent)) }
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: data)
        } catch {
            throw GitError(.unknown(exit: 1, stderr: error.localizedDescription))
        }
    }
}

extension RepositoryStore {
    @discardableResult
    public func merge(source: String, mode: MergeMode = .auto, message: String? = nil, strategyOption: String? = nil) async throws -> MergeOutcome {
        try await perform("merge") {
            let before = try await rewriteRefs()
            let result = try await git.run(RewriteCommands.merge(source: source, mode: mode, message: message, strategyOption: strategyOption))
            if result.output.contains("Already up to date") { return .upToDate }
            if mode == .squash { return .squashed }
            let after = try await rewriteRefs()
            guard let tip = after.headOID, tip != before.headOID else { return .upToDate }
            let fastForward = result.output.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == "Fast-forward" }
            let detail = fastForward ? String(localized: "Fast-forward", bundle: .module) : String(localized: "Merge commit \(tip.short)", bundle: .module)
            try await recordRewrite(.merge, label: String(localized: "Merged \(source) into \(before.name)", bundle: .module), detail: detail, before: before, after: after)
            return fastForward ? .fastForwarded(to: tip) : .merged(commit: tip)
        }
    }

    public func resolve(path: String, block: Int?, with choice: ConflictChoice) async throws {
        try await perform("resolve") {
            if block == nil, choice == .ours || choice == .theirs {
                let result = try await git.runAllowingFailure(RewriteCommands.checkout(choice, path: path))
                if result.succeeded { return }
                let output = result.errorOutput
                guard output.contains("does not have our version") || output.contains("does not have their version") else { throw ErrorClassifier.classify(result) }
                try await git.run(RewriteCommands.remove(path: path))
                return
            }
            guard let root = try await rewriteLocation().root else { throw GitError(.notARepository) }
            let url = root.appending(path: path)
            let file = try ConflictFileText.read(url)
            var diff3: String?
            if choice == .base, ConflictResolver.needsBase(file.text, block: block) {
                diff3 = try await diff3Rendering(path: path)
            }
            let resolved: String
            do {
                resolved = try ConflictResolver.resolve(file.text, block: block, with: choice, diff3: diff3)
            } catch let failure as ConflictResolver.Failure {
                throw GitError(.unknown(exit: 1, stderr: String(describing: failure)))
            }
            try file.write(resolved, to: url)
        }
    }

    public func markResolved(path: String) async throws {
        try await perform("markResolved") {
            if let root = try await rewriteLocation().root, let data = try? Data(contentsOf: root.appending(path: path)),
               ConflictResolver.hasMarkers(String(decoding: data, as: UTF8.self)) {
                throw GitError(.conflictMarkersRemain)
            }
            try await git.run(RewriteCommands.add(path: path))
        }
    }

    public func abort() async throws {
        try await perform("abort") {
            let gitDir = try await rewriteLocation().gitDir
            guard let operation = OperationInProgress.current(gitDir: gitDir) else { return }
            try await refreshIndex()
            try await git.run(RewriteCommands.abort(operation))
            if operation == .rebase { InteractivePlan.Files(gitDir: gitDir).clear() }
        }
    }

    @discardableResult
    public func rebase(onto: String, autostash: Bool = false, updateRefs: Bool = false, rebaseMerges: Bool = false, inBackground: Bool = false) async throws -> RebaseOutcome {
        try await perform("rebase") {
            let gitDir = try await rewriteLocation().gitDir
            let before = try await rewriteRefs()
            let count = try await commitCount(onto + "..HEAD")
            if inBackground, git.executable.supports(.replay), !rebaseMerges, let branch = before.headRef, branch.hasPrefix("refs/heads/") {
                return try await replayRebase(onto: onto, branch: branch, updateRefs: updateRefs, before: before, count: count)
            }
            if OperationInProgress.current(gitDir: gitDir) != .rebase { InteractivePlan.Files(gitDir: gitDir).clear() }
            let result = try await git.runAllowingFailure(RewriteCommands.rebase(onto: onto, autostash: autostash, updateRefs: updateRefs, rebaseMerges: rebaseMerges))
            return try await finishRebase(result, gitDir: gitDir, before: before, onto: onto) { count == 0 ? .fastForwarded : .rebased(commits: count) }
        }
    }

    @discardableResult
    public func interactiveRebase(onto: String, plan steps: [RebaseStep]) async throws -> RebaseOutcome {
        try await perform("interactiveRebase") {
            let gitDir = try await rewriteLocation().gitDir
            let before = try await rewriteRefs()
            let plan = InteractivePlan(steps: steps)
            switch plan.problem {
            case .empty?:
                throw GitError(.unknown(exit: 1, stderr: String(localized: "There's nothing to rebase.", bundle: .module)))
            case .startsWithFold?:
                throw GitError(.unknown(exit: 1, stderr: String(localized: "The first step can't be squash or fixup. There's no earlier commit in the list to fold it into.", bundle: .module)))
            case nil:
                break
            }
            let files = InteractivePlan.Files(gitDir: gitDir)
            var command = RewriteCommands.interactiveRebase(onto: onto)
            if OperationInProgress.current(gitDir: gitDir) != .rebase {
                guard let helper = EditorHelper.locate(environment: git.environment) else {
                    throw GitError(.unknown(exit: 127, stderr: String(localized: "vrai-editor is missing, so Vrai can't hand the rebase plan to git. Reinstall Vrai.", bundle: .module)))
                }
                do {
                    try plan.write(to: files)
                } catch {
                    throw GitError(.unknown(exit: 1, stderr: error.localizedDescription))
                }
                command = RewriteCommands.interactiveRebase(
                    onto: onto,
                    sequenceEditor: EditorHelper.sequenceEditor(helper: helper, todo: files.todo),
                    editor: files.hasMessages ? EditorHelper.messageEditor(helper: helper, messages: files.messages) : nil
                )
            }
            let result = try await git.runAllowingFailure(command)
            let kept = steps.filter { $0.action != .drop }.count
            return try await finishRebase(result, gitDir: gitDir, before: before, onto: onto, interactive: true) { .rebased(commits: kept) }
        }
    }

    public func rebasePlan(onto: String) async throws -> [RebaseStep] {
        InteractivePlan.parse(try await git.run(InteractivePlan.listCommand(onto: onto), background: true).stdout)
    }

    public func continueOperation() async throws {
        try await perform("continue") {
            try await advanceOperation(skip: false)
        }
    }

    public func skipStep() async throws {
        try await perform("skip") {
            try await advanceOperation(skip: true)
        }
    }

    public func cherryPick(ids: [OID], recordOrigin: Bool = false, noCommit: Bool = false, mainline: Int? = nil) async throws {
        try await perform("cherryPick") {
            let before = try await rewriteRefs()
            try await git.run(RewriteCommands.cherryPick(ids: ids, recordOrigin: recordOrigin, noCommit: noCommit, mainline: mainline))
            let after = try await rewriteRefs()
            let what = ids.count == 1 ? ids[0].short : n(ids.count, "commit")
            try await recordRewrite(.cherryPick, label: String(localized: "Cherry-picked \(what) onto \(before.name)", bundle: .module), detail: nil, before: before, after: after)
        }
    }

    public func revert(id: OID, noCommit: Bool = false, mainline: Int? = nil) async throws {
        try await perform("revert") {
            let before = try await rewriteRefs()
            try await git.run(RewriteCommands.revert(id: id, noCommit: noCommit, mainline: mainline))
            let after = try await rewriteRefs()
            let subject = try await commitSubject(after.headOID)
            try await recordRewrite(.revert, label: String(localized: "Reverted \(id.short)", bundle: .module), detail: subject, before: before, after: after)
        }
    }

    public func reset(to target: String, mode: ResetMode) async throws {
        try await perform("reset") {
            let before = try await rewriteRefs()
            var stashCommit: OID?
            var discarded = 0
            if mode == .hard {
                let created = try await git.runAllowingFailure(RewriteCommands.stashCreate)
                if created.succeeded, let oid = OID(created.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    stashCommit = oid
                    discarded = try await changedPathCount()
                }
            }
            if mode == .keep { try await refreshIndex() }
            try await git.run(RewriteCommands.reset(to: target, mode: mode))
            let after = try await rewriteRefs()
            let tip = after.headOID?.short ?? target
            let label = String(localized: "Reset \(before.name) to \(tip) (\(mode.rawValue))", bundle: .module)
            let detail = stashCommit != nil
                ? String(localized: "Discarded \(n(discarded, "change")); a copy stays in Undo history", bundle: .module)
                : before.headOID.map { String(localized: "ORIG_HEAD \($0.short)", bundle: .module) }
            try await recordRewrite(mode == .hard ? .resetHard : .reset, label: label, detail: detail, before: before, after: after, stashCommit: stashCommit, always: stashCommit != nil)
        }
    }

    public func stash(message: String? = nil, includeUntracked: Bool = false, keepIndex: Bool = false, onlyStaged: Bool = false, paths: [String] = []) async throws {
        try await perform("stash") {
            let result = try await git.run(RewriteCommands.stash(message: message, includeUntracked: includeUntracked, keepIndex: keepIndex, onlyStaged: onlyStaged, paths: paths))
            if result.output.contains("No local changes to save") || result.errorOutput.contains("No local changes to save") {
                throw GitError(.nothingToStash, result: result)
            }
        }
    }

    public func applyStash(index: Int, pop: Bool = false, restoreIndex: Bool = false) async throws {
        try await perform(pop ? "popStash" : "applyStash") {
            _ = try await git.run(RewriteCommands.applyStash(index: index, pop: pop, restoreIndex: restoreIndex))
        }
    }

    public func dropStash(index: Int) async throws {
        try await perform("dropStash") {
            let stashes = StashParser.parse(try await git.run(StashParser.command, background: true).stdout)
            try await git.run(RewriteCommands.dropStash(index: index))
            guard let dropped = stashes.first(where: { $0.index == index }) else { return }
            let shown = dropped.message.replacing(#/^(?:On|WIP on) [^:]+: /#, with: "")
            let quoted = "\u{201C}" + (shown.count > 44 ? String(shown.prefix(43)) + "\u{2026}" : shown) + "\u{201D}"
            try await undo.record(UndoEntry(kind: .stashDrop, label: String(localized: "Dropped stash \(quoted)", bundle: .module), stashCommit: dropped.oid, message: dropped.message))
        }
    }

    public func branchFromStash(index: Int, name: String) async throws {
        try await perform("branchFromStash") {
            _ = try await git.run(RewriteCommands.branchFromStash(index: index, name: name))
        }
    }

    @discardableResult
    public func startBisect(bad: String, good: String) async throws -> BisectOutcome {
        try await perform("bisect") {
            BisectOutcome.parse(try await git.run(RewriteCommands.startBisect(bad: bad, good: good)).output)
        }
    }

    @discardableResult
    public func markBisect(_ verdict: BisectVerdict) async throws -> BisectOutcome {
        try await perform("bisect") {
            BisectOutcome.parse(try await git.run(RewriteCommands.markBisect(verdict)).output)
        }
    }

    public func endBisect() async throws {
        try await perform("bisect") {
            _ = try await git.run(RewriteCommands.endBisect)
        }
    }

    func advanceOperation(skip: Bool) async throws {
        let gitDir = try await rewriteLocation().gitDir
        guard let operation = OperationInProgress.current(gitDir: gitDir) else { return }
        let files = InteractivePlan.Files(gitDir: gitDir)
        var editor: String?
        if operation == .rebase, files.hasMessages, let helper = EditorHelper.locate(environment: git.environment) {
            editor = EditorHelper.messageEditor(helper: helper, messages: files.messages)
        }
        guard let command = skip ? RewriteCommands.skip(operation, editor: editor) : RewriteCommands.continueOperation(operation, editor: editor) else { return }
        let rebaseState = operation == .rebase ? RebaseState.read(gitDir: gitDir) : nil
        let sequencerHead = RebaseState.sequencerHead(gitDir: gitDir)
        let mergeSource = operation == .merge ? Self.mergeSource(gitDir: gitDir) : nil
        let picked = Self.pendingCommit(gitDir: gitDir, operation: operation)
        let before = try await rewriteRefs()
        let result = try await git.runAllowingFailure(command)
        if !result.succeeded { throw ErrorClassifier.classify(result) }
        if OperationInProgress.current(gitDir: gitDir) == operation {
            if operation == .rebase { throw GitError(.stoppedForEdit, result: result) }
            return
        }
        switch operation {
        case .rebase:
            files.clear()
            guard let rebaseState else { return }
            let name = rebaseState.headName.map { $0.hasPrefix("refs/heads/") ? String($0.dropFirst("refs/heads/".count)) : $0 } ?? "HEAD"
            let onto = rebaseState.onto?.short ?? ""
            let detail = rebaseState.origHead.map { String(localized: "ORIG_HEAD \($0.short)", bundle: .module) }
            try await undo.record(UndoEntry(kind: .rebase, label: String(localized: "Rebased \(name) onto \(onto)", bundle: .module), detail: detail, head: rebaseState.head, refsBefore: rebaseState.refsBefore))
        case .merge:
            let after = try await rewriteRefs()
            let label = mergeSource.map { String(localized: "Merged \($0) into \(before.name)", bundle: .module) } ?? String(localized: "Merged into \(before.name)", bundle: .module)
            try await recordRewrite(.merge, label: label, detail: after.headOID.map { String(localized: "Merge commit \($0.short)", bundle: .module) }, before: before, after: after)
        case .cherryPick, .revert:
            let start = sequencerHead.map { before.movingHead(to: $0) } ?? before
            let after = try await rewriteRefs()
            let what = picked?.short ?? before.name
            let label = operation == .cherryPick
                ? String(localized: "Cherry-picked \(what) onto \(before.name)", bundle: .module)
                : String(localized: "Reverted \(what)", bundle: .module)
            let detail = operation == .revert ? try await commitSubject(after.headOID) : nil
            try await recordRewrite(operation == .cherryPick ? .cherryPick : .revert, label: label, detail: detail, before: start, after: after)
        case .applyingPatches, .bisect:
            break
        }
    }

    func finishRebase(_ result: GitResult, gitDir: URL, before: RewriteRefs, onto: String, interactive: Bool = false, outcome: () -> RebaseOutcome) async throws -> RebaseOutcome {
        let files = InteractivePlan.Files(gitDir: gitDir)
        let inProgress = OperationInProgress.current(gitDir: gitDir) == .rebase
        if !result.succeeded {
            if !inProgress { files.clear() }
            throw ErrorClassifier.classify(result)
        }
        if inProgress { throw GitError(.stoppedForEdit, result: result) }
        files.clear()
        let after = try await rewriteRefs()
        guard !before.changes(comparedTo: after).isEmpty || before.headOID != after.headOID else { return .upToDate }
        let label = interactive
            ? String(localized: "Rebased \(before.name) interactively", bundle: .module)
            : String(localized: "Rebased \(before.name) onto \(onto)", bundle: .module)
        try await recordRewrite(.rebase, label: label, detail: before.headOID.map { String(localized: "ORIG_HEAD \($0.short)", bundle: .module) }, before: before, after: after)
        return outcome()
    }

    func replayRebase(onto: String, branch: String, updateRefs: Bool, before: RewriteRefs, count: Int) async throws -> RebaseOutcome {
        let short = String(branch.dropFirst("refs/heads/".count))
        var result = try await git.runAllowingFailure(RewriteCommands.replay(onto: onto, branch: short, contained: updateRefs))
        if !result.succeeded, result.errorOutput.contains("ref-action") {
            result = try await git.runAllowingFailure(RewriteCommands.replay(onto: onto, branch: short, contained: updateRefs, printRefs: false))
        }
        guard result.succeeded else { throw ErrorClassifier.classify(result) }
        let elsewhere = Set(WorktreeParser.parse(try await git.run(WorktreeParser.command, background: true).stdout).compactMap { $0.branch.map { "refs/heads/" + $0 } }).subtracting([branch])
        var updates = RefUpdate.parse(result.output).filter { $0.new != $0.old && !elsewhere.contains($0.ref) }
        if !updates.contains(where: { $0.ref == branch }), count == 0, let old = before.headOID, let target = try await resolveCommit(onto), target != old {
            updates.append(RefUpdate(ref: branch, new: target, old: old))
        }
        guard !updates.isEmpty else { return .upToDate }
        if let current = updates.first(where: { $0.ref == branch }) {
            try await refreshIndex()
            try await git.run(RewriteCommands.moveWorktree(from: current.old, to: current.new))
        }
        try await git.run(RewriteCommands.updateRefs(updates, reason: "rebase (replay): onto \(onto)"))
        let after = try await rewriteRefs()
        try await recordRewrite(.rebase, label: String(localized: "Rebased \(before.name) onto \(onto)", bundle: .module), detail: before.headOID.map { String(localized: "ORIG_HEAD \($0.short)", bundle: .module) }, before: before, after: after)
        return count == 0 ? .fastForwarded : .rebased(commits: count)
    }

    func recordRewrite(_ kind: UndoEntry.Kind, label: String, detail: String?, before: RewriteRefs, after: RewriteRefs, stashCommit: OID? = nil, always: Bool = false) async throws {
        let changed = before.changes(comparedTo: after)
        guard always || !changed.isEmpty || before.headOID != after.headOID else { return }
        try await undo.record(UndoEntry(kind: kind, label: label, detail: detail, head: before.head, refsBefore: before.refsBefore(changed: changed), stashCommit: stashCommit))
    }

    func rewriteRefs() async throws -> RewriteRefs {
        let git = self.git
        async let symbolic = git.runAllowingFailure(.read(["symbolic-ref", "-q", "HEAD"]), background: true)
        async let tip = git.runAllowingFailure(.read(["rev-parse", "-q", "--verify", "HEAD"]), background: true)
        async let listed = git.run(.read(["for-each-ref", "--format=%(refname)%00%(objectname)", "refs/heads"]), background: true)
        var branches: [String: OID] = [:]
        for line in try await listed.stdout.split(separator: 0x0A) {
            let parts = line.split(separator: 0x00, omittingEmptySubsequences: false)
            guard parts.count == 2, let oid = OID(String(decoding: parts[1], as: UTF8.self)) else { continue }
            branches[String(decoding: parts[0], as: UTF8.self)] = oid
        }
        let symbolicResult = try await symbolic
        let tipResult = try await tip
        let headOID = tipResult.exitCode == 0 ? OID(tipResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) : nil
        let ref = symbolicResult.exitCode == 0 ? symbolicResult.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        return RewriteRefs(head: ref ?? headOID?.rawValue, headOID: headOID, branches: branches)
    }

    func rewriteLocation() async throws -> (root: URL?, gitDir: URL) {
        if let snapshot { return (snapshot.root, snapshot.gitDir) }
        guard let location = RepositoryLocation.parse(try await git.run(RepositoryLocation.command, background: true).stdout) else { throw GitError(.notARepository) }
        return (location.root, location.gitDir)
    }

    func refreshIndex() async throws {
        try await git.run(RewriteCommands.refreshIndex, background: true)
    }

    func commitCount(_ range: String) async throws -> Int {
        Int(try await git.run(.read(["rev-list", "--count", range]), background: true).output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    func resolveCommit(_ revision: String) async throws -> OID? {
        let result = try await git.runAllowingFailure(.read(["rev-parse", "-q", "--verify", revision + "^{commit}"]), background: true)
        return result.exitCode == 0 ? OID(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) : nil
    }

    func commitSubject(_ id: OID?) async throws -> String? {
        guard let id else { return nil }
        return try await git.run(.read(["log", "-1", "--format=%s", id.rawValue]), background: true).output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func changedPathCount() async throws -> Int {
        let data = try await git.run(.read(["diff", "HEAD", "--name-only", "-z", "--no-ext-diff"]), background: true).stdout
        return data.split(separator: 0).count
    }

    func diff3Rendering(path: String) async throws -> String? {
        let data = try await git.run(RewriteCommands.unmergedStages(path: path), background: true).stdout
        var stages: [Int: OID] = [:]
        for entry in data.split(separator: 0) {
            let line = String(decoding: entry, as: UTF8.self)
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let fields = line[..<tab].split(separator: " ")
            guard fields.count == 3, let stage = Int(fields[2]), let oid = OID(String(fields[1])) else { continue }
            stages[stage] = oid
        }
        guard let ours = stages[2], let theirs = stages[3] else { return nil }
        var base = stages[1]
        if base == nil {
            let empty = try await git.run(GitCommand(["hash-object", "-w", "--stdin"], stdin: Data(), access: .write), background: true)
            base = OID(empty.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let base else { return nil }
        let merged = try await git.run(RewriteCommands.mergeFile(ours: ours, base: base, theirs: theirs), background: true).stdout
        return String(data: merged, encoding: .utf8) ?? String(decoding: merged, as: UTF8.self)
    }

    static func pendingCommit(gitDir: URL, operation: OperationInProgress) -> OID? {
        let name: String
        switch operation {
        case .cherryPick: name = "CHERRY_PICK_HEAD"
        case .revert: name = "REVERT_HEAD"
        default: return nil
        }
        let text = (try? String(contentsOf: gitDir.appending(path: name), encoding: .utf8)) ?? ""
        return OID(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func mergeSource(gitDir: URL) -> String? {
        let message = (try? String(contentsOf: gitDir.appending(path: "MERGE_MSG"), encoding: .utf8)) ?? ""
        return message.firstMatch(of: #/^Merge (?:remote-tracking )?(?:branch|tag|commit) '([^']+)'/#).map { String($0.output.1) }
    }
}
