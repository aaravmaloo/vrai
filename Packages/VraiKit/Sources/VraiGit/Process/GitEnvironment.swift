import Foundation

public struct GitEnvironment: Sendable, Hashable {
    public var base: [String: String]
    public var askpass: String?
    public var editor: String?
    public var sequenceEditor: String?

    public init(base: [String: String], askpass: String? = nil, editor: String? = nil, sequenceEditor: String? = nil) {
        self.base = base
        self.askpass = askpass
        self.editor = editor
        self.sequenceEditor = sequenceEditor
    }

    public static func user(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> GitEnvironment {
        GitEnvironment(base: environment)
    }

    public static func sandbox(root: URL, inheriting environment: [String: String] = ProcessInfo.processInfo.environment) -> GitEnvironment {
        var base = environment
        for key in ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "SSH_AUTH_SOCK"] {
            base.removeValue(forKey: key)
        }
        for (key, value) in sandboxVariables(root: root) { base[key] = value }
        return GitEnvironment(base: base)
    }

    public static func sandboxVariables(root: URL) -> [String: String] {
        let path = root.path(percentEncoded: false).trimmingSuffix("/")
        return [
            "VRAI_SANDBOX": path,
            "HOME": path + "/home",
            "XDG_CONFIG_HOME": path + "/home/.config",
            "GIT_CONFIG_GLOBAL": path + "/gitconfig",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_ASKPASS": "/usr/bin/false",
            "SSH_ASKPASS": "/usr/bin/false",
            "GIT_SSH_COMMAND": "ssh -o BatchMode=yes",
            "GIT_CEILING_DIRECTORIES": path
        ]
    }

    public func variables(for command: GitCommand) -> [String: String] {
        var env = base
        env["LC_ALL"] = "C"
        env["GIT_TERMINAL_PROMPT"] = "0"
        if let askpass {
            env["GIT_ASKPASS"] = askpass
            env["SSH_ASKPASS"] = askpass
            env["SSH_ASKPASS_REQUIRE"] = "force"
        }
        env["GIT_EDITOR"] = command.editor ?? editor ?? "true"
        env["GIT_SEQUENCE_EDITOR"] = command.sequenceEditor ?? sequenceEditor ?? "true"
        if command.access == .read { env["GIT_OPTIONAL_LOCKS"] = "0" }
        for (key, value) in command.environment { env[key] = value }
        return env
    }
}

extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        var value = self
        while value.count > 1, value.hasSuffix(suffix) { value.removeLast(suffix.count) }
        return value
    }
}
