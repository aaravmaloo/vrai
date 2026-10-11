import Foundation

public struct ConsoleEntry: Sendable, Hashable, Identifiable {
    public enum Source: String, Sendable, Hashable, Codable {
        case vrai
        case you
    }

    public static let outputCap = 1 << 20

    public var id: UUID
    public var source: Source
    public var command: String
    public var cwd: String
    public var startedAt: Date
    public var duration: Duration
    public var exitCode: Int32?
    public var stdout: String
    public var stderr: String
    public var stdoutTruncated: Bool
    public var stderrTruncated: Bool
    public var background: Bool
    public var cancelled: Bool
    public var acceptedExitCodes: Set<Int32>

    public init(id: UUID = UUID(), source: Source, command: String, cwd: String, startedAt: Date, duration: Duration, exitCode: Int32?, stdout: Data, stderr: Data, background: Bool, cancelled: Bool = false, acceptedExitCodes: Set<Int32> = [0]) {
        self.id = id
        self.source = source
        self.command = command
        self.cwd = cwd
        self.startedAt = startedAt
        self.duration = duration
        self.exitCode = exitCode
        self.stdoutTruncated = stdout.count > Self.outputCap
        self.stderrTruncated = stderr.count > Self.outputCap
        self.stdout = String(decoding: stdout.prefix(Self.outputCap), as: UTF8.self)
        self.stderr = String(decoding: stderr.prefix(Self.outputCap), as: UTF8.self)
        self.background = background
        self.cancelled = cancelled
        self.acceptedExitCodes = acceptedExitCodes
    }

    public var failed: Bool { cancelled || exitCode.map { !acceptedExitCodes.contains($0) } ?? true }
}
