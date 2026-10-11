import Foundation

extension GitProcess {
    public static let scalarName = "scalar"

    public nonisolated func scalarExecutable(fileManager: FileManager = .default) async -> URL? {
        var candidates: [URL] = []
        if let result = try? await run(.read(["--exec-path"]), background: true) {
            let folder = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !folder.isEmpty { candidates.append(URL(filePath: folder, directoryHint: .isDirectory).appending(path: Self.scalarName)) }
        }
        candidates.append(executable.url.deletingLastPathComponent().appending(path: Self.scalarName))
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path(percentEncoded: false)) }
    }

    public nonisolated func runScalar(_ command: GitCommand, progress: (@Sendable (String) -> Void)? = nil) async throws -> GitResult {
        guard command.arguments.first == Self.scalarName, let tool = await scalarExecutable() else { throw GitError(.gitNotFound) }
        let started = Date()
        let clock = ContinuousClock()
        let begin = clock.now
        let invocation = Invocation(
            executable: tool,
            arguments: Array(command.arguments.dropFirst()),
            directory: workingDirectory,
            environment: environment.variables(for: command),
            stdin: command.stdin,
            progress: progress
        )
        let outcome: Invocation.Outcome
        do {
            outcome = try await invocation.run()
        } catch {
            throw GitError(.gitNotFound)
        }
        let result = GitResult(command: command, exitCode: outcome.status, stdout: outcome.stdout, stderr: outcome.stderr, startedAt: started, duration: clock.now - begin)
        forward(ConsoleEntry(source: .vrai, command: command.display, cwd: workingDirectory.path(percentEncoded: false), startedAt: started, duration: result.duration, exitCode: outcome.status, stdout: outcome.stdout, stderr: outcome.stderr, background: false, cancelled: outcome.cancelled))
        if outcome.cancelled { throw GitError(.cancelled, result: result) }
        guard result.succeeded else { throw ErrorClassifier.classify(result) }
        return result
    }
}
