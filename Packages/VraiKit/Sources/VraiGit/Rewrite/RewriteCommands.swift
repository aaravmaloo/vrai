import Foundation

public enum MergeMode: String, Sendable, Hashable, Codable, CaseIterable {
    case auto
    case fastForwardOnly
    case mergeCommit
    case squash
}

public enum ResetMode: String, Sendable, Hashable, Codable, CaseIterable {
    case soft
    case mixed
    case hard
    case keep
}

public enum BisectVerdict: String, Sendable, Hashable, Codable, CaseIterable {
    case good
    case bad
    case skip
}

public enum MergeOutcome: Sendable, Hashable {
    case upToDate
    case fastForwarded(to: OID)
    case merged(commit: OID)
    case squashed
}

public enum RebaseOutcome: Sendable, Hashable {
    case upToDate
    case fastForwarded
    case rebased(commits: Int)
}

public enum BisectOutcome: Sendable, Hashable {
    case testing(current: OID?, remaining: Int?)
    case found(OID)
    case inconclusive(candidates: [OID])

    public static func parse(_ output: String) -> BisectOutcome {
        if let found = output.firstMatch(of: /(?m)^([0-9a-f]{40,64}) is the first '?bad'? commit/), let oid = OID(String(found.output.1)) {
            return .found(oid)
        }
        if output.contains("only 'skip'ped commits left to test") {
            let candidates = output.split(separator: "\n").compactMap { OID(String($0).trimmingCharacters(in: .whitespaces)) }
            return .inconclusive(candidates: candidates)
        }
        let remaining = output.firstMatch(of: /Bisecting: (\d+) revisions? left to test/).flatMap { Int($0.output.1) }
        let current = output.firstMatch(of: /(?m)^\[([0-9a-f]{40,64})\]/).flatMap { OID(String($0.output.1)) }
        return .testing(current: current, remaining: remaining)
    }
}

public struct RefUpdate: Sendable, Hashable {
    public var ref: String
    public var new: OID
    public var old: OID

    public init(ref: String, new: OID, old: OID) {
        self.ref = ref
        self.new = new
        self.old = old
    }

    public static func parse(_ output: String) -> [RefUpdate] {
        output.split(separator: "\n").compactMap { line in
            let words = line.split(separator: " ")
            guard words.count == 4, words[0] == "update", let new = OID(String(words[2])), let old = OID(String(words[3])) else { return nil }
            return RefUpdate(ref: String(words[1]), new: new, old: old)
        }
    }
}

public enum RewriteCommands {
    static func write(_ arguments: [String], stdin: Data? = nil, accepted: Set<Int32> = [0], editor: String? = nil, sequenceEditor: String? = nil) -> GitCommand {
        let risk = CommandParser.risk(sub: arguments.first ?? "", rest: Array(arguments.dropFirst()))
        return GitCommand(arguments, stdin: stdin, risk: risk, access: .write, acceptedExitCodes: accepted, editor: editor, sequenceEditor: sequenceEditor)
    }

    public static func merge(source: String, mode: MergeMode, message: String? = nil, strategyOption: String? = nil) -> GitCommand {
        var arguments = ["merge"]
        switch mode {
        case .auto: break
        case .fastForwardOnly: arguments.append("--ff-only")
        case .mergeCommit: arguments.append("--no-ff")
        case .squash: arguments.append("--squash")
        }
        if let strategyOption, !strategyOption.isEmpty { arguments += ["-X", strategyOption] }
        if let message, !message.isEmpty, mode != .squash, mode != .fastForwardOnly { arguments += ["-m", message] }
        arguments.append(source)
        return write(arguments)
    }

    public static func checkout(_ choice: ConflictChoice, path: String) -> GitCommand {
        write(["checkout", choice == .theirs ? "--theirs" : "--ours", "--", path])
    }

    public static func remove(path: String) -> GitCommand {
        write(["rm", "--quiet", "--", path])
    }

    public static func add(path: String) -> GitCommand {
        write(["add", "--", path])
    }

    public static func unmergedStages(path: String) -> GitCommand {
        .read(["ls-files", "-u", "-z", "--", path])
    }

    public static func mergeFile(ours: OID, base: OID, theirs: OID) -> GitCommand {
        .read(["merge-file", "-p", "--zdiff3", "--object-id", ours.rawValue, base.rawValue, theirs.rawValue], acceptedExitCodes: Set(0...127))
    }

    public static func abort(_ operation: OperationInProgress) -> GitCommand {
        switch operation {
        case .merge: write(["merge", "--abort"])
        case .rebase: write(["rebase", "--abort"])
        case .applyingPatches: write(["am", "--abort"])
        case .cherryPick: write(["cherry-pick", "--abort"])
        case .revert: write(["revert", "--abort"])
        case .bisect: endBisect
        }
    }

