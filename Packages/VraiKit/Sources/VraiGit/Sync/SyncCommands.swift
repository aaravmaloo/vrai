import Foundation

public enum PushForce: String, Sendable, Hashable, Codable, CaseIterable {
    case none
    case withLease
    case force
}

public enum PullMode: String, Sendable, Hashable, Codable, CaseIterable {
    case merge
    case rebase
    case fastForwardOnly
}

public enum SyncCommands {
    public static func fetch(remote: String? = nil, all: Bool = false, prune: Bool? = true, tags: Bool = false, depth: Int? = nil, unshallow: Bool = false, progress: Bool = true) -> GitCommand {
        var arguments = ["fetch"]
        if all { arguments.append("--all") }
        if let prune { arguments.append(prune ? "--prune" : "--no-prune") }
        if tags { arguments.append("--tags") }
        if unshallow {
            arguments.append("--unshallow")
        } else if let depth {
            arguments += ["--depth", String(depth)]
        }
        if progress { arguments.append("--progress") }
        if !all, let remote { arguments.append(remote) }
        return make(arguments)
    }

    public static func fetchBranch(remote: String, branch: String) -> GitCommand {
        make(["fetch", remote, branch])
    }

    public static func backgroundFetch() -> GitCommand {
        make(["fetch", "--all"])
    }

    public static func pull(mode: PullMode, autostash: Bool = false, remote: String? = nil, branch: String? = nil, progress: Bool = true) -> GitCommand {
        var arguments = ["pull"]
        switch mode {
        case .merge: arguments.append("--no-rebase")
        case .rebase: arguments.append("--rebase")
        case .fastForwardOnly: arguments.append("--ff-only")
        }
        if autostash { arguments.append("--autostash") }
        if progress { arguments.append("--progress") }
        if let remote {
            arguments.append(remote)
            if let branch { arguments.append(branch) }
        }
        return make(arguments)
    }

    public static func push(remote: String, refspec: String?, force: PushForce = .none, setUpstream: Bool = false, tags: Bool = false, noVerify: Bool = false, pushOptions: [String] = [], progress: Bool = true) -> GitCommand {
        var arguments = ["push"]
        switch force {
        case .none: break
        case .withLease: arguments.append("--force-with-lease")
        case .force: arguments.append("--force")
        }
        if setUpstream { arguments.append("-u") }
        if tags { arguments.append("--follow-tags") }
        if noVerify { arguments.append("--no-verify") }
        for option in pushOptions where !option.isEmpty { arguments += ["-o", option] }
        if progress { arguments.append("--progress") }
        arguments.append(remote)
        if let refspec { arguments.append(refspec) }
        return make(arguments)
    }

    public static func deleteRemoteBranch(remote: String, name: String) -> GitCommand {
        make(["push", remote, "--delete", name])
    }

    public static func pushTag(name: String, remote: String) -> GitCommand {
        make(["push", remote, "refs/tags/" + name])
    }

    public static func deleteRemoteTag(name: String, remote: String) -> GitCommand {
        make(["push", remote, "--delete", "refs/tags/" + name])
    }

    public static func addRemote(name: String, url: String) -> GitCommand {
        make(["remote", "add", name, url])
    }

    public static func renameRemote(from: String, to: String) -> GitCommand {
        make(["remote", "rename", from, to])
    }

    public static func setRemoteURL(name: String, url: String, push: Bool = false) -> GitCommand {
        make(["remote", "set-url"] + (push ? ["--push"] : []) + [name, url])
    }

    public static func unsetRemotePushURL(name: String) -> GitCommand {
        make(["config", "--unset-all", "remote." + name + ".pushurl"])
    }

    public static func setRemotePrune(name: String, prune: Bool) -> GitCommand {
        make(["config", "remote." + name + ".prune", prune ? "true" : "false"])
    }

    public static func removeRemote(name: String) -> GitCommand {
        make(["remote", "remove", name])
    }

    static func make(_ arguments: [String]) -> GitCommand {
        GitCommand(arguments, risk: CommandParser.risk(sub: arguments[0], rest: Array(arguments.dropFirst())), access: .write)
    }
}

public enum BranchCommands {
    public static func create(name: String, from: String? = nil, switchTo: Bool) -> GitCommand {
        let start = from.flatMap { $0.isEmpty || $0 == "HEAD" ? nil : $0 }
        return SyncCommands.make((switchTo ? ["switch", "-c", name] : ["branch", name]) + (start.map { [$0] } ?? []))
    }

    public static func switchTo(_ name: String, merge: Bool = false) -> GitCommand {
        SyncCommands.make(["switch"] + (merge ? ["--merge"] : []) + [name])
    }

    public static func track(_ remoteBranch: String, merge: Bool = false) -> GitCommand {
        SyncCommands.make(["switch"] + (merge ? ["--merge"] : []) + ["--track", remoteBranch])
    }

    public static func detach(at target: String) -> GitCommand {
        SyncCommands.make(["switch", "--detach", target])
    }

    public static func stashForSwitch() -> GitCommand {
        SyncCommands.make(["stash", "push"])
    }

    public static func delete(name: String, force: Bool) -> GitCommand {
        SyncCommands.make(["branch", force ? "-D" : "-d", name])
    }

    public static func rename(from: String, to: String) -> GitCommand {
        SyncCommands.make(["branch", "-m", from, to])
    }

    public static func setUpstream(branch: String, upstream: String?) -> GitCommand {
        if let upstream { return SyncCommands.make(["branch", "--set-upstream-to=" + upstream, branch]) }
        return SyncCommands.make(["branch", "--unset-upstream", branch])
    }

    public static func createTag(name: String, target: String? = nil, message: String? = nil, sign: Bool = false) -> GitCommand {
        var arguments = ["tag"]
        if sign {
            arguments += ["-s", "-m", message ?? name]
        } else if let message {
            arguments += ["-a", "-m", message]
        }
        arguments.append(name)
        if let target, !target.isEmpty, target != "HEAD" { arguments.append(target) }
        return SyncCommands.make(arguments)
    }

    public static func deleteTag(name: String) -> GitCommand {
        SyncCommands.make(["tag", "-d", name])
    }
}
