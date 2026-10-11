import Foundation
import VraiGit

public typealias ProgressHandler = @Sendable (GitProgress) -> Void

public struct ActionSummary: Sendable, Hashable {
    public var message: String
    public var detail: String?

    public init(_ message: String, detail: String? = nil) {
        self.message = message
        self.detail = detail
    }
}

public struct FetchResult: Sendable, Hashable {
    public var remotes: [String]
    public var newCommits: [String: Int]
    public var updatedRefs: [String]
    public var prunedRefs: [String]
    public var total: Int

    public var summary: ActionSummary {
        if total > 0 {
            let refs = updatedRefs.filter { (newCommits[$0] ?? 0) > 0 }
            return ActionSummary(String(localized: "Fetched \(n(total, "new commit"))", bundle: .module), detail: refs.joined(separator: ", "))
        }
        return ActionSummary(String(localized: "Everything is up to date", bundle: .module), detail: String(localized: "Fetched \(listed(remotes)).", bundle: .module))
    }
}

public struct PullResult: Sendable, Hashable {
    public var branch: String
    public var upstream: String
    public var mode: PullMode
    public var pulled: Int
    public var ahead: Int
    public var before: OID?
    public var after: OID?

    public var upToDate: Bool { before == after }

    public var summary: ActionSummary {
        if upToDate {
            return ActionSummary(String(localized: "Already up to date", bundle: .module), detail: String(localized: "\(branch) has everything on \(upstream).", bundle: .module))
        }
        let detail: String
        if mode == .rebase {
            detail = String(localized: "Your \(n(ahead, "commit")) now sit on top.", bundle: .module)
        } else if ahead > 0 {
            detail = String(localized: "Merged with your \(n(ahead, "commit")).", bundle: .module)
        } else {
            detail = String(localized: "Fast-forwarded \(branch).", bundle: .module)
        }
        return ActionSummary(String(localized: "Pulled \(n(pulled, "commit")) from \(upstream)", bundle: .module), detail: detail)
    }
}

public struct PushResult: Sendable, Hashable {
    public var remote: String
    public var branch: String
    public var remoteBranch: String
    public var pushed: Int
    public var force: PushForce
    public var setUpstream: Bool
    public var publishedUpstream: Bool
    public var upToDate: Bool

    public var summary: ActionSummary {
        let count = n(max(1, pushed), "commit")
        let target = remote + "/" + remoteBranch
        let message = force == .none
            ? String(localized: "Pushed \(count) to \(target)", bundle: .module)
            : String(localized: "Force pushed \(count) to \(target)", bundle: .module)
        if force == .withLease { return ActionSummary(message, detail: String(localized: "Replaced the remote branch; nobody else had pushed to it.", bundle: .module)) }
        if publishedUpstream { return ActionSummary(message, detail: String(localized: "Set \(target) as the upstream.", bundle: .module)) }
        return ActionSummary(message)
    }
}

public struct OperationHandle<Value: Sendable>: Sendable {
    public let progress: AsyncStream<GitProgress>
    public let task: Task<Value, any Error>

    public func cancel() { task.cancel() }

    public var value: Value {
        get async throws { try await task.value }
    }
}

func listed(_ names: [String]) -> String {
    switch names.count {
    case 0: return ""
    case 1: return names[0]
    default: return names.dropLast().joined(separator: ", ") + " " + String(localized: "and", bundle: .module) + " " + names[names.count - 1]
    }
}

extension RepositoryStore {
    public func start<Value: Sendable>(_ body: @escaping @MainActor (@escaping ProgressHandler) async throws -> Value) -> OperationHandle<Value> {
        let (stream, continuation) = AsyncStream.makeStream(of: GitProgress.self, bufferingPolicy: .bufferingNewest(256))
        let task = Task { @MainActor in
            defer { continuation.finish() }
            return try await body { continuation.yield($0) }
        }
        return OperationHandle(progress: stream, task: task)
    }

    public func fetchOperation(remote: String? = nil, all: Bool = false, prune: Bool? = true, tags: Bool = false, depth: Int? = nil, unshallow: Bool = false) -> OperationHandle<FetchResult> {
        start { progress in try await self.fetch(remote: remote, all: all, prune: prune, tags: tags, depth: depth, unshallow: unshallow, progress: progress) }
    }