    public static func continueOperation(_ operation: OperationInProgress, editor: String? = nil) -> GitCommand? {
        switch operation {
        case .merge: write(["merge", "--continue"])
        case .rebase: write(["rebase", "--continue"], editor: editor)
        case .applyingPatches: write(["am", "--continue"])
        case .cherryPick: write(["cherry-pick", "--continue"])
        case .revert: write(["revert", "--continue"])
        case .bisect: nil
        }
    }

    public static func skip(_ operation: OperationInProgress, editor: String? = nil) -> GitCommand? {
        switch operation {
        case .rebase: write(["rebase", "--skip"], editor: editor)
        case .applyingPatches: write(["am", "--skip"])
        case .cherryPick: write(["cherry-pick", "--skip"])
        case .revert: write(["revert", "--skip"])
        case .merge, .bisect: nil
        }
    }

    public static func rebase(onto: String, autostash: Bool = false, updateRefs: Bool = false, rebaseMerges: Bool = false) -> GitCommand {
        var arguments = ["rebase"]
        if autostash { arguments.append("--autostash") }
        if updateRefs { arguments.append("--update-refs") }
        if rebaseMerges { arguments.append("--rebase-merges") }
        arguments.append(onto)
        return write(arguments)
    }

    public static func interactiveRebase(onto: String, sequenceEditor: String? = nil, editor: String? = nil) -> GitCommand {
        write(["rebase", "-i", onto], editor: editor, sequenceEditor: sequenceEditor)
    }

    public static func replay(onto: String, branch: String, contained: Bool = false, printRefs: Bool = true) -> GitCommand {
        var arguments = ["replay"]
        if contained { arguments.append("--contained") }
        if printRefs { arguments.append("--ref-action=print") }
        arguments += ["--onto", onto, onto + ".." + branch]
        return write(arguments)
    }

    public static func updateRefs(_ updates: [RefUpdate], reason: String) -> GitCommand {
        let lines = updates.map { "update \($0.ref) \($0.new.rawValue) \($0.old.rawValue)\n" }.joined()
        return write(["update-ref", "-m", reason, "--stdin"], stdin: Data(lines.utf8))
    }

    public static let refreshIndex = write(["update-index", "-q", "--refresh"], accepted: [0, 1])

    public static func moveWorktree(from old: OID, to new: OID) -> GitCommand {
        write(["read-tree", "-m", "-u", old.rawValue, new.rawValue])
    }

    public static func cherryPick(ids: [OID], recordOrigin: Bool = false, noCommit: Bool = false, mainline: Int? = nil) -> GitCommand {
        var arguments = ["cherry-pick"]
        if recordOrigin { arguments.append("-x") }
        if noCommit { arguments.append("--no-commit") }
        if let mainline { arguments += ["-m", String(mainline)] }
        arguments += ids.map(\.rawValue)
        return write(arguments)
    }

    public static func revert(id: OID, noCommit: Bool = false, mainline: Int? = nil) -> GitCommand {
        var arguments = ["revert", "--no-edit"]
        if noCommit { arguments.append("--no-commit") }
        if let mainline { arguments += ["-m", String(mainline)] }
        arguments.append(id.rawValue)
        return write(arguments)
    }

    public static func reset(to target: String, mode: ResetMode) -> GitCommand {
        write(["reset", "--" + mode.rawValue, target])
    }

    public static let stashCreate = write(["stash", "create"])

    public static func stash(message: String? = nil, includeUntracked: Bool = false, keepIndex: Bool = false, onlyStaged: Bool = false, paths: [String] = []) -> GitCommand {
        var arguments = ["stash", "push"]
        if includeUntracked { arguments.append("--include-untracked") }
        if keepIndex { arguments.append("--keep-index") }
        if onlyStaged { arguments.append("--staged") }
        if let message, !message.isEmpty { arguments += ["-m", message] }
        if !paths.isEmpty { arguments += ["--"] + paths }
        return write(arguments)
    }

    public static func applyStash(index: Int, pop: Bool = false, restoreIndex: Bool = false) -> GitCommand {
        var arguments = ["stash", pop ? "pop" : "apply"]
        if restoreIndex { arguments.append("--index") }
        arguments.append("stash@{\(index)}")
        return write(arguments)
    }

    public static func dropStash(index: Int) -> GitCommand {
        write(["stash", "drop", "stash@{\(index)}"])
    }

    public static func branchFromStash(index: Int, name: String) -> GitCommand {
        write(["stash", "branch", name, "stash@{\(index)}"])
    }

    public static func startBisect(bad: String, good: String) -> GitCommand {
        write(["bisect", "start", bad, good])
    }

    public static func markBisect(_ verdict: BisectVerdict) -> GitCommand {
        write(["bisect", verdict.rawValue], accepted: [0, 2])
    }

    public static let endBisect = write(["bisect", "reset"])
}
