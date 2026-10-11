import Foundation

public struct GitBinary: Sendable, Hashable, Identifiable {
    public enum Source: String, Sendable, Hashable {
        case commandLineTools
        case xcode
        case homebrew
        case other
    }

    public var path: String
    public var version: GitVersion
    public var source: Source

    public var id: String { path }

    public init(path: String, version: GitVersion, source: Source) {
        self.path = path
        self.version = version
        self.source = source
    }

    public var isSupported: Bool { version >= GitVersion.minimum }
}

public enum GitBinaries {
    public static func find(including extra: [String?] = [], fileManager: FileManager = .default) -> [GitBinary] {
        var seen: Set<String> = []
        var found: [GitBinary] = []
        for candidate in extra.compactMap({ $0 }) + GitExecutable.candidates where !candidate.isEmpty && !seen.contains(candidate) {
            seen.insert(candidate)
            guard let binary = try? inspect(candidate, fileManager: fileManager) else { continue }
            found.append(binary)
        }
        return found
    }

    public static func inspect(_ path: String, fileManager: FileManager = .default) throws -> GitBinary {
        guard fileManager.isExecutableFile(atPath: path) else { throw GitError(.gitNotFound) }
        if path == GitExecutable.commandLineToolsShim, !GitExecutable.developerToolsInstalled(fileManager: fileManager) { throw GitError(.gitNotFound) }
        let version = try GitExecutable.readVersion(at: path)
        return GitBinary(path: path, version: version, source: source(of: path, fileManager: fileManager))
    }

    public static func source(of path: String, fileManager: FileManager = .default) -> GitBinary.Source {
        if path == GitExecutable.commandLineToolsShim {
            return fileManager.isExecutableFile(atPath: "/Library/Developer/CommandLineTools/usr/bin/git") ? .commandLineTools : .xcode
        }
        if path.hasPrefix("/Applications/Xcode") { return .xcode }
        if path.hasPrefix("/Library/Developer/CommandLineTools/") { return .commandLineTools }
        if path.hasPrefix("/opt/homebrew/") { return .homebrew }
        let resolved = URL(filePath: path).resolvingSymlinksInPath().path(percentEncoded: false)
        if resolved.contains("/Cellar/") || resolved.hasPrefix("/opt/homebrew/") { return .homebrew }
        return .other
    }
}
