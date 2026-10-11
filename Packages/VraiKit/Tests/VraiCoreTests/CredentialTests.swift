import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"), .serialized)
struct CredentialTests {
    static var sandboxStore: URL { Sandbox.root.appending(path: "git-credentials") }

    @Test func signInAgainLandsInTheSandboxStoreNeverTheKeychain() async throws {
        let copy = try ScenarioCopy.make("auth")
        defer { copy.remove() }
        let port = try AuthServer.port(in: copy)
        let git = try copy.process()
        let helpers = try await git.run(.read(["config", "--show-origin", "--get-all", "credential.helper"])).output
        let lines = helpers.split(separator: "\n").map(String.init)
        #expect(lines == ["file:" + Sandbox.root.appending(path: "gitconfig").path(percentEncoded: false) + "\tstore --file=" + Self.sandboxStore.path(percentEncoded: false)])
        #expect(!helpers.contains("osxkeychain"))

        let original = (try? Data(contentsOf: Self.sandboxStore)) ?? Data()
        defer { try? original.write(to: Self.sandboxStore) }
        let token = "vrai_fresh_" + UUID().uuidString.prefix(8)
        let store = CredentialStore(git: git)
        #expect(store.approveCommand().display == "git credential approve")
        try await store.approve(url: "http://127.0.0.1:\(port)/vrai.git", username: "avery", password: String(token))
        let saved = try String(contentsOf: Self.sandboxStore, encoding: .utf8)
        #expect(saved.contains("http://avery:\(token)@127.0.0.1%3a\(port)"))
        let filled = try await store.fill(url: "http://127.0.0.1:\(port)/vrai.git")
        #expect(filled?.username == "avery")
        #expect(filled?.password == String(token))

        try await store.reject(url: "http://127.0.0.1:\(port)/vrai.git", username: "avery")
        #expect(try String(contentsOf: Self.sandboxStore, encoding: .utf8).contains(String(token)) == false)
        #expect(try await store.fill(url: "http://127.0.0.1:\(port)/vrai.git") == nil)
    }

    @MainActor
    @Test func storeSignInUsesTheRemoteURLAndClearsTheBadge() async throws {
        let copy = try ScenarioCopy.make("auth")
        defer { copy.remove() }
        let port = try AuthServer.port(in: copy)
        let environment = try copy.isolatedEnvironment()
        let store = try await copy.store(environment: environment)
        try await AuthServer.acquire(port: port)
        defer { AuthServer.release() }
        await expectCode("authFailed") { try await store.fetch() }
        #expect(store.snapshot?.network == .authFailed(host: "127.0.0.1"))
        try await store.signIn(username: "avery", token: "vrai_new_token")
        #expect(store.snapshot?.network == .unknown)
        #expect(try String(contentsOf: copy.credentialFile, encoding: .utf8).contains("http://avery:vrai_new_token@127.0.0.1%3a\(port)"))
        await expectCode("authFailed") { try await store.fetch() }
        try await store.signIn(username: "avery", token: "again")
        try await store.signOut()
        #expect(try String(contentsOf: copy.credentialFile, encoding: .utf8).contains("again") == false)
    }

    @Test func askpassRoundTripAgainstTheAuthServer() async throws {
        let copy = try ScenarioCopy.make("auth")
        defer { copy.remove() }
        let port = try AuthServer.port(in: copy)
        let helper = try AskpassHelper.binary()
        let requests = Recorder<AskpassRequest>()
        let bridge = try AskpassBridge(socketURL: AskpassBridge.socketURL(in: Sandbox.root.appending(path: "askpass", directoryHint: .isDirectory)))
        defer { bridge.close() }
        bridge.setHandler { request in
            await requests.append(request)
            return request.kind == .username ? "avery" : "token-from-the-sheet"
        }
        let environment = bridge.environment(try copy.isolatedEnvironment(helper: false), helper: helper, context: "window-1")
        #expect(environment.variables(for: .read(["fetch"]))["GIT_ASKPASS"] == helper.path(percentEncoded: false))
        #expect(environment.variables(for: .read(["fetch"]))["SSH_ASKPASS_REQUIRE"] == "force")
        let git = try copy.process(environment: environment)
        try await AuthServer.acquire(port: port)
        defer { AuthServer.release() }
        let error = await Self.failure(git, ["fetch", "origin"])
        #expect(error?.code == .authFailed(host: "127.0.0.1"))
        let seen = await requests.values
        #expect(seen.count == 2)
        #expect(seen.first?.kind == .username)
        #expect(seen.first?.prompt == "Username for 'http://127.0.0.1:\(port)': ")
        #expect(seen.first?.host == "127.0.0.1:\(port)")
        #expect(seen.first?.context == "window-1")
        #expect(seen.last?.kind == .password)
        #expect(seen.last?.prompt == "Password for 'http://avery@127.0.0.1:\(port)': ")
        #expect(seen.last?.username == "avery")
    }

