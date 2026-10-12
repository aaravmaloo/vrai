import Darwin
import Foundation
import Testing
@testable import VraiGit

struct CredentialUnitTests {
    @Test func requestKinds() {
        #expect(AskpassRequest(prompt: "Username for 'https://github.com': ").kind == .username)
        #expect(AskpassRequest(prompt: "Username for 'https://github.com': ").host == "github.com")
        #expect(AskpassRequest(prompt: "Password for 'https://avery@github.com': ").kind == .password)
        #expect(AskpassRequest(prompt: "Password for 'https://avery@github.com': ").username == "avery")
        #expect(AskpassRequest(prompt: "git@github.com's password: ").kind == .password)
        #expect(AskpassRequest(prompt: "Enter passphrase for key '/Users/x/.ssh/id_ed25519': ").kind == .passphrase)
        #expect(AskpassRequest(prompt: "Are you sure you want to continue connecting (yes/no/[fingerprint])? ").kind == .confirm)
        #expect(AskpassRequest(prompt: "Confirm user presence", sshPrompt: "confirm").kind == .confirm)
    }

    @Test func credentialInputIsWellFormed() throws {
        let data = try CredentialStore.input(url: "https://github.com/vrai-app/vrai.git", username: " avery ", password: "token\n")
        #expect(String(decoding: data, as: UTF8.self) == "protocol=https\nhost=github.com\npath=vrai-app/vrai.git\nusername=avery\npassword=token\n\n")
        let local = try CredentialStore.input(url: "http://127.0.0.1:47813/vrai.git", username: nil, password: nil)
        #expect(String(decoding: local, as: UTF8.self) == "protocol=http\nhost=127.0.0.1:47813\npath=vrai.git\n\n")
        #expect(throws: GitError.self) { try CredentialStore.input(url: "not a url", username: nil, password: nil) }
        #expect(throws: GitError.self) { try CredentialStore.input(url: "/local/path.git", username: nil, password: nil) }
        let git = GitProcess(executable: GitExecutable(url: URL(filePath: "/usr/bin/git"), version: GitVersion.minimum), workingDirectory: URL(filePath: "/tmp"), environment: .user([:]))
        #expect(CredentialStore(git: git, helper: "store --file=/tmp/x").rejectCommand().arguments == ["-c", "credential.helper=", "-c", "credential.helper=store --file=/tmp/x", "credential", "reject"])
        #expect(CredentialStore(git: git).approveCommand().display == "git credential approve")
    }

    @Test func fillAsksWithoutPromptingAndKeepsOnlyTheUsername() throws {
        let git = GitProcess(executable: GitExecutable(url: URL(filePath: "/usr/bin/git"), version: GitVersion.minimum), workingDirectory: URL(filePath: "/tmp"), environment: .user([:]))
        let command = try CredentialStore(git: git).fillCommand(url: "https://github.com/vrai-app/vrai.git", username: "avery")
        #expect(command.display == "git credential fill")
        #expect(command.access == .read)
        #expect(command.hidesOutput)
        #expect(command.environment["GIT_TERMINAL_PROMPT"] == "0")
        #expect(command.environment["GCM_INTERACTIVE"] == "never")
        #expect(command.environment["GIT_ASKPASS"] == "/usr/bin/false")
        #expect(command.environment["SSH_ASKPASS"] == "/usr/bin/false")
        #expect(String(decoding: command.stdin ?? Data(), as: UTF8.self) == "protocol=https\nhost=github.com\npath=vrai-app/vrai.git\nusername=avery\n\n")
        let variables = GitEnvironment.user(["GIT_ASKPASS": "/Applications/Vrai.app/Contents/MacOS/vrai-askpass"]).variables(for: command)
        #expect(variables["GIT_ASKPASS"] == "/usr/bin/false")
        #expect(CredentialStore.username(in: Data("protocol=https\nhost=github.com\nusername=avery\npassword=gho_secret\n".utf8)) == "avery")
        #expect(CredentialStore.username(in: Data("username=avery\n".utf8)) == nil)
        #expect(CredentialStore.username(in: Data("username=avery\npassword=\n".utf8)) == nil)
        #expect(CredentialStore.username(in: Data("password=gho_secret\n".utf8)) == nil)
        #expect(CredentialStore.username(in: Data()) == nil)
    }

