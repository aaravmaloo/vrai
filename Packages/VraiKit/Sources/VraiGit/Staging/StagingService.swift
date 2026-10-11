import Foundation

public struct StagingService: Sendable {
    public enum LineAction: Sendable, Hashable {
        case stage
        case unstage
        case discard
    }

    public let git: GitProcess

    public init(git: GitProcess) {
        self.git = git
    }

    static let literal = ["GIT_LITERAL_PATHSPECS": "1"]

    static func write(_ arguments: [String], stdin: Data? = nil, risk: GitCommand.Risk = .safe, paths: Bool = true) -> GitCommand {
        var command = GitCommand.write(arguments, stdin: stdin, risk: risk)
        if paths { command.environment = literal }
        return command
    }

    static func read(_ arguments: [String], acceptedExitCodes: Set<Int32> = [0]) -> GitCommand {
        var command = GitCommand.read(arguments, acceptedExitCodes: acceptedExitCodes)
        command.environment = literal
        return command
    }

    public static func stageCommand(paths: [String]) -> GitCommand {
        write(["add", "--"] + paths)
    }

    public static func unstageCommand(paths: [String], unborn: Bool) -> GitCommand {
        unborn ? write(["rm", "--cached", "-f", "-q", "--ignore-unmatch", "--"] + paths) : write(["restore", "--staged", "--"] + paths)
    }

    public static func stageAllCommand(includeUntracked: Bool) -> GitCommand {
        write(["add", includeUntracked ? "-A" : "-u"], paths: false)
    }

    public static func unstageAllCommand(unborn: Bool) -> GitCommand {
        unborn ? write(["rm", "-r", "--cached", "-f", "-q", "--ignore-unmatch", "--", "."]) : write(["restore", "--staged", "--", "."])
    }

    public static func discardTrackedCommand(paths: [String]) -> GitCommand {
        write(["restore", "--worktree", "--"] + paths, risk: .destructive)
    }

    public static func cleanCommand(paths: [String]) -> GitCommand {
        write(["clean", "-f", "--"] + paths, risk: .destructive)
    }

    public static func restoreCommand(path: String, source: String) -> GitCommand {
        write(["restore", "--source=" + source, "--worktree", "--", path], risk: .destructive)
    }

    public static func applyCommand(_ patch: Data, cached: Bool, reverse: Bool) -> GitCommand {
        var arguments = ["apply"]
        if cached { arguments.append("--cached") }
        if reverse { arguments.append("--reverse") }
        arguments += ["--recount", "--unidiff-zero", "-"]
        return write(arguments, stdin: patch, risk: !cached && reverse ? .destructive : .safe, paths: false)
    }

    public static func diffCommand(path: String, oldPath: String?, staged: Bool, untracked: Bool, renameThreshold: Int = 50) -> GitCommand {
        if untracked, !staged {
            return read(["diff", "--no-index", "--no-color", "--no-ext-diff", "--", "/dev/null", path], acceptedExitCodes: [0, 1])
        }
        if staged {
            let paths = [oldPath, path].compactMap { $0 }
            return read(["diff", "--cached", "--no-color", "--no-ext-diff", "--find-renames=\(renameThreshold)%", "--"] + paths)
        }
        return read(["diff", "--no-color", "--no-ext-diff", "--", path])
    }

    public static func lineCommand(_ selection: LineSelection, action: LineAction) throws -> GitCommand? {
        let expected: LineSelection.Side = action == .unstage ? .staged : .unstaged
        guard selection.side == expected, PatchBuilder.canBuild(for: selection.file) else { throw GitError(.patchDoesNotApply) }
        guard let patch = PatchBuilder.patch(for: selection, reverse: action != .stage) else { return nil }
        return applyCommand(patch, cached: action != .discard, reverse: action != .stage)
    }

    public static let headCommand = GitCommand.read(["rev-parse", "-q", "--verify", "HEAD^{commit}"], acceptedExitCodes: [0, 1])
    public static let symbolicHeadCommand = GitCommand.read(["symbolic-ref", "-q", "HEAD"], acceptedExitCodes: [0, 1])

    public func head() async throws -> OID? {
        let result = try await git.run(Self.headCommand, background: true)
        return OID(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func isUnborn() async throws -> Bool {
        try await head() == nil
    }

    public func headRef() async throws -> String? {
        let result = try await git.run(Self.symbolicHeadCommand, background: true)
        let name = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.exitCode == 0 && !name.isEmpty ? name : nil
    }

    public func trackedPaths(_ paths: [String]) async throws -> Set<String> {
        guard !paths.isEmpty else { return [] }
        let data = try await git.run(Self.read(["ls-files", "-z", "--"] + paths), background: true).stdout
        return Set(ParseSupport.nulFields(data).filter { !$0.isEmpty })
    }

    public func diff(path: String, oldPath: String? = nil, staged: Bool, untracked: Bool, renameThreshold: Int = 50) async throws -> FileDiff? {
        let data = try await git.run(Self.diffCommand(path: path, oldPath: oldPath, staged: staged, untracked: untracked, renameThreshold: renameThreshold), background: true).stdout
        let files = PatchParser.parse(data)
        return files.first { $0.path == path } ?? files.first
    }

    @discardableResult
    public func apply(_ selection: LineSelection, action: LineAction) async throws -> GitResult? {
        guard let command = try Self.lineCommand(selection, action: action) else { return nil }
        return try await git.run(command)
    }
}
