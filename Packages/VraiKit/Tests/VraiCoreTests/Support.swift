import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

enum Sandbox {
    static var root: URL {
        if let explicit = ProcessInfo.processInfo.environment["VRAI_SANDBOX"], !explicit.isEmpty {
            return URL(filePath: explicit, directoryHint: .isDirectory)
        }
        let tmp = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        return URL(filePath: tmp, directoryHint: .isDirectory).appending(path: "vrai-sandbox", directoryHint: .isDirectory)
    }

    static func repository(_ relative: String) -> URL {
        root.appending(path: "fixtures/" + relative, directoryHint: .isDirectory)
    }

    static func has(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: repository(relative).appending(path: ".git").path(percentEncoded: false))
    }

    static var available: Bool { has("everyday/vrai") }

    static func git(_ relative: String) throws -> GitProcess {
        GitProcess(executable: try GitExecutable.discover(), workingDirectory: repository(relative), environment: .sandbox(root: root))
    }

    static func git(at url: URL) throws -> GitProcess {
        GitProcess(executable: try GitExecutable.discover(), workingDirectory: url, environment: .sandbox(root: root))
    }

    static func output(_ relative: String, _ arguments: [String]) async throws -> String {
        try await git(relative).run(.read(arguments)).output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func manifest(_ scenario: String) throws -> [String: Any] {
        let url = root.appending(path: "fixtures/\(scenario)/manifest.json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
    }
}

func median(_ values: [Duration]) -> Duration {
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}

func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
}