    public func pullOperation(mode: PullMode, autostash: Bool = false, remote: String? = nil, branch: String? = nil) -> OperationHandle<PullResult> {
        start { progress in try await self.pull(mode: mode, autostash: autostash, remote: remote, branch: branch, progress: progress) }
    }

    public func pushOperation(remote: String? = nil, branch: String? = nil, force: PushForce = .none, setUpstream: Bool = false, tags: Bool = false, noVerify: Bool = false, pushOptions: [String] = []) -> OperationHandle<PushResult> {
        start { progress in try await self.push(remote: remote, branch: branch, force: force, setUpstream: setUpstream, tags: tags, noVerify: noVerify, pushOptions: pushOptions, progress: progress) }
    }

    public func fetchCommand(remote: String? = nil, all: Bool = false, prune: Bool? = true, tags: Bool = false, depth: Int? = nil, unshallow: Bool = false) -> GitCommand {
        SyncCommands.fetch(remote: all ? nil : (remote ?? defaultRemoteName()), all: all, prune: prune, tags: tags, depth: depth, unshallow: unshallow)
    }

    @discardableResult
    public func fetch(remote: String? = nil, all: Bool = false, prune: Bool? = true, tags: Bool = false, depth: Int? = nil, unshallow: Bool = false, progress: ProgressHandler? = nil) async throws -> FetchResult {
        try await perform("fetch") {
            let names = try await remoteNames()
            guard !names.isEmpty else { throw GitError(.remoteNotFound) }
            let target = all ? nil : (remote ?? defaultRemoteName(among: names))
            let before = try await remoteTips()
            try await runNetwork(SyncCommands.fetch(remote: target, all: all, prune: prune, tags: tags, depth: depth, unshallow: unshallow), progress: progress)
            let after = try await remoteTips()
            return try await fetchResult(remotes: all ? names : [target].compactMap { $0 }, before: before, after: after)
        }
    }

    public func pullCommand(mode: PullMode, autostash: Bool = false, remote: String? = nil, branch: String? = nil) -> GitCommand {
        SyncCommands.pull(mode: mode, autostash: autostash, remote: remote, branch: branch)
    }

    @discardableResult
    public func pull(mode: PullMode, autostash: Bool = false, remote: String? = nil, branch: String? = nil, progress: ProgressHandler? = nil) async throws -> PullResult {
        try await perform("pull") {
            let current = try await currentBranchName()
            let before = try await resolve("HEAD")
            var tracking: Tracking?
            if let current { tracking = try await upstream(of: current) }
            var command = SyncCommands.pull(mode: mode, autostash: autostash, remote: remote, branch: branch)
            let trace = HookTrace.attach(to: &command)
            defer { HookTrace.remove(trace) }
            do {
                try await runNetwork(command, progress: progress)
            } catch let error as GitError {
                throw HookTrace.refine(error, trace: trace)
            }
            let after = try await resolve("HEAD")
            let upstreamRef: String
            let upstreamName: String
            if let remote {
                upstreamRef = branch.map { "refs/remotes/" + remote + "/" + $0 } ?? "FETCH_HEAD"
                upstreamName = branch.map { remote + "/" + $0 } ?? remote
            } else {
                upstreamRef = tracking?.trackingRef ?? "FETCH_HEAD"
                upstreamName = tracking?.shortName ?? "FETCH_HEAD"
            }
            var pulled = 0
            var ahead = 0
            if let before {
                pulled = try await count([before.rawValue + ".." + upstreamRef])
                ahead = try await count([upstreamRef + ".." + before.rawValue])
            }
            let result = PullResult(branch: current ?? "HEAD", upstream: upstreamName, mode: mode, pulled: pulled, ahead: ahead, before: before, after: after)
            if let before, before != after, let current {
                let label = String(localized: "Pulled \(n(pulled, "commit")) into \(current)", bundle: .module)
                let detail = mode == .rebase ? String(localized: "Rebased onto \(upstreamName)", bundle: .module) : String(localized: "Merged \(upstreamName)", bundle: .module)
                let entry = UndoEntry(kind: .pull, label: label, detail: detail, head: "refs/heads/" + current, refsBefore: ["refs/heads/" + current: before])
                try await undo.record(entry)
                try? await undo.complete(entry.id)
            }
            return result
        }
    }

