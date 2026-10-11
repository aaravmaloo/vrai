import Foundation

public struct GitResult: Sendable, Hashable {
    public var command: GitCommand
    public var exitCode: Int32
    public var stdout: Data
    public var stderr: Data
    public var startedAt: Date
    public var duration: Duration

    public init(command: GitCommand, exitCode: Int32, stdout: Data, stderr: Data, startedAt: Date, duration: Duration) {
        self.command = command
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.startedAt = startedAt
        self.duration = duration
    }

    public var output: String { String(decoding: stdout, as: UTF8.self) }
    public var errorOutput: String { String(decoding: stderr, as: UTF8.self) }
    public var succeeded: Bool { command.acceptedExitCodes.contains(exitCode) }
}
