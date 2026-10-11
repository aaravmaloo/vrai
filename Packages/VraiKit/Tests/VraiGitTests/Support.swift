import Foundation
import Testing
@testable import VraiGit

enum TestSandbox {
    static var root: URL {
        if let explicit = ProcessInfo.processInfo.environment["VRAI_SANDBOX"], !explicit.isEmpty {
            return URL(filePath: explicit, directoryHint: .isDirectory)
        }
        let tmp = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        return URL(filePath: tmp, directoryHint: .isDirectory).appending(path: "vrai-sandbox", directoryHint: .isDirectory)
    }

    static var fixtures: URL { root.appending(path: "fixtures", directoryHint: .isDirectory) }

    static func repository(_ relative: String) -> URL {
        fixtures.appending(path: relative, directoryHint: .isDirectory)
    }

    static var available: Bool {
        FileManager.default.fileExists(atPath: repository("everyday/vrai/.git").path(percentEncoded: false))
    }

    static var environment: GitEnvironment { .sandbox(root: root) }

    static func process(_ relative: String) throws -> GitProcess {
        GitProcess(executable: try GitExecutable.discover(), workingDirectory: repository(relative), environment: environment)
    }

    static var realPrefixes: [String] {
        let path = root.path(percentEncoded: false).trimmingSuffix("/")
        var prefixes = [path]
        if path.hasPrefix("/var/") { prefixes.insert("/private" + path, at: 0) }
        if let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: "/var"), path.hasPrefix("/var/") { _ = resolved }
        return prefixes
    }
}

enum Recorded {
    static let directory = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/git", directoryHint: .isDirectory)
    static let sandboxPlaceholder = "/SANDBOX"

    static func url(_ fixture: String, _ name: String) -> URL {
        directory.appending(path: fixture).appending(path: name + ".out")
    }

    static func data(_ fixture: String, _ name: String) throws -> Data {
        try Data(contentsOf: url(fixture, name))
    }

    static func normalize(_ data: Data) -> Data {
        var text = String(decoding: data, as: UTF8.self)
        for prefix in TestSandbox.realPrefixes { text = text.replacingOccurrences(of: prefix, with: sandboxPlaceholder) }
        return Data(text.utf8)
    }
}

enum Fixture {
    static let directory = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures", directoryHint: .isDirectory)

    static func json(_ relative: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: relative)))
    }
}