    public func pushCommand(remote: String? = nil, branch: String? = nil, force: PushForce = .none, setUpstream: Bool = false, tags: Bool = false, noVerify: Bool = false, pushOptions: [String] = []) async throws -> GitCommand {
        try await pushPlan(remote: remote, branch: branch, force: force, setUpstream: setUpstream, tags: tags, noVerify: noVerify, pushOptions: pushOptions).command
    }

    @discardableResult
    public func push(remote: String? = nil, branch: String? = nil, force: PushForce = .none, setUpstream: Bool = false, tags: Bool = false, noVerify: Bool = false, pushOptions: [String] = [], progress: ProgressHandler? = nil) async throws -> PushResult {
        try await perform("push") {
            let plan = try await pushPlan(remote: remote, branch: branch, force: force, setUpstream: setUpstream, tags: tags, noVerify: noVerify, pushOptions: pushOptions)
            let pending = try await pendingCount(local: plan.local, remote: plan.remote, remoteBranch: plan.remoteBranch)
            let result: GitResult
            do {
                result = try await runNetwork(plan.command, progress: progress)
            } catch let error as GitError {
                throw try await refinePushError(error, plan: plan, noVerify: noVerify)
            }
            return PushResult(
                remote: plan.remote,
                branch: plan.local,
                remoteBranch: plan.remoteBranch,
                pushed: pending,
                force: force,
                setUpstream: plan.setUpstream,
                publishedUpstream: plan.publishes,
                upToDate: result.errorOutput.contains("Everything up-to-date")
            )
        }
    }

    @discardableResult
    public func deleteRemoteBranch(remote: String, name: String) async throws -> ActionSummary {
        try await perform("push") {
            let tip = try await resolve("refs/remotes/" + remote + "/" + name)
            try await runNetwork(SyncCommands.deleteRemoteBranch(remote: remote, name: name), progress: nil)
            return ActionSummary(String(localized: "Deleted \(name) on \(remote)", bundle: .module), detail: tip.map { String(localized: "It pointed at \($0.short).", bundle: .module) })
        }
    }

    @discardableResult
    public func pushTag(name: String, remote: String? = nil) async throws -> ActionSummary {
        try await perform("push") {
            let names = try await remoteNames()
            guard let target = remote ?? defaultRemoteName(among: names) else { throw GitError(.remoteNotFound) }
            try await runNetwork(SyncCommands.pushTag(name: name, remote: target), progress: nil)
            return ActionSummary(String(localized: "Pushed tag \(name) to \(target)", bundle: .module))
        }
    }

    @discardableResult
    public func addRemote(name: String, url: String) async throws -> ActionSummary {
        try await perform("remote") {
            guard RemoteURL.isValid(url) else { throw GitError(.invalidURL) }
            try await git.run(SyncCommands.addRemote(name: name, url: url))
            return ActionSummary(String(localized: "Added remote \(name)", bundle: .module), detail: url)
        }
    }

    @discardableResult
    public func editRemote(name: String, newName: String? = nil, fetchURL: String? = nil, pushURL: String? = nil, prune: Bool? = nil) async throws -> ActionSummary {
        try await perform("remote") {
            if let fetchURL, !RemoteURL.isValid(fetchURL) { throw GitError(.invalidURL) }
            if let pushURL, !pushURL.isEmpty, !RemoteURL.isValid(pushURL) { throw GitError(.invalidURL) }
            let remotes = ConfigParser.remotes(try await git.run(ConfigParser.remotesCommand, background: true).stdout)
            guard let current = remotes.first(where: { $0.name == name }) else { throw GitError(.remoteNotFound) }
            var target = name
            if let newName, newName != name {
                try await git.run(SyncCommands.renameRemote(from: name, to: newName))
                target = newName
            }
            if let fetchURL, fetchURL != current.fetchURL {
                try await git.run(SyncCommands.setRemoteURL(name: target, url: fetchURL))
            }
            if let pushURL {
                if pushURL.isEmpty {
                    if current.pushURL != nil { try await git.run(SyncCommands.unsetRemotePushURL(name: target)) }
                } else if pushURL != current.pushURL {
                    try await git.run(SyncCommands.setRemoteURL(name: target, url: pushURL, push: true))
                }
            }
            if let prune, prune != current.prune {
                try await git.run(SyncCommands.setRemotePrune(name: target, prune: prune))
            }
            return ActionSummary(String(localized: "Saved remote \(target)", bundle: .module))
        }
    }

