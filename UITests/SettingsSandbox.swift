import Foundation
import XCTest

struct SettingsSandbox {
    let root: String

    var gitconfig: String { root + "/gitconfig" }
    var home: String { root + "/home" }
    var credentials: String { root + "/git-credentials" }

    func repository(_ scenario: String = "everyday") -> String {
        root + "/fixtures/" + scenario + "/" + (scenario == "empty" ? "pocket-notes" : "vrai")
    }

    static func make(_ scenarios: [String] = ["everyday"]) throws -> SettingsSandbox {
        let fm = FileManager.default
        let root = Sandbox.root + "/tests/settings-" + UUID().uuidString
        try fm.createDirectory(atPath: root + "/fixtures", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/home/.config", withIntermediateDirectories: true)
        try fm.copyItem(atPath: Sandbox.root + "/home/.ssh", toPath: root + "/home/.ssh")
        let config = try String(contentsOfFile: Sandbox.root + "/gitconfig", encoding: .utf8)
        try config.replacingOccurrences(of: Sandbox.root + "/", with: root + "/").write(toFile: root + "/gitconfig", atomically: true, encoding: .utf8)
        fm.createFile(atPath: root + "/git-credentials", contents: Data(), attributes: [.posixPermissions: NSNumber(value: 0o600)])
        let sandbox = SettingsSandbox(root: root)
        for scenario in scenarios {
            try fm.copyItem(atPath: Sandbox.root + "/fixtures/" + scenario, toPath: root + "/fixtures/" + scenario)
            let repo = sandbox.repository(scenario)
            let remotes = try sandbox.git(["remote"], in: repo)
            for name in remotes.output.split(separator: "\n").map(String.init) where !name.isEmpty {
                let url = try sandbox.git(["remote", "get-url", name], in: repo).output.trimmingCharacters(in: .whitespacesAndNewlines)
                guard url.contains(Sandbox.root + "/") else { continue }
                let outcome = try sandbox.git(["remote", "set-url", name, url.replacingOccurrences(of: Sandbox.root + "/", with: root + "/")], in: repo)
                XCTAssertEqual(outcome.status, 0, outcome.output)
            }
        }
        return sandbox
    }

    var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        for key in ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "SSH_AUTH_SOCK"] {
            env.removeValue(forKey: key)
        }
        env["VRAI_SANDBOX"] = root
        env["HOME"] = home
        env["XDG_CONFIG_HOME"] = home + "/.config"
        env["GIT_CONFIG_GLOBAL"] = gitconfig
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_ASKPASS"] = "/usr/bin/false"
        env["SSH_ASKPASS"] = "/usr/bin/false"
        env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes"
        env["GIT_CEILING_DIRECTORIES"] = root
        env["LC_ALL"] = "C"
        return env
    }

    struct Outcome {
        let status: Int32
        let output: String
    }

    func git(_ arguments: [String], in directory: String? = nil) throws -> Outcome {
        let candidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/Applications/Xcode.app/Contents/Developer/usr/bin/git", "/Library/Developer/CommandLineTools/usr/bin/git", "/usr/bin/git"]
        let executable = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/git"
        let process = Process()
        let out = Pipe()
        process.executableURL = URL(filePath: executable)
        process.arguments = ["-C", directory ?? root] + arguments
        process.environment = environment
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Outcome(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    func global(_ key: String) -> String? {
        guard let outcome = try? git(["config", "--global", "--get", key]), outcome.status == 0 else { return nil }
        return outcome.output.trimmingCharacters(in: .newlines)
    }

    func globalAll(_ key: String) -> [String] {
        guard let outcome = try? git(["config", "--global", "--get-all", key]), outcome.status == 0 else { return [] }
        return outcome.output.split(separator: "\n").map(String.init)
    }

    func local(_ key: String, scenario: String = "everyday") -> String? {
        guard let outcome = try? git(["config", "--local", "--get", key], in: repository(scenario)), outcome.status == 0 else { return nil }
        return outcome.output.trimmingCharacters(in: .newlines)
    }

    var lfsInstalled: Bool {
        guard let outcome = try? git(["lfs", "version"]) else { return false }
        return outcome.status == 0
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: root)
    }
}
