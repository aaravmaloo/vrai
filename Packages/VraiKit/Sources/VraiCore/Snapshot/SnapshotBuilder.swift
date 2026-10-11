import Foundation
import VraiGit

public struct SnapshotBuilder: Sendable {
    public let git: GitProcess
    public var renameThreshold: Int
    public var fileManager: FileManager { .default }

    public init(git: GitProcess, renameThreshold: Int = 50) {
        self.git = git
        self.renameThreshold = renameThreshold
    }

    public static let numstatHead = GitCommand.read(["diff", "HEAD", "--numstat", "-z", "--find-renames", "--no-ext-diff", "--ignore-submodules=dirty"])
    public static let numstatCached = GitCommand.read(["diff", "--cached", "--numstat", "-z", "--find-renames", "--no-ext-diff"])
    public static let numstatWorktree = GitCommand.read(["diff", "--numstat", "-z", "--no-ext-diff"])

    public static func numstatHead(renameThreshold: Int) -> GitCommand {
        .read(["diff", "HEAD", "--numstat", "-z", "--find-renames=\(renameThreshold)%", "--no-ext-diff", "--ignore-submodules=dirty"])
    }

    public static func numstatCached(renameThreshold: Int) -> GitCommand {
        .read(["diff", "--cached", "--numstat", "-z", "--find-renames=\(renameThreshold)%", "--no-ext-diff"])
    }

    public func location() async throws -> RepositoryLocation {
        do {
            let data = try await git.run(RepositoryLocation.command, background: true).stdout
            if let location = RepositoryLocation.parse(data) { return location }
        } catch let error as GitError {
            if case .notARepository = error.code { throw error }
            if error.result?.errorOutput.contains("must be run in a work tree") != true { throw error }
        }
        let data = try await git.run(RepositoryLocation.bareCommand, background: true).stdout
        guard let location = RepositoryLocation.parse(data) else { throw GitError(.notARepository) }
        return location
    }

    public func build(colors: BranchColors = BranchColors(), network: NetworkStatus = .unknown) async throws -> RepositorySnapshot {
        let location = try await location()
        let hasModules = location.root.map { fileManager.fileExists(atPath: $0.appending(path: ".gitmodules").path(percentEncoded: false)) } ?? false

        async let statusData = git.run(StatusParser.command(renameThreshold: renameThreshold), background: true).stdout
        async let refsData = git.run(RefParser.command, background: true).stdout
        async let remotesData = git.run(ConfigParser.remotesCommand, background: true).stdout
        async let stashData = git.run(StashParser.command, background: true).stdout
        async let listedWorktrees = worktrees()
        async let modules: [Submodule] = hasModules && !location.isBare ? submodules(root: location.root) : []
        async let numstat = location.isBare ? [:] : numstats()

        let status = StatusParser.parse(try await statusData)
        let refsRaw = try await refsData
        let remotesRaw = try await remotesData
        let remoteNames = ConfigParser.remotes(remotesRaw).map(\.name)
        let refs = RefParser.parse(refsRaw, remotes: remoteNames)
        let remotes = ConfigParser.remotes(remotesRaw, heads: refs.remoteHeads)

        var colors = colors
        colors.assign(branches: refs.branches, remoteBranches: refs.remoteBranches, current: status.branch)
        let branches = refs.branches.map { branch -> Branch in
            var branch = branch
            branch.colorIndex = colors.color(for: branch.name) ?? 0
            return branch
        }
        let remoteBranches = refs.remoteBranches.map { remote -> RemoteBranch in
            var remote = remote
            remote.colorIndex = colors.color(for: remote.name) ?? 0
            return remote
        }

        var state = RepoStateReader.read(gitDir: location.gitDir, head: status.head, hasConflicts: !status.conflicts.isEmpty)
        state = try await enrich(state)

        var working = status.files
        let counts = try await numstat
        for index in working.indices {
            if let count = counts[working[index].path] {
                working[index].additions = count.additions
                working[index].deletions = count.deletions
                working[index].isBinary = count.binary
            } else if working[index].status == .untracked, let root = location.root {
                let lines = Self.lineCount(root.appending(path: working[index].path))
                working[index].additions = lines.count
                working[index].isBinary = lines.binary
            }
        }

        let stashes = StashParser.parse(try await stashData)
        let worktrees = try await listedWorktrees.map { worktree in
            var worktree = worktree
            if worktree.isMain { worktree.changes = working.count }
            return worktree
        }
        let dirty = Set(working.filter { $0.isSubmodule }.map(\.path))
        let submodules = try await modules.map { module in
            var module = module
            if module.state == .clean, dirty.contains(module.path) { module.state = .modified }
            return module
        }

        let fetchHead = location.gitDir.appending(path: "FETCH_HEAD").path(percentEncoded: false)
        let lastFetch = (try? fileManager.attributesOfItem(atPath: fetchHead))?[.modificationDate] as? Date
        let objects = location.commonDir.appending(path: "objects/info")
        let hasCommitGraph = fileManager.fileExists(atPath: objects.appending(path: "commit-graph").path(percentEncoded: false))
            || fileManager.fileExists(atPath: objects.appending(path: "commit-graphs/commit-graph-chain").path(percentEncoded: false))

        return RepositorySnapshot(
            root: location.root,
            gitDir: location.gitDir,
            commonDir: location.commonDir,
            isBare: location.isBare,
            isShallow: location.isShallow,
            head: status.head,
            headOID: status.oid,
            upstream: status.upstream,
            ahead: status.ahead,
            behind: status.behind,
            branches: branches,
            remoteBranches: remoteBranches,
            remotes: remotes,
            tags: refs.tags,
            stashes: stashes,
            worktrees: worktrees,
            submodules: submodules,
            working: working,
            conflicts: status.conflicts,
            state: state,
            hooks: HookReader.read(location.hooksDir),
            network: network,
            lastFetch: lastFetch,
            gitVersion: git.executable.version,
            branchColors: colors,
            hasCommitGraph: hasCommitGraph
        )
    }

