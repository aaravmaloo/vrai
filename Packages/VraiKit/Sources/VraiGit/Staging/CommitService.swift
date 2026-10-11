import Foundation

public struct CommitMessage: Sendable, Hashable, Codable {
    public var subject: String
    public var body: String

    public init(subject: String, body: String = "") {
        self.subject = subject
        self.body = body
    }

    public init(text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0).trimmingSuffix("\r") }
        var index = 0
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty { index += 1 }
        subject = index < lines.count ? lines[index] : ""
        index += 1
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty { index += 1 }
        body = index < lines.count ? lines[index...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    public var isEmpty: Bool { subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public var text: String {
        let summary = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return details.isEmpty ? summary + "\n" : summary + "\n\n" + details + "\n"
    }
}

extension GitError {
    public var commitMessage: CommitMessage? {
        guard let command = result?.command, command.subcommand == "commit", let stdin = command.stdin else { return nil }
        return CommitMessage(text: String(decoding: stdin, as: UTF8.self))
    }
}

public struct CommitService: Sendable {
    public struct HeadState: Sendable, Hashable {
        public var ref: String?
        public var tip: OID?
        public var merging: Bool

        public var undoHead: String? { ref ?? tip?.rawValue }
        public var undoRefs: [String: OID] {
            guard let tip else { return [:] }
            return [ref ?? "HEAD": tip]
        }
    }

    public let git: GitProcess

    public init(git: GitProcess) {
        self.git = git
    }

    public static let lastMessageCommand = GitCommand.read(["log", "-1", "--format=%B"])

    public static func command(_ message: CommitMessage, amend: Bool = false, signoff: Bool = false, noVerify: Bool = false) -> GitCommand {
        var arguments = ["commit", "-F", "-"]
        if amend { arguments.append("--amend") }
        if signoff { arguments.append("--signoff") }
        if noVerify { arguments.append("--no-verify") }
        return GitCommand(arguments, stdin: Data(message.text.utf8), risk: amend ? .rewrites : .safe, access: .write)
    }

    public func headState() async throws -> HeadState {
        let staging = StagingService(git: git)
        async let ref = staging.headRef()
        async let tip = staging.head()
        async let merge = git.run(.read(["rev-parse", "-q", "--verify", "MERGE_HEAD"], acceptedExitCodes: [0, 1]), background: true)
        return HeadState(ref: try await ref, tip: try await tip, merging: try await merge.exitCode == 0)
    }

    public func lastMessage() async throws -> CommitMessage? {
        guard try await StagingService(git: git).head() != nil else { return nil }
        return CommitMessage(text: try await git.run(Self.lastMessageCommand).output)
    }

    @discardableResult
    public func commit(_ message: CommitMessage, amend: Bool = false, signoff: Bool = false, noVerify: Bool = false) async throws -> OID {
        guard !message.isEmpty else { throw GitError(.emptyMessage) }
        var command = Self.command(message, amend: amend, signoff: signoff, noVerify: noVerify)
        let trace = HookTrace.attach(to: &command)
        defer { HookTrace.remove(trace) }
        let result = try await git.runAllowingFailure(command)
        guard result.succeeded else {
            if let hook = HookTrace.failedHook(in: trace) {
                let output = (result.errorOutput + result.output).trimmingCharacters(in: .whitespacesAndNewlines)
                throw GitError(.hookFailed(name: hook, output: output), result: result)
            }
            throw ErrorClassifier.classify(result)
        }
        guard let tip = try await StagingService(git: git).head() else { throw GitError(.unknown(exit: 0, stderr: result.errorOutput)) }
        return tip
    }
}
