import Foundation

extension GitProcess {
    public nonisolated func stream(_ command: GitCommand, source: ConsoleEntry.Source = .vrai, background: Bool = true) -> AsyncThrowingStream<Data, Error> {
        let box = StreamBox()
        let invocationArguments = Self.implicitArguments + command.arguments
        let env = environment.variables(for: command)
        let url = executable.url
        let cwd = workingDirectory
        let report: @Sendable (ConsoleEntry) -> Void = { [weak self] entry in self?.forward(entry) }
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { _ in box.cancel() }
            box.start(executable: url, arguments: invocationArguments, directory: cwd, environment: env, command: command, source: source, background: background, continuation: continuation, report: report)
        }
    }
}

final class StreamBox: @unchecked Sendable {
    private let lock = NSLock()
    private let spawned = SpawnedProcess()
    private var stderr = Data()
    private var head = Data()
    private var pending = 3
    private var status: Int32 = -1
    private var cancelled = false
    private var startedAt = Date()
    private let clock = ContinuousClock()
    private var begin = ContinuousClock.now
    private var command: GitCommand?
    private var source: ConsoleEntry.Source = .vrai
    private var background = true
    private var directory = ""
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var report: (@Sendable (ConsoleEntry) -> Void)?

    func start(executable: URL, arguments: [String], directory: URL, environment: [String: String], command: GitCommand, source: ConsoleEntry.Source, background: Bool, continuation: AsyncThrowingStream<Data, Error>.Continuation, report: @escaping @Sendable (ConsoleEntry) -> Void) {
        lock.withLock {
            self.command = command
            self.source = source
            self.background = background
            self.directory = directory.path(percentEncoded: false)
            self.continuation = continuation
            self.report = report
            self.startedAt = Date()
            self.begin = clock.now
        }
        spawned.onStdout = { [weak self] data in
            guard let self else { return }
            let target: AsyncThrowingStream<Data, Error>.Continuation? = self.lock.withLock {
                if self.head.count < 65_536 { self.head.append(data.prefix(65_536 - self.head.count)) }
                return self.cancelled ? nil : self.continuation
            }
            target?.yield(data)
        }
        spawned.onStderr = { [weak self] data in self?.lock.withLock { self?.stderr.append(data) } }
        spawned.onStdoutEnd = { [weak self] in self?.finishOne() }
        spawned.onStderrEnd = { [weak self] in self?.finishOne() }
        spawned.onExit = { [weak self] code in
            self?.lock.withLock { self?.status = code }
            self?.finishOne()
        }
        do {
            try spawned.start(executable: executable, arguments: arguments, directory: directory, environment: environment, stdin: nil)
        } catch {
            lock.withLock { self.continuation = nil }
            continuation.finish(throwing: GitError(.gitNotFound))
        }
    }

    private func finishOne() {
        let done: (AsyncThrowingStream<Data, Error>.Continuation, GitResult, Bool, (@Sendable (ConsoleEntry) -> Void)?, ConsoleEntry)? = lock.withLock {
            pending -= 1
            guard pending == 0, let continuation, let command else { return nil }
            self.continuation = nil
            let duration = clock.now - begin
            let result = GitResult(command: command, exitCode: status, stdout: head, stderr: stderr, startedAt: startedAt, duration: duration)
            let entry = ConsoleEntry(source: source, command: command.display, cwd: directory, startedAt: startedAt, duration: duration, exitCode: status, stdout: head, stderr: stderr, background: background, cancelled: cancelled, acceptedExitCodes: command.acceptedExitCodes)
            return (continuation, result, cancelled, report, entry)
        }
        guard let (continuation, result, wasCancelled, report, entry) = done else { return }
        report?(entry)
        if wasCancelled {
            continuation.finish(throwing: GitError(.cancelled, result: result))
        } else if result.succeeded {
            continuation.finish()
        } else {
            continuation.finish(throwing: ErrorClassifier.classify(result))
        }
    }

    func cancel() {
        let first: Bool = lock.withLock {
            guard !cancelled else { return false }
            cancelled = true
            return true
        }
        guard first, spawned.isRunning else { return }
        spawned.signalGroup(SIGTERM)
    }
}
