import Foundation
import Synchronization
import Testing
@testable import VraiCore
@testable import VraiGit

struct ScenarioCopy {
    let scenario: String
    let root: URL

    var repository: URL { root.appending(path: "vrai", directoryHint: .isDirectory) }
    var remotes: URL { root.appending(path: "remotes", directoryHint: .isDirectory) }

    func remote(_ name: String) -> URL { remotes.appending(path: name + ".git", directoryHint: .isDirectory) }

    func process(at url: URL? = nil, environment: GitEnvironment? = nil, observer: GitProcess.Observer? = nil) throws -> GitProcess {
        GitProcess(executable: try GitExecutable.discover(), workingDirectory: url ?? repository, environment: environment ?? .sandbox(root: Sandbox.root), observer: observer)
    }

    @MainActor
    func store(environment: GitEnvironment? = nil, observer: GitProcess.Observer? = nil) async throws -> RepositoryStore {
        let store = RepositoryStore(git: try process(environment: environment, observer: observer))
        try await store.refresh()
        return store
    }

    func git(_ arguments: [String], in url: URL? = nil) async throws -> String {
        let result = try await process(at: url).run(GitCommand(arguments, access: .write))
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func gitAllowingFailure(_ arguments: [String], in url: URL? = nil) async throws -> GitResult {
        try await process(at: url).runAllowingFailure(GitCommand(arguments, access: .write))
    }

    func tip(_ ref: String, in url: URL? = nil) async throws -> String? {
        let result = try await gitAllowingFailure(["rev-parse", "--verify", "--quiet", ref + "^{commit}"], in: url)
        guard result.exitCode == 0 else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func remoteTip(_ remote: String, _ ref: String) async throws -> String? {
        try await tip(ref, in: self.remote(remote))
    }

    func clone(_ remote: String, branch: String? = nil) async throws -> URL {
        let target = root.appending(path: "clone-" + UUID().uuidString.prefix(8), directoryHint: .isDirectory)
        var arguments = ["clone", "-q"]
        if let branch { arguments += ["--branch", branch] }
        arguments += ["file://" + self.remote(remote).path(percentEncoded: false), target.path(percentEncoded: false)]
        _ = try await git(arguments, in: root)
        return target
    }

    func commit(in url: URL, file: String, contents: String, message: String) async throws -> String {
        let path = url.appending(path: file)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: path)
        _ = try await git(["add", "--", file], in: url)
        _ = try await git(["commit", "-q", "--no-gpg-sign", "-m", message], in: url)
        return try await tip("HEAD", in: url) ?? ""
    }

    func remove() {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    static func make(_ scenario: String) throws -> ScenarioCopy {
        let fm = FileManager.default
        let source = Sandbox.root.appending(path: "fixtures/" + scenario, directoryHint: .isDirectory)
        let holder = Sandbox.root.appending(path: "tests/" + UUID().uuidString.prefix(12).lowercased(), directoryHint: .isDirectory)
        try fm.createDirectory(at: holder, withIntermediateDirectories: true)
        let root = holder.appending(path: scenario, directoryHint: .isDirectory)
        try fm.copyItem(at: source, to: root)
        let copy = ScenarioCopy(scenario: scenario, root: root)
        try copy.relink(from: source)
        return copy
    }

    private func relink(from source: URL) throws {
        let fm = FileManager.default
        let original = source.path(percentEncoded: false).trimmingSuffix("/")
        let replacement = root.path(percentEncoded: false).trimmingSuffix("/")
        var pairs = [(original, replacement)]
        if original.hasPrefix("/var/") { pairs.insert(("/private" + original, "/private" + replacement), at: 0) }
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: []) else { return }
        for case let url as URL in walker {
            let name = url.lastPathComponent
            let path = url.path(percentEncoded: false)
            let inGitDir = path.contains("/.git/")
            let candidate = (name == ".git") || (inGitDir && (name == "config" || name == "gitdir"))
            guard candidate, (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            guard var text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let before = text
            for (from, to) in pairs { text = text.replacingOccurrences(of: from, with: to) }
            if text != before { try Data(text.utf8).write(to: url) }
        }
    }
}

enum AuthServer {
    static let state = Mutex<(count: Int, process: Process?)>((0, nil))

    static var script: URL {
        URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../Scripts/auth-server.py").standardizedFileURL
    }

    static var python: URL? {
        ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"].map { URL(filePath: $0) }.first { FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false)) }
    }

    static func port(in copy: ScenarioCopy) throws -> Int {
        let config = try String(contentsOf: copy.repository.appending(path: ".git/config"), encoding: .utf8)
        guard let match = config.firstMatch(of: /url = http:\/\/127\.0\.0\.1:(\d+)\//), let port = Int(match.output.1) else {
            throw GitError(.unknown(exit: 1, stderr: "the auth fixture has no local http remote"))
        }
        return port
    }

    static func with<T>(port: Int, _ body: () async throws -> T) async throws -> T {
        try await acquire(port: port)
        do {
            let value = try await body()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }

    static func acquire(port: Int) async throws {
        let needsStart = state.withLock { state -> Bool in
            state.count += 1
            return state.process == nil
        }
        guard needsStart else {
            try await waitUntilListening(port: port)
            return
        }
        guard let python else { throw GitError(.unknown(exit: 1, stderr: "python3 is missing")) }
        let process = Process()
        process.executableURL = python
        process.arguments = [script.path(percentEncoded: false), "--port", String(port)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        state.withLock { $0.process = process }
        try await waitUntilListening(port: port)
    }

    static func release() {
        let stopping = state.withLock { state -> Process? in
            state.count -= 1
            guard state.count == 0, let process = state.process else { return nil }
            state.process = nil
            return process
        }
        if let stopping {
            stopping.terminate()
            stopping.waitUntilExit()
        }
    }

    static func waitUntilListening(port: Int) async throws {
        for _ in 0..<100 {
            if canConnect(port: port) { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw GitError(.unknown(exit: 1, stderr: "auth-server.py did not start on port \(port)"))
    }

    static func canConnect(port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        return result == 0
    }
}

enum AskpassHelper {
    static let built = Mutex<URL?>(nil)

    static var source: URL {
        URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../Helpers/vrai-askpass/main.swift").standardizedFileURL
    }

    static func binary() throws -> URL {
        if let existing = built.withLock({ $0 }) { return existing }
        let code = try Data(contentsOf: source)
        var hash: UInt64 = 1469598103934665603
        for byte in code { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        let directory = Sandbox.root.appending(path: "bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appending(path: "vrai-askpass-" + String(hash, radix: 16))
        return try built.withLock { cached -> URL in
            if let cached { return cached }
            if !FileManager.default.isExecutableFile(atPath: output.path(percentEncoded: false)) {
                let partial = directory.appending(path: "vrai-askpass-" + UUID().uuidString)
                let process = Process()
                process.executableURL = URL(filePath: "/usr/bin/xcrun")
                process.arguments = ["swiftc", "-swift-version", "6", "-warnings-as-errors", "-O", source.path(percentEncoded: false), "-o", partial.path(percentEncoded: false)]
                let errors = Pipe()
                process.standardError = errors
                process.standardOutput = FileHandle.nullDevice
                try process.run()
                let message = errors.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    throw GitError(.unknown(exit: process.terminationStatus, stderr: String(decoding: message, as: UTF8.self)))
                }
                try FileManager.default.moveItem(at: partial, to: output)
            }
            cached = output
            return output
        }
    }
}

func waitFor(_ timeout: Duration = .seconds(10), _ condition: @Sendable () async -> Bool) async throws -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() { return true }
        try await Task.sleep(for: .milliseconds(25))
    }
    return await condition()
}

extension ScenarioCopy {
    var credentialFile: URL { root.appending(path: "git-credentials") }

    func isolatedEnvironment(seed: String? = nil, helper: Bool = true) throws -> GitEnvironment {
        var environment = GitEnvironment.sandbox(root: Sandbox.root)
        if helper {
            try Data((seed ?? "").utf8).write(to: credentialFile)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialFile.path(percentEncoded: false))
            environment.base["GIT_CONFIG_COUNT"] = "2"
            environment.base["GIT_CONFIG_KEY_0"] = "credential.helper"
            environment.base["GIT_CONFIG_VALUE_0"] = ""
            environment.base["GIT_CONFIG_KEY_1"] = "credential.helper"
            environment.base["GIT_CONFIG_VALUE_1"] = CredentialStore.storeHelper(file: credentialFile)
        } else {
            environment.base["GIT_CONFIG_COUNT"] = "1"
            environment.base["GIT_CONFIG_KEY_0"] = "credential.helper"
            environment.base["GIT_CONFIG_VALUE_0"] = ""
        }
        return environment
    }

    func clean() async throws {
        _ = try await git(["reset", "-q", "--hard"])
        _ = try await git(["clean", "-q", "-fd"])
    }

    func setHook(_ name: String, _ body: String?, in directory: URL? = nil) throws {
        let hooks = directory ?? repository.appending(path: ".git/hooks", directoryHint: .isDirectory)
        let path = hooks.appending(path: name)
        if let body {
            try Data(body.utf8).write(to: path)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path(percentEncoded: false))
        } else if FileManager.default.fileExists(atPath: path.path(percentEncoded: false)) {
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path.path(percentEncoded: false))
        }
    }

    func config(_ key: String, in url: URL? = nil) async throws -> String? {
        let result = try await gitAllowingFailure(["config", "--get", key], in: url)
        guard result.exitCode == 0 else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

actor Recorder<Value: Sendable> {
    private(set) var values: [Value] = []

    func append(_ value: Value) { values.append(value) }
}

final class ConsoleRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ConsoleEntry] = []

    var entries: [ConsoleEntry] { lock.withLock { stored } }

    var observer: GitProcess.Observer {
        { [weak self] entry in self?.lock.withLock { self?.stored.append(entry) } }
    }
}

@MainActor
@discardableResult
func expectCode(_ expected: String, sourceLocation: SourceLocation = #_sourceLocation, _ body: () async throws -> Void) async -> GitError? {
    do {
        try await body()
        Issue.record("expected GitError.\(expected), but nothing was thrown", sourceLocation: sourceLocation)
        return nil
    } catch let error as GitError {
        #expect(error.code.name == expected, "\(error)", sourceLocation: sourceLocation)
        return error
    } catch {
        Issue.record("expected GitError.\(expected), got \(error)", sourceLocation: sourceLocation)
        return nil
    }
}