    struct Count {
        var additions: Int
        var deletions: Int
        var binary: Bool
    }

    func numstats() async throws -> [String: Count] {
        let head = try await git.runAllowingFailure(Self.numstatHead(renameThreshold: renameThreshold), background: true)
        if head.succeeded { return Self.parseNumstat(head.stdout) }
        async let cached = git.run(Self.numstatCached(renameThreshold: renameThreshold), background: true).stdout
        async let worktree = git.run(Self.numstatWorktree, background: true).stdout
        var merged = Self.parseNumstat(try await cached)
        for (path, count) in Self.parseNumstat(try await worktree) {
            if var existing = merged[path] {
                existing.additions += count.additions
                existing.deletions += count.deletions
                merged[path] = existing
            } else {
                merged[path] = count
            }
        }
        return merged
    }

    static func parseNumstat(_ data: Data) -> [String: Count] {
        var out: [String: Count] = [:]
        let tokens = ParseSupportBridge.nulFields(data)
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            index += 1
            let parts = token.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            var path = String(parts[2])
            if path.isEmpty, index + 1 < tokens.count {
                path = tokens[index + 1]
                index += 2
            }
            let binary = parts[0] == "-" && parts[1] == "-"
            out[path] = Count(additions: Int(parts[0]) ?? 0, deletions: Int(parts[1]) ?? 0, binary: binary)
        }
        return out
    }

    static func lineCount(_ url: URL) -> (count: Int, binary: Bool) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (0, false) }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 1 << 20) else { return (0, false) }
        if data.prefix(8000).contains(0) { return (0, true) }
        var lines = data.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
        if let last = data.last, last != 0x0A { lines += 1 }
        return (lines, false)
    }

    func enrich(_ state: RepoState) async throws -> RepoState {
        switch state {
        case .detached(let id, _):
            let result = try await git.runAllowingFailure(.read(["describe", "--tags", "--abbrev=0", id.rawValue]), background: true)
            let tag = result.exitCode == 0 ? result.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil
            return .detached(id, nearestTag: tag)
        case .bisecting(_, _, let current, _):
            let refs = try await git.run(.read(["for-each-ref", "--format=%(refname) %(objectname)", "refs/bisect"]), background: true).output
            var good: [OID] = []
            var bad: OID?
            for line in refs.split(separator: "\n") {
                let parts = line.split(separator: " ")
                guard parts.count == 2, let oid = OID(String(parts[1])) else { continue }
                if parts[0] == "refs/bisect/bad" { bad = oid } else if parts[0].hasPrefix("refs/bisect/good") { good.append(oid) }
            }
            var remaining: Int?
            if let bad, !good.isEmpty {
                let vars = try await git.runAllowingFailure(.read(["rev-list", "--bisect-vars", bad.rawValue, "--not"] + good.map(\.rawValue)), background: true)
                if vars.exitCode == 0 { remaining = RepoStateReader.bisectVars(vars.stdout).remaining }
            }
            return .bisecting(good: good, bad: bad, current: current, remaining: remaining)
        default:
            return state
        }
    }

    func worktrees() async throws -> [Worktree] {
        let worktrees = WorktreeParser.parse(try await git.run(WorktreeParser.command, background: true).stdout)
        return await withTaskGroup(of: (Int, Int?).self) { group in
            for (index, worktree) in worktrees.enumerated() where !worktree.isMain && !worktree.isBare && worktree.prunable == nil {
                let process = GitProcess(executable: git.executable, workingDirectory: URL(filePath: worktree.path, directoryHint: .isDirectory), environment: git.environment)
                group.addTask {
                    let data = try? await process.run(.read(["status", "--porcelain=v2", "-z", "--untracked-files=normal"]), background: true).stdout
                    return (index, data.map { StatusParser.parse($0).files.count })
                }
            }
            var out = worktrees
            for await (index, count) in group { out[index].changes = count }
            return out
        }
    }

    func submodules(root: URL?) async throws -> [Submodule] {
        guard let root else { return [] }
        let declared = ConfigParser.gitmodules(try await git.run(SubmoduleParser.gitmodulesCommand, background: true).stdout)
        guard !declared.isEmpty else { return [] }
        let links = SubmoduleParser.gitlinks(try await git.run(SubmoduleParser.stageCommand(paths: declared.map(\.path)), background: true).stdout)
        return await withTaskGroup(of: (Int, Submodule).self) { group in
            for (index, link) in links.enumerated() {
                let info = declared.first { $0.path == link.path }
                group.addTask {
                    let directory = root.appending(path: link.path, directoryHint: .isDirectory)
                    let process = GitProcess(executable: git.executable, workingDirectory: directory, environment: git.environment)
                    var head = SubmoduleParser.head(at: directory)
                    if head == .unresolved {
                        let result = try? await process.runAllowingFailure(.read(["rev-parse", "--verify", "--quiet", "HEAD"]), background: true)
                        head = result.flatMap { $0.exitCode == 0 ? OID($0.output.trimmingCharacters(in: .whitespacesAndNewlines)) : nil }.map(SubmoduleParser.Head.commit) ?? .unpopulated
                    }
                    var submodule = SubmoduleParser.submodule(link, declared: info, head: head)
                    guard submodule.state == .ahead, let recorded = submodule.recorded, let checkedOut = submodule.checkedOut else { return (index, submodule) }
                    if let data = try? await process.run(.read(["rev-list", "--left-right", "--count", recorded.rawValue + "..." + checkedOut.rawValue]), background: true).output {
                        let numbers = data.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
                        if numbers.count == 2 {
                            if numbers[1] > 0, numbers[0] == 0 {
                                submodule.state = .ahead
                                submodule.ahead = numbers[1]
                            } else if numbers[0] > 0, numbers[1] == 0 {
                                submodule.state = .behind
                                submodule.ahead = -numbers[0]
                            } else {
                                submodule.state = .modified
                                submodule.ahead = numbers[1]
                            }
                        }
                    }
                    return (index, submodule)
                }
            }
            var out = Array(repeating: Submodule(path: "", state: .clean), count: links.count)
            for await (index, submodule) in group { out[index] = submodule }
            return out
        }
    }
}

enum ParseSupportBridge {
    static func nulFields(_ data: Data) -> [String] {
        data.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
    }
}