    @Test func credentialManagerCommands() {
        #expect(CredentialManager.listCommand(url: "https://github.com/vrai-app/vrai.git").display == "git credential-manager github list")
        #expect(CredentialManager.listCommand(url: "https://github.example.com/a/b.git").arguments == ["credential-manager", "github", "list", "--url", "https://github.example.com"])
        #expect(CredentialManager.listCommand(url: "https://github.com").environment["GCM_INTERACTIVE"] == "never")
        let login = CredentialManager.loginCommand(url: "https://avery@github.com/vrai-app/vrai.git")
        #expect(login.arguments == ["credential-manager", "github", "login", "--url", "https://github.com"])
        #expect(login.environment["GCM_GITHUB_AUTHMODES"] == "browser")
        #expect(login.environment["GCM_INTERACTIVE"] == nil)
        #expect(CredentialManager.logoutCommand(account: "avery", url: "https://github.com").arguments == ["credential-manager", "github", "logout", "avery"])
        #expect(CredentialManager.logoutCommand(account: "avery", url: "https://github.example.com:8443/x").arguments == ["credential-manager", "github", "logout", "avery", "--url", "https://github.example.com:8443"])
        #expect(CredentialManager.logoutCommand(account: "avery", url: "https://github.com").risk == .destructive)
        #expect(CredentialManager.versionCommand.arguments == ["credential-manager", "--version"])
        #expect(CredentialManager.installCommand == "brew install --cask git-credential-manager")
        #expect(CredentialManager.packagePath == "/usr/local/share/gcm-core/git-credential-manager")
        #expect(CredentialManager.isGitHub(host: "github.com"))
        #expect(CredentialManager.isGitHub(host: "GitHub.com:443"))
        #expect(CredentialManager.isGitHub(host: "acme.ghe.com"))
        #expect(CredentialManager.isGitHub(host: "github.acme.dev"))
        #expect(!CredentialManager.isGitHub(host: "gitlab.com"))
        #expect(!CredentialManager.isGitHub(host: "127.0.0.1:47801"))
        #expect(CredentialManager.searchPath(["PATH": "/usr/bin:/opt/homebrew/bin/"]) == ["/usr/bin/git-credential-manager", "/opt/homebrew/bin/git-credential-manager"])
    }

    @Test func credentialManagerOutputParses() {
        #expect(CredentialManager.accounts("avery\nmira\n", url: "https://github.com") == ["avery", "mira"])
        #expect(CredentialManager.accounts("", url: "https://github.com").isEmpty)
        #expect(CredentialManager.accounts("No accounts found.\n", url: "https://github.com").isEmpty)
        let grouped = "https://github.com:\n  avery\n  Avery\nhttps://github.example.com:\n  mira\n"
        #expect(CredentialManager.accounts(grouped, url: "https://github.com/a/b.git") == ["avery"])
        #expect(CredentialManager.accounts(grouped, url: "https://github.example.com") == ["mira"])
        #expect(CredentialManager.accounts(grouped, url: "https://acme.ghe.com").isEmpty)
        #expect(CredentialManager.version("2.6.1+3fdf2b2ea0d0b2b4\n") == "2.6.1")
        #expect(CredentialManager.version("") == nil)
    }

    @Test func credentialManagerIsFoundWhereItIsInstalled() throws {
        let folder = TestSandbox.root.appending(path: "tests/gcm-locate-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appending(path: "first/git-credential-manager").path(percentEncoded: false)
        let second = folder.appending(path: "second/git-credential-manager").path(percentEncoded: false)
        let plain = folder.appending(path: "plain/git-credential-manager").path(percentEncoded: false)
        for (path, mode) in [(second, 0o755), (plain, 0o644)] {
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: NSNumber(value: mode)])
        }
        #expect(CredentialManager.locate(candidates: [first, plain, second])?.helperValue == second)
        #expect(CredentialManager.locate(candidates: [first, plain]) == nil)
        #expect(CredentialManager.locate(configured: [CredentialHelper(second)], candidates: [])?.helperValue == second)
        #expect(CredentialManager.locate(configured: [CredentialHelper("manager")], candidates: []) == nil)
    }

    @Test func bridgeAnswersOverTheSocket() async throws {
        let directory = TestSandbox.root.appending(path: "askpass", directoryHint: .isDirectory)
        let bridge = try AskpassBridge(socketURL: AskpassBridge.socketURL(in: directory))
        defer { bridge.close() }
        let attributes = try FileManager.default.attributesOfItem(atPath: bridge.socketURL.path(percentEncoded: false))
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(Self.ask(bridge.socketURL, ["prompt": "Username for 'https://github.com': "]) == [UInt8(ascii: "0")])
        bridge.setHandler { request in request.kind == .username ? "avery" : nil }
        #expect(Self.ask(bridge.socketURL, ["prompt": "Username for 'https://github.com': ", "context": "w"]) == Array("1avery".utf8))
        #expect(Self.ask(bridge.socketURL, ["prompt": "Password for 'https://avery@github.com': "]) == [UInt8(ascii: "0")])
        let environment = bridge.environment(.user(["PATH": "/usr/bin"]), helper: URL(filePath: "/Applications/Vrai.app/Contents/MacOS/vrai-askpass"), context: "repo-1")
        let variables = environment.variables(for: .read(["fetch"]))
        #expect(variables["GIT_ASKPASS"] == "/Applications/Vrai.app/Contents/MacOS/vrai-askpass")
        #expect(variables["SSH_ASKPASS"] == "/Applications/Vrai.app/Contents/MacOS/vrai-askpass")
        #expect(variables[AskpassBridge.socketVariable] == bridge.socketURL.path(percentEncoded: false))
        #expect(variables[AskpassBridge.contextVariable] == "repo-1")
        bridge.close()
        #expect(!FileManager.default.fileExists(atPath: bridge.socketURL.path(percentEncoded: false)))
        #expect(throws: GitError.self) { try AskpassBridge(socketURL: directory.appending(path: String(repeating: "x", count: 120))) }
    }

    static func ask(_ socketURL: URL, _ request: [String: String]) -> [UInt8]? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var address = AskpassBridge.address(Array(socketURL.path(percentEncoded: false).utf8))
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0, let payload = try? JSONSerialization.data(withJSONObject: request) else { return nil }
        _ = payload.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        shutdown(fd, SHUT_WR)
        var reply: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 256)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            reply.append(contentsOf: buffer[0..<count])
        }
        return reply
    }
}
