import Foundation

public enum MaintenanceCommands {
    public static let register = GitCommand(["maintenance", "register"], access: .write)
    public static let unregister = GitCommand(["maintenance", "unregister"], access: .write)
    public static let registered = ConfigCommands.getAll(ConfigKeys.maintenanceRepo, scope: .global)

    public static func run(auto: Bool = false) -> GitCommand {
        GitCommand(["maintenance", "run"] + (auto ? ["--auto"] : []), access: .write)
    }

    public static func isRegistered(_ paths: [String], repository: URL) -> Bool {
        let wanted = canonical(repository.path(percentEncoded: false))
        return paths.contains { canonical($0) == wanted }
    }

    static func canonical(_ path: String) -> String {
        var value = URL(filePath: path, directoryHint: .isDirectory).resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        while value.count > 1, value.hasSuffix("/") { value.removeLast() }
        if value.hasPrefix("/private/var/") || value.hasPrefix("/private/tmp/") { value.removeFirst("/private".count) }
        return value
    }
}

public struct HookRun: Sendable, Hashable {
    public var name: String
    public var exitCode: Int32
    public var output: String
    public var duration: Duration

    public init(name: String, exitCode: Int32, output: String, duration: Duration) {
        self.name = name
        self.exitCode = exitCode
        self.output = output
        self.duration = duration
    }

    public var passed: Bool { exitCode == 0 }
}

public enum HookCommands {
    public static let messageHooks: Set<String> = ["commit-msg", "applypatch-msg", "prepare-commit-msg"]

    public static func run(_ name: String, arguments: [String] = [], stdin: Data? = nil) -> GitCommand {
        GitCommand(["hook", "run", name] + (arguments.isEmpty ? [] : ["--"] + arguments), stdin: stdin, access: .write)
    }

    public static func setEnabled(_ enabled: Bool, path: String, fileManager: FileManager = .default) throws {
        let attributes = try fileManager.attributesOfItem(atPath: path)
        let mode = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o644
        let next: UInt16 = enabled ? mode | ((mode & 0o444) >> 2) | 0o100 : mode & ~UInt16(0o111)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: next)], ofItemAtPath: path)
    }

    public static func summary(of path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path), data.count < 256 * 1024 else { return nil }
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
        for line in lines.dropFirst(lines.first?.hasPrefix("#!") == true ? 1 : 0) {
            guard line.hasPrefix("#") else { break }
            let text = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { return text }
        }
        return nil
    }
}

public struct LFSInfo: Sendable, Hashable {
    public var version: String
    public var configured: Bool
    public var patterns: [String]
    public var files: Int?

    public init(version: String, configured: Bool, patterns: [String] = [], files: Int? = nil) {
        self.version = version
        self.configured = configured
        self.patterns = patterns
        self.files = files
    }
}

public enum LFSStatus: Sendable, Hashable {
    case notInstalled
    case installed(LFSInfo)
}

public enum LFSCommands {
    public static let env = GitCommand.read(["lfs", "env"], acceptedExitCodes: [0, 1, 2, 128])
    public static let track = GitCommand.read(["lfs", "track"], acceptedExitCodes: [0, 1, 2, 128])
    public static let files = GitCommand.read(["lfs", "ls-files", "--name-only"], acceptedExitCodes: [0, 1, 2, 128])

    public static func isMissing(_ result: GitResult) -> Bool {
        result.exitCode != 0 && (result.errorOutput.contains("'lfs' is not a git command") || result.errorOutput.contains("git-lfs: command not found"))
    }

    public static func version(_ env: String) -> String? {
        env.firstMatch(of: /git-lfs\/([0-9][0-9A-Za-z.\-]*)/).map { String($0.output.1) }
    }

    public static func configured(_ env: String) -> Bool {
        for line in env.split(separator: "\n") where line.hasPrefix("git config filter.lfs.process") || line.hasPrefix("git config filter.lfs.clean") {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let value = line[line.index(after: equals)...].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"")))
            if !value.isEmpty { return true }
        }
        return false
    }

    public static func patterns(_ track: String) -> [String] {
        var tracked = false
        var out: [String] = []
        for raw in track.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            if line.hasPrefix("Listing tracked patterns") {
                tracked = true
                continue
            }
            if line.hasPrefix("Listing") {
                tracked = false
                continue
            }
            guard tracked, line.first?.isWhitespace == true else { continue }
            let text = line.trimmingCharacters(in: .whitespaces)
            if let match = text.firstMatch(of: /^(.+) \([^()]+\)$/) {
                out.append(String(match.output.1))
            } else if !text.isEmpty {
                out.append(text)
            }
        }
        return out
    }

    public static func fileCount(_ output: String) -> Int {
        output.split(separator: "\n", omittingEmptySubsequences: true).count
    }
}

public struct SSHKey: Sendable, Hashable, Identifiable {
    public var name: String
    public var path: String
    public var type: String
    public var fingerprint: String?
    public var comment: String?
    public var publicKey: String

    public var id: String { path }

    public init(name: String, path: String, type: String, fingerprint: String? = nil, comment: String? = nil, publicKey: String) {
        self.name = name
        self.path = path
        self.type = type
        self.fingerprint = fingerprint
        self.comment = comment
        self.publicKey = publicKey
    }
}

