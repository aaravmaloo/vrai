import Foundation
import Testing
@testable import VraiGit

final class EntryLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [ConsoleEntry] = []
    func append(_ entry: ConsoleEntry) { lock.withLock { entries.append(entry) } }
    var all: [ConsoleEntry] { lock.withLock { entries } }
}

struct GitProcessTests {
    static func scratchRepo() throws -> URL {
        let dir = TestSandbox.root.appending(path: "tests/process-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func process(at dir: URL, log: EntryLog? = nil) throws -> GitProcess {
        var observer: GitProcess.Observer?
        if let log {
            observer = { entry in log.append(entry) }
        }
        return GitProcess(executable: try GitExecutable.discover(), workingDirectory: dir, environment: TestSandbox.environment, observer: observer)
    }

    @Test(.timeLimit(.minutes(1)))
    func manyShortProcessesAllFinish() async throws {
        let git = try Self.process(at: TestSandbox.root)
        let finished = try await withThrowingTaskGroup(of: Int32.self) { group in
            for _ in 0..<1500 {
                group.addTask { try await git.runAllowingFailure(.read(["--version"])).exitCode }
            }
            var count = 0
            for try await code in group where code == 0 { count += 1 }
            return count
        }
        #expect(finished == 1500)
    }

    @Test func runsWithArgumentArraysAndReportsToTheConsole() async throws {
        let dir = try Self.scratchRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = EntryLog()
        let git = try Self.process(at: dir, log: log)
        try await git.run(.write(["init", "-q", "-b", "main"]))
        let result = try await git.run(.read(["rev-parse", "--is-inside-work-tree"]))
        #expect(result.output == "true\n")
        #expect(log.all.map(\.command) == ["git init -q -b main", "git rev-parse --is-inside-work-tree"])
        #expect(log.all.allSatisfy { $0.exitCode == 0 && $0.source == .vrai })
        #expect(log.all.first?.cwd == dir.path(percentEncoded: false))
    }

    @Test func failuresThrowClassifiedErrors() async throws {
        let dir = try Self.scratchRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        let git = try Self.process(at: dir)
        await #expect {
            try await git.run(.read(["status"]))
        } throws: { error in
            (error as? GitError)?.code == .notARepository
        }
        let tolerated = try await git.run(.read(["diff", "--no-index", "--", "/dev/null", "/dev/null"], acceptedExitCodes: [0, 1]))
        #expect(tolerated.exitCode == 0)
    }

    @Test func passesStdinAndKeepsShellCharactersLiteral() async throws {
        let dir = try Self.scratchRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        let git = try Self.process(at: dir)
        try await git.run(.write(["init", "-q"]))
        let hashed = try await git.run(GitCommand(["hash-object", "--stdin"], stdin: Data("hello\n".utf8)))
        #expect(hashed.output == "ce013625030ba8dba906f756967f9e9ca394464a\n")
        let marker = dir.appending(path: "x")
        try Data().write(to: marker)
        let typed = try #require(CommandParser.parse("git log; rm -rf x"))
        let result = try await git.runAllowingFailure(typed.command)
        #expect(result.exitCode != 0)
        #expect(result.errorOutput.contains("log;"))
        #expect(FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
    }

    @Test func usesTheSandboxEnvironmentAndCLocale() async throws {
        let dir = try Self.scratchRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        let git = try Self.process(at: dir)
        let global = try await git.run(.read(["config", "--global", "--show-origin", "--get", "user.name"], acceptedExitCodes: [0, 1]))
        #expect(global.exitCode == 1 || global.output.contains(TestSandbox.root.lastPathComponent))
        let variables = TestSandbox.environment.variables(for: .read(["status"]))
        #expect(variables["LC_ALL"] == "C")
        #expect(variables["GIT_OPTIONAL_LOCKS"] == "0")
        #expect(variables["GIT_TERMINAL_PROMPT"] == "0")
        #expect(variables["GIT_CONFIG_NOSYSTEM"] == "1")
        #expect(variables["HOME"]?.hasSuffix("vrai-sandbox/home") == true)
        #expect(variables["SSH_AUTH_SOCK"] == nil)
        #expect(TestSandbox.environment.variables(for: .write(["commit"]))["GIT_OPTIONAL_LOCKS"] == nil)
        #expect(variables["GIT_EDITOR"] == "true")
    }

