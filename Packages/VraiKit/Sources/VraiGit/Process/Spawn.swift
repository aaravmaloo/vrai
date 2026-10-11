import Darwin
import Foundation

final class SpawnedProcess: @unchecked Sendable {
    struct Failure: Error {
        let code: Int32
    }

    private let lock = NSLock()
    private(set) var pid: pid_t = 0
    private var exitSource: DispatchSourceProcess?
    private var outHandle: FileHandle?
    private var errHandle: FileHandle?
    private var exited = false

    var onStdout: (@Sendable (Data) -> Void)?
    var onStderr: (@Sendable (Data) -> Void)?
    var onStdoutEnd: (@Sendable () -> Void)?
    var onStderrEnd: (@Sendable () -> Void)?
    var onExit: (@Sendable (Int32) -> Void)?

    func start(executable: URL, arguments: [String], directory: URL, environment: [String: String], stdin: Data?) throws {
        var outPipe: [Int32] = [-1, -1]
        var errPipe: [Int32] = [-1, -1]
        var inPipe: [Int32] = [-1, -1]
        guard pipe(&outPipe) == 0, pipe(&errPipe) == 0 else { throw Failure(code: errno) }
        if stdin != nil, pipe(&inPipe) != 0 { throw Failure(code: errno) }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        if stdin != nil {
            posix_spawn_file_actions_adddup2(&actions, inPipe[0], 0)
        } else {
            posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        }
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2)
        posix_spawn_file_actions_addchdir(&actions, directory.path(percentEncoded: false))

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for signal in [SIGPIPE, SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGCHLD] { sigaddset(&defaults, signal) }
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        var mask = sigset_t()
        sigemptyset(&mask)
        posix_spawnattr_setsigmask(&attributes, &mask)

        let argv = ([executable.path(percentEncoded: false)] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            for pointer in argv { free(pointer) }
            for pointer in envp { free(pointer) }
        }

        var child: pid_t = 0
        let status = posix_spawn(&child, executable.path(percentEncoded: false), &actions, &attributes, argv, envp)
        close(outPipe[1])
        close(errPipe[1])
        if stdin != nil { close(inPipe[0]) }
        guard status == 0 else {
            close(outPipe[0])
            close(errPipe[0])
            if stdin != nil { close(inPipe[1]) }
            throw Failure(code: status)
        }
        lock.withLock { pid = child }

        let out = FileHandle(fileDescriptor: outPipe[0], closeOnDealloc: true)
        let err = FileHandle(fileDescriptor: errPipe[0], closeOnDealloc: true)
        lock.withLock {
            outHandle = out
            errHandle = err
        }
        out.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                self?.onStdoutEnd?()
            } else {
                self?.onStdout?(data)
            }
        }
        err.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                self?.onStderrEnd?()
            } else {
                self?.onStderr?(data)
            }
        }

        let source = DispatchSource.makeProcessSource(identifier: child, eventMask: .exit, queue: .global(qos: .userInitiated))
        source.setEventHandler { [weak self] in
            source.cancel()
            var raw: Int32 = 0
            var reaped = waitpid(child, &raw, 0)
            while reaped == -1, errno == EINTR { reaped = waitpid(child, &raw, 0) }
            guard reaped == child else { return }
            self?.reportExit(raw)
        }
        lock.withLock { exitSource = source }
        source.resume()
        var check: Int32 = 0
        if waitpid(child, &check, WNOHANG) == child {
            source.cancel()
            reportExit(check)
        }

        if let stdin {
            let writer = FileHandle(fileDescriptor: inPipe[1], closeOnDealloc: true)
            DispatchQueue.global(qos: .userInitiated).async {
                try? writer.write(contentsOf: stdin)
                try? writer.close()
            }
        }
    }

    private func reportExit(_ raw: Int32) {
        let first = lock.withLock {
            defer { exited = true }
            return !exited
        }
        guard first else { return }
        onExit?(raw & 0x7f == 0 ? (raw >> 8) & 0xff : 128 + (raw & 0x7f))
    }

    var isRunning: Bool { lock.withLock { pid != 0 && !exited } }

    func signalGroup(_ signal: Int32) {
        let (target, done) = lock.withLock { (pid, exited) }
        guard target > 0 else { return }
        kill(-target, signal)
        if !done { kill(target, signal) }
    }

    func abandonOutput() {
        let handles = lock.withLock { (outHandle, errHandle) }
        handles.0?.readabilityHandler = nil
        handles.1?.readabilityHandler = nil
    }
}
