import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

struct ArgvRecorder {
    let folder: URL
    let wrapper: URL
    let real: GitExecutable

    static func make(in root: URL) throws -> ArgvRecorder {
        let fm = FileManager.default
        let folder = root.appending(path: "argv", directoryHint: .isDirectory)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let real = try GitExecutable.discover()
        let wrapper = root.appending(path: "argv-git")
        let script = """
        #!/bin/sh
        record=$(/usr/bin/mktemp "$VRAI_ARGV_LOG/call.XXXXXXXX") || exit 97
        for argument in "$@"; do printf '%s\\000' "$argument"; done > "$record"
        exec '\(real.path)' "$@"

        """
        try Data(script.utf8).write(to: wrapper)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path(percentEncoded: false))
        return ArgvRecorder(folder: folder, wrapper: wrapper, real: real)
    }

    var executable: GitExecutable { GitExecutable(url: wrapper, version: real.version) }

    var environment: GitEnvironment {
        var environment = GitEnvironment.sandbox(root: Sandbox.root)
        environment.base["VRAI_ARGV_LOG"] = folder.path(percentEncoded: false)
        return environment
    }

    func calls() throws -> [[String]] {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        return try files.map { url in
            let data = try Data(contentsOf: url)
            return data.split(separator: 0, omittingEmptySubsequences: false).dropLast().map { String(decoding: $0, as: UTF8.self) }
        }
    }

    func commandCalls() throws -> [[String]] {
        try calls().map { call in
            Array(call.starts(with: GitProcess.implicitArguments) ? call.dropFirst(GitProcess.implicitArguments.count) : call[...])
        }
    }

    func reset() throws {
        for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

@MainActor
struct ConsoleFixture {
    let copy: ScenarioCopy
    let recorder: ArgvRecorder
    let console: ConsoleLog
    let store: RepositoryStore

    var repository: URL { copy.repository }

    static func make(_ scenario: String = "everyday", limit: Int = 5000) async throws -> ConsoleFixture {
        let copy = try ScenarioCopy.make(scenario)
        let recorder = try ArgvRecorder.make(in: copy.root.deletingLastPathComponent())
        let console = ConsoleLog(limit: limit, spillFolder: copy.root.deletingLastPathComponent().appending(path: "console", directoryHint: .isDirectory))
        let git = GitProcess(executable: recorder.executable, workingDirectory: copy.repository, environment: recorder.environment, observer: console.observer)
        let store = RepositoryStore(git: git, console: console)
        try await store.refresh()
        console.flush()
        return ConsoleFixture(copy: copy, recorder: recorder, console: console, store: store)
    }

    func remove() {
        copy.remove()
    }

    func settle() async {
        for _ in 0..<5 {
            await Task.yield()
            console.flush()
        }
    }

    static func difference(entries: [ConsoleEntry], calls: [[String]]) -> String {
        var counts: [String: Int] = [:]
        for call in calls { counts[rendered(call), default: 0] += 1 }
        for entry in entries {
            let key = entry.source == .you ? CommandParser.parse(entry.command).map { rendered($0.arguments) } ?? entry.command : entry.command
            counts[key, default: 0] -= 1
        }
        return counts.filter { $0.value != 0 }.map { "\($0.value > 0 ? "ran but not logged" : "logged but not run") \(abs($0.value))x: \($0.key)" }.sorted().joined(separator: "\n")
    }

    static func rendered(_ arguments: [String]) -> String {
        CommandDisplay.render(["git"] + arguments)
    }
}