    @Test func sandboxVariablesMatchTheShellScript() throws {
        let script = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "Scripts/sandbox-env.sh")
        let text = try String(contentsOf: script, encoding: .utf8)
        let exported = Set(text.matches(of: #/export ([A-Z_]+)=/#).map { String($0.output.1) })
        let swift = Set(GitEnvironment.sandboxVariables(root: URL(filePath: "/tmp/vrai-sandbox")).keys)
        #expect(swift.subtracting(exported).isEmpty)
        #expect(exported.subtracting(swift).subtracting(["VRAI_FIXTURE_NOW", "VRAI_AUTH_PORT"]).isEmpty)
    }

    @Test func writesRunOneAtATime() async throws {
        let dir = try Self.scratchRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = EntryLog()
        let git = try Self.process(at: dir, log: log)
        try await git.run(.write(["init", "-q"]))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<8 {
                group.addTask {
                    try await git.run(.write(["config", "vrai.test\(index)", "\(index)"]))
                }
            }
            try await group.waitForAll()
        }
        let writes = log.all.filter { $0.command.hasPrefix("git config vrai.test") }
        #expect(writes.count == 8)
        let sorted = writes.sorted { $0.startedAt < $1.startedAt }
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            #expect(a.startedAt.addingTimeInterval(Double(a.duration.components.seconds) + Double(a.duration.components.attoseconds) / 1e18) <= b.startedAt.addingTimeInterval(0.002))
        }
        let config = try await git.run(.read(["config", "--get-regexp", "^vrai\\.test"]))
        #expect(config.output.split(separator: "\n").count == 8)
    }

    @Test func cancellationInterruptsTheProcess() async throws {
        let dir = try Self.scratchRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appending(path: "slow-git")
        try Data("#!/bin/sh\nif [ \"$1\" = child ]; then sleep 30; exit 0; fi\ntrap 'exit 130' INT\n\"$0\" child &\nwait\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path(percentEncoded: false))
        let git = GitProcess(executable: GitExecutable(url: script, version: GitVersion(2, 54, 0)), workingDirectory: dir, environment: TestSandbox.environment)
        let started = ContinuousClock.now
        let task = Task { try await git.run(.read(["status"])) }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await #expect {
            try await task.value
        } throws: { error in
            (error as? GitError)?.code == .cancelled
        }
        #expect(ContinuousClock.now - started < .seconds(4))
        try await Task.sleep(for: .seconds(6))
        let survivors = Process()
        survivors.executableURL = URL(filePath: "/usr/bin/pgrep")
        survivors.arguments = ["-f", dir.lastPathComponent]
        let out = Pipe()
        survivors.standardOutput = out
        try survivors.run()
        survivors.waitUntilExit()
        #expect(out.fileHandleForReading.readDataToEndOfFile().isEmpty, "children of a cancelled git must not outlive it")
    }

    @Test func progressLinesStreamFromStderr() async throws {
        let dir = try Self.scratchRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appending(path: "progress-git")
        try Data("#!/bin/sh\nprintf 'Receiving objects:  10%% (1/10)\\rReceiving objects: 100%% (10/10), done.\\n' >&2\necho ok\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path(percentEncoded: false))
        let git = GitProcess(executable: GitExecutable(url: script, version: GitVersion(2, 54, 0)), workingDirectory: dir, environment: TestSandbox.environment)
        let lines = EntryLines()
        let result = try await git.run(.read(["fetch"]), progress: { lines.append($0) })
        #expect(result.output == "ok\n")
        #expect(lines.all.compactMap { ProgressParser.parse($0)?.percent } == [10, 100])
    }
}

final class EntryLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func append(_ line: String) { lock.withLock { lines.append(line) } }
    var all: [String] { lock.withLock { lines } }
}
