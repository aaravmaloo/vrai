import Foundation

public actor GitProcess {
    public typealias Observer = @Sendable (ConsoleEntry) -> Void

    public nonisolated let executable: GitExecutable
    public nonisolated let workingDirectory: URL
    public nonisolated let environment: GitEnvironment
    private nonisolated let observer: Observer?
    private var writing = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    public static let implicitArguments = ["-c", "core.quotepath=false"]

    public init(executable: GitExecutable, workingDirectory: URL, environment: GitEnvironment, observer: Observer? = nil) {
        self.executable = executable
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.observer = observer
    }

    @discardableResult
    public func run(_ command: GitCommand, source: ConsoleEntry.Source = .vrai, background: Bool = false, progress: (@Sendable (String) -> Void)? = nil) async throws -> GitResult {
        let result = try await runAllowingFailure(command, source: source, background: background, progress: progress)
        guard result.succeeded else { throw ErrorClassifier.classify(result) }
        return result
    }

    public func runAllowingFailure(_ command: GitCommand, source: ConsoleEntry.Source = .vrai, background: Bool = false, progress: (@Sendable (String) -> Void)? = nil) async throws -> GitResult {
        if command.access == .write { await acquireWrite() }
        defer { if command.access == .write { releaseWrite() } }
        try Task.checkCancellation()
        let started = Date()
        let clock = ContinuousClock()
        let begin = clock.now
        let invocation = Invocation(
            executable: executable.url,
            arguments: Self.implicitArguments + command.arguments,
            directory: workingDirectory,
            environment: environment.variables(for: command),
            stdin: command.stdin,
            progress: progress
        )
        do {
            let outcome = try await invocation.run()
            let result = GitResult(command: command, exitCode: outcome.status, stdout: outcome.stdout, stderr: outcome.stderr, startedAt: started, duration: clock.now - begin)
            report(ConsoleEntry(source: source, command: command.display, cwd: workingDirectory.path(percentEncoded: false), startedAt: started, duration: result.duration, exitCode: outcome.status, stdout: outcome.stdout, stderr: outcome.stderr, background: background, cancelled: outcome.cancelled))
            if outcome.cancelled { throw GitError(.cancelled, result: result) }
            return result
        } catch let error as GitError {
            throw error
        } catch {
            report(ConsoleEntry(source: source, command: command.display, cwd: workingDirectory.path(percentEncoded: false), startedAt: started, duration: clock.now - begin, exitCode: nil, stdout: Data(), stderr: Data(String(describing: error).utf8), background: background))
            throw GitError(.gitNotFound)
        }
    }

    public func output(_ arguments: [String], acceptedExitCodes: Set<Int32> = [0]) async throws -> Data {
        try await run(.read(arguments, acceptedExitCodes: acceptedExitCodes), background: true).stdout
    }

    private nonisolated func report(_ entry: ConsoleEntry) {
        observer?(entry)
    }

    nonisolated func forward(_ entry: ConsoleEntry) {
        observer?(entry)
    }

    private func acquireWrite() async {
        if !writing {
            writing = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func releaseWrite() {
        if waiting.isEmpty {
            writing = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}

struct Invocation: Sendable {
    struct Outcome: Sendable {
        var status: Int32
        var stdout: Data
        var stderr: Data
        var cancelled: Bool
    }

    let executable: URL
    let arguments: [String]
    let directory: URL
    let environment: [String: String]
    let stdin: Data?
    let progress: (@Sendable (String) -> Void)?

    static let interruptGrace: Duration = .seconds(2)
    static let terminateGrace: Duration = .seconds(5)

    func run() async throws -> Outcome {
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Outcome, Error>) in
                box.start(self, continuation: continuation)
            }
        } onCancel: {
            box.cancel()
        }
    }
}

final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private let spawned = SpawnedProcess()
    private var stdout = Data()
    private var stderr = Data()
    private var stderrLine = Data()
    private var pending = 3
    private var status: Int32 = -1
    private var cancelled = false
    private var started = false
    private var exited = false
    private var continuation: CheckedContinuation<Invocation.Outcome, Error>?
    private var progress: (@Sendable (String) -> Void)?

    static let drainGrace: Duration = .seconds(2)

    func start(_ invocation: Invocation, continuation: CheckedContinuation<Invocation.Outcome, Error>) {
        progress = invocation.progress
        spawned.onStdout = { [weak self] data in self?.lock.withLock { self?.stdout.append(data) } }
        spawned.onStderr = { [weak self] data in
            guard let self else { return }
            self.lock.withLock {
                self.stderr.append(data)
                self.stderrLine.append(data)
            }
            self.flushProgress(final: false)
        }
        spawned.onStdoutEnd = { [weak self] in self?.finishOne() }
        spawned.onStderrEnd = { [weak self] in
            self?.flushProgress(final: true)
            self?.finishOne()
        }
        spawned.onExit = { [weak self] code in
            guard let self else { return }
            let wasCancelled = self.lock.withLock {
                self.status = code
                self.exited = true
                return self.cancelled
            }
            self.finishOne()
            Task.detached { [weak self] in
                try? await Task.sleep(for: wasCancelled ? .milliseconds(200) : Self.drainGrace)
                self?.forceFinish()
            }
        }
        let shouldStart: Bool = lock.withLock {
            self.continuation = continuation
            if cancelled { return false }
            started = true
            return true
        }
        guard shouldStart else {
            resume(with: .success(Invocation.Outcome(status: -1, stdout: Data(), stderr: Data(), cancelled: true)))
            return
        }
        do {
            try spawned.start(executable: invocation.executable, arguments: invocation.arguments, directory: invocation.directory, environment: invocation.environment, stdin: invocation.stdin)
        } catch {
            resume(with: .failure(error))
        }
    }

    private func flushProgress(final: Bool) {
        guard let progress else { return }
        let lines: [String] = lock.withLock {
            var out: [String] = []
            while let index = stderrLine.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                let line = stderrLine[stderrLine.startIndex..<index]
                if !line.isEmpty { out.append(String(decoding: line, as: UTF8.self)) }
                stderrLine.removeSubrange(stderrLine.startIndex...index)
            }
            if final, !stderrLine.isEmpty {
                out.append(String(decoding: stderrLine, as: UTF8.self))
                stderrLine.removeAll()
            }
            return out
        }
        for line in lines { progress(line) }
    }

    private func finishOne() {
        let ready: Bool = lock.withLock {
            pending -= 1
            return pending == 0
        }
        if ready { complete() }
    }

    private func forceFinish() {
        let stillWaiting = lock.withLock { continuation != nil && exited }
        guard stillWaiting else { return }
        spawned.abandonOutput()
        complete()
    }

    private func complete() {
        let outcome = lock.withLock { Invocation.Outcome(status: status, stdout: stdout, stderr: stderr, cancelled: cancelled) }
        resume(with: .success(outcome))
    }

    private func resume(with result: Result<Invocation.Outcome, Error>) {
        let target = lock.withLock { () -> CheckedContinuation<Invocation.Outcome, Error>? in
            let c = continuation
            continuation = nil
            return c
        }
        target?.resume(with: result)
    }

    func cancel() {
        let running: Bool = lock.withLock {
            cancelled = true
            return started && !exited
        }
        guard running else { return }
        let spawned = self.spawned
        spawned.signalGroup(SIGINT)
        Task.detached {
            try? await Task.sleep(for: Invocation.interruptGrace)
            spawned.signalGroup(SIGTERM)
            try? await Task.sleep(for: Invocation.terminateGrace - Invocation.interruptGrace)
            spawned.signalGroup(SIGKILL)
        }
    }
}
