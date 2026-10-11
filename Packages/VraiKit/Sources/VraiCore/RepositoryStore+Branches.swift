import Foundation
import VraiGit

public enum SwitchCarry: String, Sendable, Hashable, Codable, CaseIterable {
    case none
    case bring
    case stash
}

extension RepositoryStore {
    public func createBranchCommand(name: String, from: String? = nil, switchTo: Bool = true) -> GitCommand {
        BranchCommands.create(name: name, from: from, switchTo: switchTo)
    }

    @discardableResult
    public func createBranch(name: String, from: String? = nil, switchTo: Bool = true, publish: Bool = false, progress: ProgressHandler? = nil) async throws -> ActionSummary {
        try await perform("branch") {
            let start = from.flatMap { $0.isEmpty || $0 == "HEAD" ? nil : $0 }
            var origin = start ?? "HEAD"
            if start == nil, let head = try await resolve("HEAD") { origin = head.short }
            try await git.run(BranchCommands.create(name: name, from: start, switchTo: switchTo))
            let message = switchTo
                ? String(localized: "Created and switched to \(name)", bundle: .module)
                : String(localized: "Created branch \(name)", bundle: .module)
            var detail = String(localized: "From \(origin).", bundle: .module)
            if publish {
                let names = try await remoteNames()
                guard let remote = defaultRemoteName(among: names) else { throw GitError(.remoteNotFound) }
                try await runNetwork(SyncCommands.push(remote: remote, refspec: name, setUpstream: true), progress: progress)
                detail += " " + String(localized: "Set \(remote)/\(name) as the upstream.", bundle: .module)
            }
            return ActionSummary(message, detail: detail)
        }
    }

    @discardableResult
    public func switchTo(branch name: String, carry: SwitchCarry = .none) async throws -> ActionSummary {
        try await perform("switch") {
            let target = try await switchTarget(for: name)
            var stashed: OID?
            if carry == .stash {
                let before = try await resolve("refs/stash")
                try await git.run(BranchCommands.stashForSwitch())
                let after = try await resolve("refs/stash")
                if after != before { stashed = after }
            }
            do {
                switch target {
                case .local(let local):
                    try await git.run(BranchCommands.switchTo(local, merge: carry == .bring))
                case .track(let remoteBranch, _):
                    try await git.run(BranchCommands.track(remoteBranch, merge: carry == .bring))
                }
            } catch {
                if stashed != nil { _ = try? await git.run(.write(["stash", "pop", "--index"])) }
                throw error
            }
            switch target {
            case .track(let remoteBranch, let local):
                return ActionSummary(String(localized: "Switched to \(local)", bundle: .module), detail: String(localized: "Tracking \(remoteBranch).", bundle: .module))
            case .local(let local):
                let detail: String? = switch carry {
                case .stash: stashed == nil ? nil : String(localized: "Your changes are in stash@{0}.", bundle: .module)
                case .bring: String(localized: "Your changes came along.", bundle: .module)
                case .none: nil
                }
                return ActionSummary(String(localized: "Switched to \(local)", bundle: .module), detail: detail)
            }
        }
    }

    @discardableResult
    public func detach(at target: String) async throws -> ActionSummary {
        try await perform("switch") {
            try await git.run(BranchCommands.detach(at: target))
            let short = try await resolve("HEAD")?.short ?? target
            return ActionSummary(String(localized: "You're looking at \(short)", bundle: .module), detail: String(localized: "Not on a branch. Create one to keep commits you make here.", bundle: .module))
        }
    }

    public func unmergedCount(branch name: String) async throws -> Int {
        guard try await resolve("HEAD") != nil else { return 0 }
        return try await count(["refs/heads/" + name, "^HEAD"])
    }

    @discardableResult
    public func deleteBranch(name: String, force: Bool = false, alsoOnRemote: Bool = false) async throws -> ActionSummary {
        try await perform("deleteBranch") {
            let resolved = try await resolve("refs/heads/" + name)
            guard let tip = resolved else {
                try await git.run(BranchCommands.delete(name: name, force: force))
                throw GitError(.refNotFound)
            }
            let tracking = try await upstream(of: name)
            do {
                try await git.run(BranchCommands.delete(name: name, force: force))
            } catch let error as GitError {
                throw try await refineDeleteError(error, name: name)
            }
            let entry = UndoEntry(
                kind: .branchDelete,
                label: String(localized: "Deleted branch \(name)", bundle: .module),
                detail: String(localized: "Was at \(tip.short)", bundle: .module),
                refsBefore: ["refs/heads/" + name: tip]
            )
            try await undo.record(entry)
            try? await undo.complete(entry.id)
            var deletedOn: String?
            if alsoOnRemote, let tracking {
                try await runNetwork(SyncCommands.deleteRemoteBranch(remote: tracking.remote, name: tracking.branch), progress: nil)
                deletedOn = tracking.remote
            }
            let detail = deletedOn.map { String(localized: "Was at \(tip.short), also deleted on \($0).", bundle: .module) } ?? String(localized: "Was at \(tip.short).", bundle: .module)
            return ActionSummary(String(localized: "Deleted branch \(name)", bundle: .module), detail: detail)
        }
    }