    @discardableResult
    public func removeRemote(name: String) async throws -> ActionSummary {
        try await perform("remote") {
            try await git.run(SyncCommands.removeRemote(name: name))
            return ActionSummary(String(localized: "Removed remote \(name)", bundle: .module))
        }
    }

    public func signIn(remote: String? = nil, username: String, token: String, helper: String? = nil) async throws {
        try await perform("signIn", refresh: false) {
            let remotes = ConfigParser.remotes(try await git.run(ConfigParser.remotesCommand, background: true).stdout)
            guard let entry = remotes.first(where: { $0.name == (remote ?? defaultRemoteName(among: remotes.map(\.name))) }) else { throw GitError(.remoteNotFound) }
            try await CredentialStore(git: git, helper: helper).approve(url: entry.pushURL ?? entry.fetchURL, username: username, password: token)
            snapshot?.network = .unknown
        }
    }

    public func signOut(remote: String? = nil, helper: String? = nil) async throws {
        try await perform("signIn", refresh: false) {
            let remotes = ConfigParser.remotes(try await git.run(ConfigParser.remotesCommand, background: true).stdout)
            guard let entry = remotes.first(where: { $0.name == (remote ?? defaultRemoteName(among: remotes.map(\.name))) }) else { throw GitError(.remoteNotFound) }
            try await CredentialStore(git: git, helper: helper).reject(url: entry.pushURL ?? entry.fetchURL)
        }
    }
}

struct Tracking: Sendable, Hashable {
    var remote: String
    var branch: String

    var trackingRef: String { "refs/remotes/" + remote + "/" + branch }
    var shortName: String { remote + "/" + branch }
}

struct PushPlan: Sendable {
    var local: String
    var remote: String
    var remoteBranch: String
    var setUpstream: Bool
    var publishes: Bool
    var command: GitCommand
}

extension RepositoryStore {
    @discardableResult
    func runNetwork(_ command: GitCommand, background: Bool = false, progress: ProgressHandler?) async throws -> GitResult {
        var forward: (@Sendable (String) -> Void)?
        if let progress {
            forward = { @Sendable line in
                if let parsed = ProgressParser.parse(line) { progress(parsed) }
            }
        }
        do {
            let result = try await git.run(command, background: background, progress: forward)
            noteNetwork(.ok)
            return result
        } catch let error as GitError {
            noteNetwork(after: error)
            throw error
        }
    }

    func noteNetwork(_ status: NetworkStatus) {
        guard snapshot?.network != status else { return }
        snapshot?.network = status
    }

    func noteNetwork(after error: GitError) {
        switch error.code {
        case .authFailed(let host): noteNetwork(.authFailed(host: host))
        case .networkUnreachable(let host): noteNetwork(.offline(host: host))
        default: break
        }
    }

    func remoteNames() async throws -> [String] {
        let output = try await git.run(.read(["remote"]), background: true).output
        return output.split(separator: "\n").map(String.init)
    }

    func defaultRemoteName(among names: [String]? = nil) -> String? {
        let names = names ?? snapshot?.remotes.map(\.name) ?? []
        return names.contains("origin") ? "origin" : names.first
    }