public enum SSHKeys {
    public static let keygen = "/usr/bin/ssh-keygen"

    public static func folder(home: URL) -> URL {
        home.appending(path: ".ssh", directoryHint: .isDirectory)
    }

    public static func list(home: URL, fingerprints: Bool = true, fileManager: FileManager = .default) -> [SSHKey] {
        let folder = folder(home: home)
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else { return [] }
        return names.filter { $0.hasSuffix(".pub") && !$0.hasPrefix(".") }.sorted().compactMap { name in
            let url = folder.appending(path: name)
            let path = url.path(percentEncoded: false)
            guard let data = fileManager.contents(atPath: path), data.count < 64 * 1024 else { return nil }
            let line = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard var key = parse(publicKey: line, name: String(name.dropLast(".pub".count)), path: path) else { return nil }
            if fingerprints, let print = fingerprint(of: path) {
                key.fingerprint = print.fingerprint
                key.type = print.type ?? key.type
            }
            return key
        }
    }

    public static func parse(publicKey line: String, name: String, path: String) -> SSHKey? {
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2, parts[0].contains("ssh") || parts[0].hasPrefix("ecdsa") else { return nil }
        return SSHKey(name: name, path: path, type: keyType(parts[0]), comment: parts.count > 2 ? parts[2] : nil, publicKey: line)
    }

    public static func keyType(_ prefix: String) -> String {
        switch prefix {
        case "ssh-ed25519": "ED25519"
        case "sk-ssh-ed25519@openssh.com": "ED25519-SK"
        case "ssh-rsa": "RSA"
        case "ssh-dss": "DSA"
        case "sk-ecdsa-sha2-nistp256@openssh.com": "ECDSA-SK"
        default: prefix.hasPrefix("ecdsa") ? "ECDSA" : prefix.uppercased()
        }
    }

    public static func parseFingerprint(_ output: String) -> (fingerprint: String, type: String?)? {
        guard let match = output.firstMatch(of: /^\d+\s+(\S+)\s.*?(?:\(([A-Z0-9-]+)\))?\s*$/.anchorsMatchLineEndings()) else { return nil }
        return (String(match.output.1), match.output.2.map(String.init))
    }

    public static func fingerprint(of path: String) -> (fingerprint: String, type: String?)? {
        guard FileManager.default.isExecutableFile(atPath: keygen) else { return nil }
        let process = Process()
        process.executableURL = URL(filePath: keygen)
        process.arguments = ["-l", "-f", path]
        process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return parseFingerprint(String(decoding: data, as: UTF8.self))
    }

    public static func signingKeyValue(for key: SSHKey, fileManager: FileManager = .default) -> String {
        let privatePath = String(key.path.dropLast(".pub".count))
        return key.path.hasSuffix(".pub") && fileManager.fileExists(atPath: privatePath) ? privatePath : key.path
    }

    public static func matches(_ key: SSHKey, signingKey: String?) -> Bool {
        guard let signingKey, !signingKey.isEmpty else { return false }
        let trimmed = signingKey.hasPrefix("key::") ? String(signingKey.dropFirst("key::".count)) : signingKey
        if trimmed.hasPrefix("ssh-") || trimmed.hasPrefix("ecdsa") || trimmed.hasPrefix("sk-") {
            let blob = trimmed.split(separator: " ").dropFirst().first
            return blob != nil && key.publicKey.split(separator: " ").dropFirst().first == blob
        }
        let expanded = trimmed.hasPrefix("~/") ? URL(filePath: key.path).deletingLastPathComponent().deletingLastPathComponent().path(percentEncoded: false) + trimmed.dropFirst(2) : trimmed
        let normalized = MaintenanceCommands.canonical(expanded)
        let pub = MaintenanceCommands.canonical(key.path)
        return normalized == pub || normalized + ".pub" == pub
    }
}

public enum GlobalConfigFile {
    public static func path(environment: [String: String], fileManager: FileManager = .default) -> String {
        if let explicit = environment["GIT_CONFIG_GLOBAL"], !explicit.isEmpty { return explicit }
        let home = environment["HOME"] ?? NSHomeDirectory()
        let dotfile = (home as NSString).appendingPathComponent(".gitconfig")
        let xdgBase = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? (home as NSString).appendingPathComponent(".config")
        let xdg = (xdgBase as NSString).appendingPathComponent("git/config")
        if !fileManager.fileExists(atPath: dotfile), fileManager.fileExists(atPath: xdg) { return xdg }
        return dotfile
    }

    public static func display(_ path: String, environment: [String: String], home: String = NSHomeDirectory()) -> String {
        if let sandbox = environment["VRAI_SANDBOX"], !sandbox.isEmpty, path.hasPrefix(sandbox + "/") {
            return "$VRAI_SANDBOX" + path.dropFirst(sandbox.count)
        }
        let base = home.hasSuffix("/") ? String(home.dropLast()) : home
        if !base.isEmpty, path.hasPrefix(base + "/") { return "~" + path.dropFirst(base.count) }
        return path
    }
}
