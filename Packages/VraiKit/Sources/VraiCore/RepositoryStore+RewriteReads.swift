import Foundation
import VraiGit

public struct PreviewCommit: Sendable, Hashable, Identifiable {
    public var id: OID
    public var subject: String

    public init(id: OID, subject: String) {
        self.id = id
        self.subject = subject
    }
}

public struct MergePreview: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case unknown
        case upToDate
        case fastForward
        case clean
        case conflicts
    }

    public var kind: Kind
    public var commits: [PreviewCommit]
    public var commitCount: Int
    public var files: Int
    public var conflicted: [String]

    public init(kind: Kind, commits: [PreviewCommit] = [], commitCount: Int = 0, files: Int = 0, conflicted: [String] = []) {
        self.kind = kind
        self.commits = commits
        self.commitCount = commitCount
        self.files = files
        self.conflicted = conflicted
    }
}

public struct RebasePreview: Sendable, Hashable {
    public var upToDate: Bool
    public var commits: [PreviewCommit]
    public var pushed: Int

    public init(upToDate: Bool, commits: [PreviewCommit], pushed: Int) {
        self.upToDate = upToDate
        self.commits = commits
        self.pushed = pushed
    }
}

public struct BisectPreview: Sendable, Hashable {
    public var candidates: Int
    public var valid: Bool

    public init(candidates: Int, valid: Bool) {
        self.candidates = candidates
        self.valid = valid
    }

    public var steps: Int {
        var count = 1
        var span = 2
        while span < max(2, candidates) {
            span *= 2
            count += 1
        }
        return count
    }
}

public struct StashDetail: Sendable, Hashable {
    public var files: [ChangedFile]
    public var untracked: Set<String>
    public var untrackedCommit: OID?

    public init(files: [ChangedFile], untracked: Set<String>, untrackedCommit: OID?) {
        self.files = files
        self.untracked = untracked
        self.untrackedCommit = untrackedCommit
    }
}

extension RepositoryStore {
    public func mergePreview(source: String) async -> MergePreview {
        guard let target = try? await resolveCommit(source), let head = try? await resolveCommit("HEAD") else { return MergePreview(kind: .unknown) }
        if target == head { return MergePreview(kind: .upToDate) }
        let contained = (try? await isAncestor(target, of: head)) ?? false
        if contained { return MergePreview(kind: .upToDate) }
        let commits = (try? await previewCommits(head.rawValue + ".." + target.rawValue)) ?? []
        let count = (try? await commitCount(head.rawValue + ".." + target.rawValue)) ?? commits.count
        let files = (try? await git.run(.read(["diff", "--name-only", "-z", "--no-ext-diff", head.rawValue + "..." + target.rawValue, "--"]), background: true).stdout.split(separator: 0).count) ?? 0
        if (try? await isAncestor(head, of: target)) == true {
            return MergePreview(kind: .fastForward, commits: commits, commitCount: count, files: files)
        }
        guard let result = try? await git.runAllowingFailure(SharedCommands.mergeTree(head.rawValue, target.rawValue), background: true), result.succeeded else {
            return MergePreview(kind: .clean, commits: commits, commitCount: count, files: files)
        }
        let fields = result.stdout.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        let conflicted = result.exitCode == 1 ? Array(Set(fields.dropFirst())).sorted() : []
        return MergePreview(kind: conflicted.isEmpty ? .clean : .conflicts, commits: commits, commitCount: count, files: files, conflicted: conflicted)
    }

    public func rebasePreview(onto: String) async -> RebasePreview {
        guard let base = try? await resolveCommit(onto), let head = try? await resolveCommit("HEAD") else { return RebasePreview(upToDate: false, commits: [], pushed: 0) }
        let steps = (try? await rebasePlan(onto: base.rawValue)) ?? []
        let commits = steps.map { PreviewCommit(id: $0.commit, subject: $0.subject) }
        let contains = (try? await isAncestor(base, of: head)) ?? false
        let upToDate = base == head || (steps.isEmpty && contains)
        var pushed = 0
        if let upstream = snapshot?.currentBranch?.upstream, !commits.isEmpty,
           let listed = try? await git.run(.read(["rev-list", upstream, "^" + base.rawValue, "--"]), background: true) {
            let published = Set(listed.output.split(separator: "\n").compactMap { OID(String($0)) })
            pushed = commits.filter { published.contains($0.id) }.count
        }
        return RebasePreview(upToDate: upToDate, commits: commits, pushed: pushed)
    }

    public func commitsBetween(_ base: String, _ tip: String, limit: Int = 50) async -> (commits: [PreviewCommit], count: Int) {
        let range = base + ".." + tip
        let commits = (try? await previewCommits(range, limit: limit)) ?? []
        let count = (try? await commitCount(range)) ?? commits.count
        return (commits, count)
    }

    public func bisectPreview(bad: String, good: String) async -> BisectPreview {
        guard let badCommit = try? await resolveCommit(bad), let goodCommit = try? await resolveCommit(good) else { return BisectPreview(candidates: 0, valid: false) }
        guard badCommit != goodCommit, (try? await isAncestor(goodCommit, of: badCommit)) == true else { return BisectPreview(candidates: 0, valid: false) }
        let count = (try? await commitCount(goodCommit.rawValue + ".." + badCommit.rawValue)) ?? 0
        return BisectPreview(candidates: count, valid: count > 0)
    }