    @Test func askpassDeclineAndTimeout() async throws {
        let copy = try ScenarioCopy.make("auth")
        defer { copy.remove() }
        let port = try AuthServer.port(in: copy)
        let helper = try AskpassHelper.binary()
        let bridge = try AskpassBridge(socketURL: AskpassBridge.socketURL(in: Sandbox.root.appending(path: "askpass", directoryHint: .isDirectory)))
        defer { bridge.close() }
        try await AuthServer.acquire(port: port)
        defer { AuthServer.release() }

        bridge.setHandler { _ in nil }
        let declined = try copy.process(environment: bridge.environment(try copy.isolatedEnvironment(helper: false), helper: helper))
        let error = await Self.failure(declined, ["fetch", "origin"])
        #expect(error?.code == .authFailed(host: "127.0.0.1"))

        bridge.setHandler { _ in
            try? await Task.sleep(for: .seconds(3))
            return "late"
        }
        var slow = bridge.environment(try copy.isolatedEnvironment(helper: false), helper: helper)
        slow.base[AskpassBridge.timeoutVariable] = "0.5"
        let clock = ContinuousClock()
        let started = clock.now
        let timedOut = await Self.failure(try copy.process(environment: slow), ["fetch", "origin"])
        #expect(clock.now - started < .seconds(2.5))
        #expect(timedOut?.code == .authFailed(host: "127.0.0.1"))
        #expect(timedOut?.result?.errorOutput.contains("did not answer within 0 seconds") == true || timedOut?.result?.errorOutput.contains("did not answer within 1 seconds") == true)
    }

    @Test func helperExitsWithoutTheApp() throws {
        let helper = try AskpassHelper.binary()
        let missing = try Self.runHelper(helper, environment: [:])
        #expect(missing.status == 1)
        #expect(missing.stderr.contains("no Vrai window is answering prompts"))
        let nobody = try Self.runHelper(helper, environment: [AskpassBridge.socketVariable: Sandbox.root.appending(path: "askpass/none.sock").path(percentEncoded: false)])
        #expect(nobody.status == 1)
        #expect(nobody.stderr.contains("Vrai is not answering prompts"))
    }

    @Test func helperPrintsTheAnswer() async throws {
        let helper = try AskpassHelper.binary()
        let bridge = try AskpassBridge(socketURL: AskpassBridge.socketURL(in: Sandbox.root.appending(path: "askpass", directoryHint: .isDirectory)), handler: { request in
            request.kind == .confirm ? "yes" : "pass phrase with spaces"
        })
        defer { bridge.close() }
        let environment = [AskpassBridge.socketVariable: bridge.socketURL.path(percentEncoded: false)]
        let passphrase = try Self.runHelper(helper, arguments: ["Enter passphrase for key '/x/id_ed25519': "], environment: environment)
        #expect(passphrase.status == 0)
        #expect(passphrase.stdout == "pass phrase with spaces\n")
        let confirm = try Self.runHelper(helper, arguments: ["Allow use of key?"], environment: environment.merging(["SSH_ASKPASS_PROMPT": "confirm"]) { $1 })
        #expect(confirm.stdout == "yes\n")
        bridge.close()
        let closed = try Self.runHelper(helper, environment: environment)
        #expect(closed.status == 1)
    }

    static func failure(_ git: GitProcess, _ arguments: [String]) async -> GitError? {
        do {
            try await git.run(GitCommand(arguments, access: .write))
            Issue.record("expected \(arguments) to fail")
            return nil
        } catch {
            return error as? GitError
        }
    }

    static func runHelper(_ helper: URL, arguments: [String] = ["Username for 'https://github.com': "], environment: [String: String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = helper
        process.arguments = arguments
        process.environment = environment
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: stdout, as: UTF8.self), String(decoding: stderr, as: UTF8.self))
    }
}