    @discardableResult
    public func renameBranch(from: String, to: String) async throws -> ActionSummary {
        try await perform("renameBranch") {
            try await git.run(BranchCommands.rename(from: from, to: to))
            return ActionSummary(String(localized: "Renamed \(from) to \(to)", bundle: .module))
        }
    }

    @discardableResult
    public func setUpstream(branch: String, upstream: String?) async throws -> ActionSummary {
        try await perform("upstream") {
            if let upstream {
                try await git.run(BranchCommands.setUpstream(branch: branch, upstream: upstream))
                return ActionSummary(String(localized: "\(branch) now tracks \(upstream)", bundle: .module))
            }
            guard try await resolve("refs/heads/" + branch) != nil else { throw GitError(.refNotFound) }
            let configured = try await git.runAllowingFailure(.read(["config", "--get", "branch." + branch + ".merge"]), background: true)
            if configured.exitCode == 0 { try await git.run(BranchCommands.setUpstream(branch: branch, upstream: nil)) }
            return ActionSummary(String(localized: "\(branch) no longer tracks a remote branch", bundle: .module))
        }
    }

    public func createTagCommand(name: String, target: String? = nil, message: String? = nil, sign: Bool = false) -> GitCommand {
        BranchCommands.createTag(name: name, target: target, message: message, sign: sign)
    }

    @discardableResult
    public func createTag(name: String, target: String? = nil, message: String? = nil, sign: Bool = false) async throws -> ActionSummary {
        try await perform("tag") {
            try await git.run(BranchCommands.createTag(name: name, target: target, message: message, sign: sign))
            let short = try await resolve("refs/tags/" + name)?.short ?? name
            return ActionSummary(String(localized: "Tagged \(short) as \(name)", bundle: .module))
        }
    }

    @discardableResult
    public func deleteTag(name: String, alsoOnRemote: Bool = false, remote: String? = nil) async throws -> ActionSummary {
        try await perform("deleteTag") {
            let ref = "refs/tags/" + name
            let object = try await git.runAllowingFailure(.read(["rev-parse", "--verify", "--quiet", ref]), background: true)
            var entry: UndoEntry?
            if object.exitCode == 0, let value = OID(object.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                let target = try await resolve(ref) ?? value
                let recorded = UndoEntry(kind: .tagDelete, label: String(localized: "Deleted tag \(name)", bundle: .module), detail: String(localized: "Was at \(target.short)", bundle: .module), refsBefore: [ref: value])
                try await undo.record(recorded)
                entry = recorded
            }
            do {
                try await git.run(BranchCommands.deleteTag(name: name))
            } catch {
                if let entry { try? await undo.forget(entry.id) }
                throw error
            }
            if let entry { try? await undo.complete(entry.id) }
            if alsoOnRemote {
                let names = try await remoteNames()
                guard let target = remote ?? defaultRemoteName(among: names) else { throw GitError(.remoteNotFound) }
                try await runNetwork(SyncCommands.deleteRemoteTag(name: name, remote: target), progress: nil)
            }
            return ActionSummary(String(localized: "Deleted tag \(name)", bundle: .module))
        }
    }
}

enum SwitchTarget: Sendable, Hashable {
    case local(String)
    case track(remoteBranch: String, local: String)
}

extension RepositoryStore {
    func switchTarget(for name: String) async throws -> SwitchTarget {
        if try await resolve("refs/heads/" + name) != nil { return .local(name) }
        guard try await resolve("refs/remotes/" + name) != nil else { return .local(name) }
        let remotes = try await remoteNames().sorted { $0.count > $1.count }
        guard let remote = remotes.first(where: { name.hasPrefix($0 + "/") }) else { return .local(name) }
        let short = String(name.dropFirst(remote.count + 1))
        if try await resolve("refs/heads/" + short) != nil, let tracking = try await upstream(of: short), tracking.remote == remote, tracking.branch == short {
            return .local(short)
        }
        return .track(remoteBranch: name, local: short)
    }

    func refineDeleteError(_ error: GitError, name: String) async throws -> GitError {
        switch error.code {
        case .branchNotMerged:
            return GitError(.branchNotMerged(count: try await unmergedCount(branch: name)), result: error.result)
        case .isCurrentBranch:
            guard let path = error.result?.errorOutput.firstMatch(of: /used by worktree at '([^']+)'/).map({ String($0.output.1) }) else { return error }
            let own = try await git.run(.read(["rev-parse", "--show-toplevel"]), background: true).output.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.samePath(path, own) { return error }
            return GitError(.branchCheckedOutElsewhere(path: path), result: error.result)
        default:
            return error
        }
    }

    static func samePath(_ a: String, _ b: String) -> Bool {
        URL(filePath: a).resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            == URL(filePath: b).resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
