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