    func remoteTips() async throws -> [String: String] {
        let output = try await git.run(.read(["for-each-ref", "--format=%(refname)%09%(objectname)%09%(symref)", "refs/remotes"]), background: true).output
        var tips: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 2, fields.count < 3 || fields[2].isEmpty else { continue }
            tips[String(fields[0])] = String(fields[1])
        }
        return tips
    }

    func fetchResult(remotes: [String], before: [String: String], after: [String: String]) async throws -> FetchResult {
        var newCommits: [String: Int] = [:]
        var updated: [String] = []
        let oldTips = Array(Set(before.values)).sorted()
        for (ref, tip) in after.sorted(by: { $0.key < $1.key }) where before[ref] != tip {
            let name = String(ref.dropFirst("refs/remotes/".count))
            updated.append(name)
            if let old = before[ref] {
                newCommits[name] = try await count([old + ".." + tip])
            } else {
                newCommits[name] = try await count([tip, "--not"] + oldTips)
            }
        }
        let pruned = before.keys.filter { after[$0] == nil }.map { String($0.dropFirst("refs/remotes/".count)) }.sorted()
        let changedTips = Array(Set(updated.compactMap { after["refs/remotes/" + $0] })).sorted()
        let total = changedTips.isEmpty ? 0 : try await count(changedTips + ["--not"] + oldTips)
        return FetchResult(remotes: remotes, newCommits: newCommits, updatedRefs: updated, prunedRefs: pruned, total: total)
    }

    func count(_ arguments: [String]) async throws -> Int {
        let result = try await git.runAllowingFailure(.read(["rev-list", "--count"] + arguments), background: true)
        guard result.exitCode == 0 else { return 0 }
        return Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    func resolve(_ ref: String) async throws -> OID? {
        let result = try await git.runAllowingFailure(.read(["rev-parse", "--verify", "--quiet", ref + "^{commit}"]), background: true)
        guard result.exitCode == 0 else { return nil }
        return OID(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func currentBranchName() async throws -> String? {
        let result = try await git.runAllowingFailure(.read(["symbolic-ref", "--quiet", "--short", "HEAD"]), background: true)
        guard result.exitCode == 0 else { return nil }
        let name = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    func upstream(of branch: String) async throws -> Tracking? {
        let result = try await git.runAllowingFailure(.read(["for-each-ref", "--format=%(upstream:remotename)%09%(upstream:remoteref)", "refs/heads/" + branch]), background: true)
        guard result.exitCode == 0 else { return nil }
        let line = result.output.split(separator: "\n").first.map(String.init) ?? ""
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 2, !fields[0].isEmpty, fields[1].hasPrefix("refs/heads/") else { return nil }
        return Tracking(remote: fields[0], branch: String(fields[1].dropFirst("refs/heads/".count)))
    }

    func pushPlan(remote: String?, branch: String?, force: PushForce, setUpstream: Bool, tags: Bool, noVerify: Bool, pushOptions: [String]) async throws -> PushPlan {
        let local: String
        if let branch {
            local = branch
        } else if let current = try await currentBranchName() {
            local = current
        } else {
            throw GitError(.refNotFound)
        }
        let tracking = try await upstream(of: local)
        guard let target = remote ?? tracking?.remote else { throw GitError(.noUpstream) }
        let remoteBranch = tracking.flatMap { $0.remote == target ? $0.branch : nil } ?? local
        let publishes = tracking == nil
        let upstreamFlag = setUpstream || publishes
        let refspec = remoteBranch == local ? local : "refs/heads/" + local + ":refs/heads/" + remoteBranch
        let command = SyncCommands.push(remote: target, refspec: refspec, force: force, setUpstream: upstreamFlag, tags: tags, noVerify: noVerify, pushOptions: pushOptions)
        return PushPlan(local: local, remote: target, remoteBranch: remoteBranch, setUpstream: upstreamFlag, publishes: publishes, command: command)
    }

    func pendingCount(local: String, remote: String, remoteBranch: String) async throws -> Int {
        let tracking = "refs/remotes/" + remote + "/" + remoteBranch
        if try await resolve(tracking) != nil { return try await count([tracking + ".." + "refs/heads/" + local]) }
        return try await count(["refs/heads/" + local, "--not", "--remotes=" + remote])
    }

    func refinePushError(_ error: GitError, plan: PushPlan, noVerify: Bool) async throws -> GitError {
        switch error.code {
        case .pushRejected:
            let fetched = try? await git.run(SyncCommands.fetchBranch(remote: plan.remote, branch: plan.remoteBranch))
            guard fetched != nil else { return error }
            let behind = try await count(["refs/heads/" + plan.local + "..FETCH_HEAD"])
            return GitError(.pushRejected(behind: behind), result: error.result)
        case .unknown:
            let stderr = error.result?.errorOutput ?? ""
            guard !noVerify, stderr.contains("failed to push some refs"), !stderr.contains("[rejected]"), !stderr.contains("[remote rejected]") else { return error }
            let hooks = try await hooksDirectory()
            guard FileManager.default.isExecutableFile(atPath: hooks.appending(path: "pre-push").path(percentEncoded: false)) else { return error }
            let output = stderr.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.hasPrefix("error: failed to push some refs") && !$0.hasPrefix("hint: ") }.joined(separator: "\n")
            return GitError(.hookFailed(name: "pre-push", output: output.trimmingCharacters(in: .whitespacesAndNewlines)), result: error.result)
        default:
            return error
        }
    }

    func hooksDirectory() async throws -> URL {
        let path = try await git.run(.read(["rev-parse", "--path-format=absolute", "--git-path", "hooks"]), background: true).output.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(filePath: path, directoryHint: .isDirectory)
    }
}