    public func commitExists(_ revision: String) async -> OID? {
        try? await resolveCommit(revision)
    }

    public func previewSubjects(_ ids: [OID]) async -> [PreviewCommit] {
        var out: [PreviewCommit] = []
        for id in ids { out.append(PreviewCommit(id: id, subject: await subject(of: id) ?? "")) }
        return out
    }

    public func isMergeCommit(_ id: OID) async -> Bool {
        if let index = history.index[id] { return history.commits[index].parents.count > 1 }
        guard let result = try? await git.run(.read(["rev-list", "--parents", "-n", "1", id.rawValue, "--"]), background: true) else { return false }
        return result.output.split(separator: " ").count > 2
    }

    public func isAncestor(_ ancestor: OID, of descendant: OID) async throws -> Bool {
        let result = try await git.runAllowingFailure(.read(["merge-base", "--is-ancestor", ancestor.rawValue, descendant.rawValue], acceptedExitCodes: [0, 1]), background: true)
        return result.exitCode == 0
    }

    public func bisectSkipped() async -> [OID] {
        guard let result = try? await git.run(.read(["for-each-ref", "--format=%(refname)%00%(objectname)", "refs/bisect/"]), background: true) else { return [] }
        return result.output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\u{0}", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].hasPrefix("refs/bisect/skip-") else { return nil }
            return OID(String(parts[1]))
        }
    }

    public func conflictText(path: String) async -> String? {
        guard let root = try? await rewriteLocation().root else { return nil }
        return try? ConflictFileText.read(root.appending(path: path)).text
    }

    public func restoreConflictText(path: String, text: String) async throws {
        try await perform("resolve") {
            guard let root = try await rewriteLocation().root else { throw GitError(.notARepository) }
            let url = root.appending(path: path)
            try ConflictFileText.read(url).write(text, to: url)
        }
    }

    public func openMergeTool(path: String) async throws {
        try await perform("mergetool") {
            _ = try await git.run(SharedCommands.mergeTool(path: path))
        }
    }

    public func stashDetail(index: Int) async throws -> StashDetail {
        guard let stash = snapshot?.stashes.first(where: { $0.index == index }) else { throw GitError(.refNotFound) }
        let base = try await resolveCommit(stash.oid.rawValue + "^1")
        var files: [ChangedFile] = []
        if let base { files = try await changedFiles(from: base, to: stash.oid) }
        let third = try await resolveCommit(stash.oid.rawValue + "^3")
        var untracked: Set<String> = []
        if let third {
            let extra = try await commitDetail(id: third).files.map { file -> ChangedFile in
                var copy = file
                copy.status = .untracked
                return copy
            }
            untracked = Set(extra.map(\.path))
            files += extra.filter { file in !files.contains { $0.path == file.path } }
        }
        return StashDetail(files: files.sorted { $0.path < $1.path }, untracked: untracked, untrackedCommit: third)
    }

    public func stashDiff(index: Int, path: String, detail: StashDetail, context: Int = RepositoryStore.defaultContext) async throws -> FileDiff? {
        guard let stash = snapshot?.stashes.first(where: { $0.index == index }) else { throw GitError(.refNotFound) }
        if detail.untracked.contains(path), let third = detail.untrackedCommit {
            var diff = try await diff(for: path, in: third, context: context)
            diff?.status = .untracked
            return diff
        }
        guard let base = try await resolveCommit(stash.oid.rawValue + "^1") else { return nil }
        let oldPath = detail.files.first { $0.path == path }?.oldPath
        return try await diff(for: path, in: stash.oid, oldPath: oldPath, parent: base, context: context)
    }

    func previewCommits(_ range: String, limit: Int = 50) async throws -> [PreviewCommit] {
        let data = try await git.run(.read(["log", "-z", "--format=%H%x00%s", "-n", String(limit), range, "--"]), background: true).stdout
        var fields = data.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        var out: [PreviewCommit] = []
        while fields.count >= 2 {
            let id = fields.removeFirst().trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = fields.removeFirst()
            if let oid = OID(id) { out.append(PreviewCommit(id: oid, subject: subject)) }
        }
        return out
    }

    public func conflictBases(path: String) async -> [Int: [String]] {
        guard let text = await conflictText(path: path) else { return [:] }
        let current = ConflictResolver.conflicts(in: text)
        var out: [Int: [String]] = [:]
        var missing = false
        for conflict in current {
            if let base = conflict.base { out[conflict.index] = base } else { missing = true }
        }
        guard missing, let rendering = try? await diff3Rendering(path: path) else { return out }
        let alternatives = ConflictResolver.alternatives(in: rendering)
        for conflict in current where out[conflict.index] == nil {
            if let found = ConflictResolver.matchingBase(for: conflict, in: alternatives) { out[conflict.index] = found }
        }
        return out
    }

    @discardableResult
    public func markBisect(_ verdict: BisectVerdict, at commit: OID) async throws -> BisectOutcome {
        try await perform("bisect") {
            let command = GitCommand(["bisect", verdict.rawValue, commit.rawValue], risk: .safe, access: .write, acceptedExitCodes: [0, 2])
            return BisectOutcome.parse(try await git.run(command).output)
        }
    }
}
