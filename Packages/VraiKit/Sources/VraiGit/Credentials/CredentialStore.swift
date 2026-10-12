import Foundation

public struct Credential: Sendable, Hashable {
    public var url: String
    public var username: String
    public var password: String

    public init(url: String, username: String, password: String) {
        self.url = url
        self.username = username
        self.password = password
    }

    public var host: String? { RemoteURL(url)?.hostAndPort }
}

public struct CredentialStore: Sendable {
    public let git: GitProcess
    public let helper: String?

    public init(git: GitProcess, helper: String? = nil) {
        self.git = git
        self.helper = helper
    }

    public static func storeHelper(file: URL) -> String {
        "store --file=" + file.path(percentEncoded: false)
    }

    public func approveCommand() -> GitCommand { command("approve") }
    public func rejectCommand() -> GitCommand { command("reject") }

    public func approve(_ credential: Credential) async throws {
        var command = approveCommand()
        command.stdin = try Self.input(url: credential.url, username: credential.username, password: credential.password)
        try await git.run(command)
    }

    public func approve(url: String, username: String, password: String) async throws {
        try await approve(Credential(url: url, username: username, password: password))
    }

    public func reject(url: String, username: String? = nil) async throws {
        var command = rejectCommand()
        command.stdin = try Self.input(url: url, username: username, password: nil)
        try await git.run(command)
    }

    public static let nonInteractive: [String: String] = [
        "GIT_ASKPASS": "/usr/bin/false",
        "SSH_ASKPASS": "/usr/bin/false",
        "GIT_TERMINAL_PROMPT": "0",
        "GCM_INTERACTIVE": "never"
    ]

    public func fillCommand(url: String, username: String? = nil) throws -> GitCommand {
        var command = self.command("fill", access: .read)
        command.stdin = try Self.input(url: url, username: username, password: nil)
        for (key, value) in Self.nonInteractive { command.environment[key] = value }
        command.hidesOutput = true
        return command
    }

    public func account(url: String, username: String? = nil) async throws -> String? {
        let result = try await git.runAllowingFailure(try fillCommand(url: url, username: username), background: true)
        guard result.exitCode == 0 else { return nil }
        return Self.username(in: result.stdout)
    }

    static func username(in output: Data) -> String? {
        let user = Array("username=".utf8)
        let secret = Array("password=".utf8)
        var name: String?
        var hasSecret = false
        for line in output.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            if line.starts(with: user) {
                name = String(decoding: line.dropFirst(user.count), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if line.starts(with: secret) {
                hasSecret = line.count > secret.count
            }
        }
        guard hasSecret, let name, !name.isEmpty else { return nil }
        return name
    }

    public func fill(url: String, username: String? = nil) async throws -> Credential? {
        let result = try await git.runAllowingFailure(try fillCommand(url: url, username: username), background: true)
        guard result.exitCode == 0 else { return nil }
        var fields: [String: String] = [:]
        for line in result.output.split(separator: "\n") {
            guard let equals = line.firstIndex(of: "=") else { continue }
            fields[String(line[..<equals])] = String(line[line.index(after: equals)...])
        }
        guard let name = fields["username"], let secret = fields["password"] else { return nil }
        return Credential(url: url, username: name, password: secret)
    }

    func command(_ action: String, access: GitCommand.Access = .write) -> GitCommand {
        var arguments: [String] = []
        if let helper { arguments += ["-c", "credential.helper=", "-c", "credential.helper=" + helper] }
        arguments += ["credential", action]
        return GitCommand(arguments, access: access)
    }

    static func input(url: String, username: String?, password: String?) throws -> Data {
        guard let parsed = RemoteURL(url), parsed.kind == .network || parsed.kind == .scp, let host = parsed.hostAndPort else { throw GitError(.invalidURL) }
        let clean: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var lines = ["protocol=" + (parsed.scheme ?? "https"), "host=" + host]
        let path = parsed.repositoryPath
        if !path.isEmpty, parsed.kind == .network { lines.append("path=" + String(parsed.path.drop { $0 == "/" })) }
        if let username, !clean(username).isEmpty { lines.append("username=" + clean(username)) }
        if let password { lines.append("password=" + clean(password)) }
        guard !lines.contains(where: { $0.contains("\n") || $0.contains("\0") }) else { throw GitError(.invalidURL) }
        return Data((lines.joined(separator: "\n") + "\n\n").utf8)
    }
}
