import Foundation

public struct GitExecutable: Sendable, Hashable {
    public let url: URL
    public let version: GitVersion

    public init(url: URL, version: GitVersion) {
        self.url = url
        self.version = version
    }

    public static let candidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]
    public static let commandLineToolsShim = "/usr/bin/git"

    public var path: String { url.path(percentEncoded: false) }

    public func supports(_ feature: GitFeature) -> Bool { version >= feature.minimumVersion }

    public static func discover(preferred: String? = nil, fileManager: FileManager = .default) throws -> GitExecutable {
        var paths: [String] = []
        if let preferred, !preferred.isEmpty { paths.append(preferred) }
        paths.append(contentsOf: candidates)
        var tooOld: GitVersion?
        for path in paths where fileManager.isExecutableFile(atPath: path) {
            if path == commandLineToolsShim, !developerToolsInstalled(fileManager: fileManager) { continue }
            guard let version = try? readVersion(at: path) else { continue }
            if version < GitVersion.minimum {
                tooOld = tooOld.map { max($0, version) } ?? version
                continue
            }
            return GitExecutable(url: URL(filePath: path), version: version)
        }
        if let tooOld { throw GitError(.gitTooOld(found: tooOld, needed: GitVersion.minimum)) }
        throw GitError(.gitNotFound)
    }

    public static func readVersion(at path: String) throws -> GitVersion {
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = ["--version"]
        process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitWithoutRunLoop()
        guard process.terminationStatus == 0, let version = GitVersion(parsing: String(decoding: data, as: UTF8.self)) else {
            throw GitError(.gitNotFound)
        }
        return version
    }

    static func developerToolsInstalled(fileManager: FileManager) -> Bool {
        let roots = ["/Library/Developer/CommandLineTools/usr/bin/git", "/Applications/Xcode.app/Contents/Developer/usr/bin/git"]
        if roots.contains(where: fileManager.isExecutableFile(atPath:)) { return true }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitWithoutRunLoop()
        let dir = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return process.terminationStatus == 0 && fileManager.isExecutableFile(atPath: dir + "/usr/bin/git")
    }
}

extension Process {
    // waitUntilExit() spins the current run loop, so on the main thread it lets queued
    // blocks run mid-call. During launch that re-enters SwiftUI's graph and aborts.
    func waitWithoutRunLoop() {
        while isRunning { usleep(1_000) }
    }
}

public enum GitFeature: Sendable, CaseIterable {
    case historyReword
    case replay
    case pathFormatAbsolute

    public var minimumVersion: GitVersion {
        switch self {
        case .historyReword: GitVersion(2, 54, 0)
        case .replay: GitVersion(2, 44, 0)
        case .pathFormatAbsolute: GitVersion(2, 31, 0)
        }
    }
}
