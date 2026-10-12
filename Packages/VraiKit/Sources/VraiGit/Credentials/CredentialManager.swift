import Foundation

public struct CredentialManager: Sendable, Hashable {
    public static let name = "git-credential-manager"
    public static let packagePath = "/usr/local/share/gcm-core/git-credential-manager"
    public static let standardLocations = [packagePath, "/opt/homebrew/bin/" + name, "/usr/local/bin/" + name]
    public static let installCommand = "brew install --cask git-credential-manager"
    public static let defaultURL = "https://github.com"

    public let executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    public var helperValue: String { executable.path(percentEncoded: false) }

    public static func locate(configured: [CredentialHelper] = [], candidates: [String], fileManager: FileManager = .default) -> CredentialManager? {
        let named = configured.filter { $0.kind == .manager && $0.name.hasPrefix("/") }.map(\.name)
        for path in named + candidates where fileManager.isExecutableFile(atPath: path) {
            return CredentialManager(executable: URL(filePath: path))
        }
        return nil
    }

    public static func searchPath(_ environment: [String: String]) -> [String] {
        (environment["PATH"] ?? "").split(separator: ":").map { String($0).trimmingSuffix("/") + "/" + name }
    }

    public static func isGitHub(host: String) -> Bool {
        let bare = (host.split(separator: ":").first.map(String.init) ?? host).lowercased()
        return bare == "github.com" || bare.hasSuffix(".ghe.com") || bare.hasPrefix("github.")
    }

    public static func hostURL(_ url: String) -> String? {
        guard let parsed = RemoteURL(url), parsed.kind == .network, let host = parsed.hostAndPort else { return nil }
        return (parsed.scheme ?? "https") + "://" + host
    }

    static func targets(_ url: String) -> [String] {
        guard let base = hostURL(url), base.lowercased() != defaultURL else { return [] }
        return ["--url", base]
    }

    public static let versionCommand = GitCommand(["credential-manager", "--version"], environment: ["GCM_INTERACTIVE": "never"])

    public static func listCommand(url: String) -> GitCommand {
        GitCommand(["credential-manager", "github", "list"] + targets(url), environment: ["GCM_INTERACTIVE": "never"])
    }

    public static func loginCommand(url: String) -> GitCommand {
        GitCommand(["credential-manager", "github", "login", "--url", hostURL(url) ?? defaultURL], access: .write, environment: ["GCM_GITHUB_AUTHMODES": "browser"])
    }

    public static func logoutCommand(account: String, url: String) -> GitCommand {
        GitCommand(["credential-manager", "github", "logout", account] + targets(url), risk: .destructive, access: .write, environment: ["GCM_INTERACTIVE": "never"])
    }

    public static func accounts(_ output: String, url: String) -> [String] {
        let wanted = hostURL(url)?.lowercased()
        var sections: [String?: [String]] = [:]
        var current: String?
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasSuffix(":") {
                let header = String(line.dropLast())
                current = (hostURL(header) ?? hostURL("https://" + header))?.lowercased()
                continue
            }
            guard !line.contains(" "), !line.contains("://") else { continue }
            sections[current, default: []].append(line)
        }
        var names = sections[wanted] ?? []
        if names.isEmpty, sections.keys.allSatisfy({ $0 == nil }) { names = sections[nil] ?? [] }
        var seen: Set<String> = []
        return names.filter { seen.insert($0.lowercased()).inserted }
    }

    public static func version(_ output: String) -> String? {
        let first = output.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let short = first.split(separator: "+").first.map(String.init) ?? first
        return short.isEmpty ? nil : short
    }
}

extension GitProcess {
    @discardableResult
    public nonisolated func runCredentialManager(_ manager: CredentialManager, _ command: GitCommand) async throws -> GitResult {
        guard command.arguments.first == "credential-manager" else { throw GitError(.gitNotFound) }
        let started = Date()
        let clock = ContinuousClock()
        let begin = clock.now
        let invocation = Invocation(
            executable: manager.executable,
            arguments: Array(command.arguments.dropFirst()),
            directory: workingDirectory,
            environment: environment.variables(for: command),
            stdin: command.stdin,
            progress: nil
        )
        let outcome: Invocation.Outcome
        do {
            outcome = try await invocation.run()
        } catch {
            throw GitError(.gitNotFound)
        }
        let result = GitResult(command: command, exitCode: outcome.status, stdout: outcome.stdout, stderr: outcome.stderr, startedAt: started, duration: clock.now - begin)
        forward(ConsoleEntry(source: .vrai, command: command.display, cwd: workingDirectory.path(percentEncoded: false), startedAt: started, duration: result.duration, exitCode: outcome.status, stdout: outcome.stdout, stderr: outcome.stderr, background: command.access == .read, cancelled: outcome.cancelled, acceptedExitCodes: command.acceptedExitCodes))
        if outcome.cancelled { throw GitError(.cancelled, result: result) }
        guard result.succeeded else { throw ErrorClassifier.classify(result) }
        return result
    }
}
