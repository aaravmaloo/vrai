import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

struct FakeCredentialManager {
    let root: URL

    var executable: URL { root.appending(path: "bin/git-credential-manager") }
    var state: URL { root.appending(path: "gcm", directoryHint: .isDirectory) }
    var accountsFile: URL { state.appending(path: "accounts") }
    var callsFile: URL { state.appending(path: "calls.log") }
    var path: String { executable.path(percentEncoded: false) }

    struct Call: Hashable {
        var arguments: String
        var interactive: String
        var modes: String
        var terminal: String
    }

    static func install(in root: URL, accounts: [(host: String, user: String, secret: String)] = []) throws -> FakeCredentialManager {
        let fake = FakeCredentialManager(root: root)
        let fm = FileManager.default
        try fm.createDirectory(at: fake.executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: fake.state, withIntermediateDirectories: true)
        let seeded = accounts.map { $0.host + "\t" + $0.user + "\t" + $0.secret + "\n" }.joined()
        try Data(seeded.utf8).write(to: fake.accountsFile)
        try Data(script(state: fake.state.path(percentEncoded: false)).utf8).write(to: fake.executable)
        try fm.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: fake.path)
        return fake
    }

    static func script(state: String) -> String {
        """
        #!/bin/bash
        state='\(state)'
        accounts="$state/accounts"
        touch "$accounts"
        printf '%s\\t%s\\t%s\\t%s\\n' "$*" "${GCM_INTERACTIVE:-}" "${GCM_GITHUB_AUTHMODES:-}" "${GIT_TERMINAL_PROMPT:-}" >> "$state/calls.log"
        host_of() { local u="${1#*://}"; u="${u#*@}"; echo "${u%%/*}"; }
        case "$1" in
          --version) echo "2.6.1+fake0123"; exit 0 ;;
          github)
            sub="$2"; shift 2
            url="https://github.com"; account=""
            while [ $# -gt 0 ]; do
              case "$1" in
                --url) url="$2"; shift 2 ;;
                *) account="$1"; shift ;;
              esac
            done
            host="$(host_of "$url")"
            case "$sub" in
              list) awk -F'\\t' -v h="$host" '$1 == h { print $2 }' "$accounts"; exit 0 ;;
              login)
                [ "${GCM_GITHUB_AUTHMODES:-}" = "browser" ] || { echo "fatal: expected browser sign in" >&2; exit 1; }
                [ -e "$state/fail-login" ] && { echo "fatal: the browser sign in was cancelled" >&2; exit 1; }
                user="$(cat "$state/next-login" 2>/dev/null || echo avery-gcm)"
                printf '%s\\t%s\\t%s\\n' "$host" "$user" "gho_from_browser" >> "$accounts"
                exit 0 ;;
              logout)
                awk -F'\\t' -v h="$host" -v u="$account" '$1 == h && $2 == u { found = 1 } END { exit found ? 0 : 1 }' "$accounts" || { echo "fatal: no account $account" >&2; exit 1; }
                awk -F'\\t' -v h="$host" -v u="$account" '!($1 == h && $2 == u)' "$accounts" > "$accounts.next" && mv "$accounts.next" "$accounts"
                exit 0 ;;
            esac ;;
          get|store|erase)
            op="$1"; host=""; username=""; password=""
            while IFS= read -r line && [ -n "$line" ]; do
              case "$line" in
                host=*) host="${line#host=}" ;;
                username=*) username="${line#username=}" ;;
                password=*) password="${line#password=}" ;;
              esac
            done
            case "$op" in
              get)
                [ "${GCM_INTERACTIVE:-}" = "never" ] || { echo "fatal: asked interactively" >&2; exit 1; }
                found="$(awk -F'\\t' -v h="$host" -v u="$username" '$1 == h && (u == "" || $2 == u) { print; exit }' "$accounts")"
                [ -n "$found" ] || { echo "fatal: Cannot prompt because user interactivity has been disabled." >&2; exit 1; }
                printf 'username=%s\\npassword=%s\\n' "$(printf '%s' "$found" | cut -f2)" "$(printf '%s' "$found" | cut -f3)"
                exit 0 ;;
              store) printf '%s\\t%s\\t%s\\n' "$host" "$username" "$password" >> "$accounts"; exit 0 ;;
              erase)
                awk -F'\\t' -v h="$host" -v u="$username" '!($1 == h && (u == "" || $2 == u))' "$accounts" > "$accounts.next" && mv "$accounts.next" "$accounts"
                exit 0 ;;
            esac ;;
        esac
        echo "fatal: unknown command $*" >&2
        exit 2

        """
    }

    var calls: [Call] {
        let text = (try? String(contentsOf: callsFile, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            return Call(arguments: fields[0], interactive: fields.count > 1 ? fields[1] : "", modes: fields.count > 2 ? fields[2] : "", terminal: fields.count > 3 ? fields[3] : "")
        }
    }

    var stored: String { (try? String(contentsOf: accountsFile, encoding: .utf8)) ?? "" }

    func nextLogin(_ user: String) throws {
        try Data(user.utf8).write(to: state.appending(path: "next-login"))
    }
}

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"), .serialized)
struct CredentialManagerTests {
    static func useHelpers(_ values: [String], in box: SettingsSandbox) async throws {
        let git = try box.app.configProcess()
        try await git.run(ConfigCommands.unset(CredentialHelperCommands.key, scope: .global))
        for value in values {
            try await git.run(ConfigCommands.add(CredentialHelperCommands.key, value, scope: .global))
        }
    }

    static func globalHelpers(_ box: SettingsSandbox) async throws -> [String] {
        ConfigCommands.values(try await box.app.configProcess().run(ConfigCommands.getAll(CredentialHelperCommands.key, scope: .global)).stdout)
    }

    @Test func statusComesFromGitWhateverTheHelper() async throws {
        let box = try await SettingsSandbox.make([])
        defer { box.remove() }
        let fake = try FakeCredentialManager.install(in: box.root, accounts: [(host: "github.com", user: "avery", secret: "gho_never_kept_7f3a")])
        try await Self.useHelpers(["", fake.path], in: box)
        let console = ConsoleRecorder()
        let accounts = CredentialAccounts(store: CredentialStore(git: try box.app.process(at: box.root, observer: console.observer)))

        let found = await accounts.lookup(url: "https://github.com/vrai-app/vrai.git")
        #expect(found.usernames == ["avery"])
        #expect(found.managed.isEmpty)
        #expect(String(describing: found).contains("gho_never_kept_7f3a") == false)
        #expect(await accounts.lookup(url: "https://gitlab.com/vrai-app/vrai.git").usernames.isEmpty)
        #expect(await accounts.lookup(url: "https://github.com/vrai-app/vrai.git", username: "mira").usernames.isEmpty)

        let gets = fake.calls.filter { $0.arguments == "get" }
        #expect(gets.count == 3)
        #expect(gets.allSatisfy { $0.interactive == "never" && $0.terminal == "0" })
        #expect(console.entries.contains { $0.command == "git credential fill" })
        #expect(console.entries.allSatisfy { !$0.stdout.contains("gho_never_kept_7f3a") && !$0.stderr.contains("gho_never_kept_7f3a") })

        try await accounts.store.approve(url: "https://git.example.com", username: "mira", password: "glpat_sheet_token")
        #expect(fake.stored.contains("git.example.com\tmira\tglpat_sheet_token"))
        #expect(await accounts.lookup(url: "https://git.example.com/vrai.git").usernames == ["mira"])
        try await accounts.signOut(url: "https://git.example.com/vrai.git", username: "mira")
        #expect(!fake.stored.contains("git.example.com"))
        #expect(await accounts.lookup(url: "https://git.example.com/vrai.git").usernames.isEmpty)
    }

    @Test func statusWorksWithTheStoreHelper() async throws {
        let box = try await SettingsSandbox.make([])
        defer { box.remove() }
        try await Self.useHelpers([CredentialStore.storeHelper(file: box.credentials)], in: box)
        let accounts = CredentialAccounts(store: CredentialStore(git: try box.app.configProcess()))
        #expect(await accounts.lookup(url: "https://git.example.com/vrai.git").usernames.isEmpty)
        try await accounts.store.approve(url: "https://git.example.com", username: "avery", password: "vrai_store_token")
        #expect(await accounts.lookup(url: "https://avery@git.example.com/vrai.git", username: "avery").usernames == ["avery"])
        try await accounts.signOut(url: "https://git.example.com", username: "avery")
        #expect(try String(contentsOf: box.credentials, encoding: .utf8).contains("vrai_store_token") == false)
        #expect(await accounts.lookup(url: "https://git.example.com/vrai.git").usernames.isEmpty)
    }

    @Test func choosingTheCredentialManagerWritesWhatConfigureWrites() async throws {
        let box = try await SettingsSandbox.make([])
        defer { box.remove() }
        let settings = try box.app.makeGitSettings()
        await settings.reload()

        let missing = await settings.credentialSetup { box.app.locateCredentialManager($0) }
        #expect(missing.manager == nil)
        #expect(!missing.managerActive)
        #expect(missing.helpers.map(\.kind) == [.store])
        #expect(box.app.credentialManagerCandidates == [box.root.appending(path: "bin/git-credential-manager").path(percentEncoded: false)])

        let fake = try FakeCredentialManager.install(in: box.root)
        let found = await settings.credentialSetup { box.app.locateCredentialManager($0) }
        let manager = try #require(found.manager)
        #expect(manager.helperValue == fake.path)
        #expect(found.managerVersion == "2.6.1")
        #expect(!found.managerActive)

        try await settings.setCredentialManager(manager)
        #expect(try await Self.globalHelpers(box) == ["", fake.path])
        #expect(try await box.readGlobal(CredentialHelperCommands.azureUseHttpPath) == "true")
        try await settings.setCredentialManager(manager)
        #expect(try await Self.globalHelpers(box) == ["", fake.path])
        #expect(try await box.readGlobal("user.name") == "Avery Chen")

        let active = await settings.credentialSetup { box.app.locateCredentialManager($0) }
        #expect(active.managerActive)
        #expect(active.helpers.map(\.kind) == [.manager])

        try await settings.setCredentialHelper(.store)
        #expect(try await Self.globalHelpers(box) == ["", "store"])
        #expect(try await box.readGlobal(CredentialHelperCommands.azureUseHttpPath) == "true")
        try await settings.clearCredentialHelpers()
        #expect(try await Self.globalHelpers(box) == [""])
        #expect(await settings.credentialHelpers().isEmpty)
    }

    @Test func duplicateHelpersAreShownOnce() async throws {
        let box = try await SettingsSandbox.make([])
        defer { box.remove() }
        try await Self.useHelpers(["osxkeychain", "osxkeychain"], in: box)
        let settings = try box.app.makeGitSettings()
        await settings.reload()
        let setup = await settings.credentialSetup { box.app.locateCredentialManager($0) }
        #expect(setup.helpers.map(\.value) == ["osxkeychain"])
        #expect(CredentialHelper.displayNames(setup.helpers) == ["osxkeychain"])
    }

    @Test func signInListAndSignOutGoThroughTheCredentialManager() async throws {
        let box = try await SettingsSandbox.make([])
        defer { box.remove() }
        let fake = try FakeCredentialManager.install(in: box.root, accounts: [(host: "github.com", user: "mira", secret: "gho_mira")])
        let settings = try box.app.makeGitSettings()
        await settings.reload()
        let manager = try #require(await settings.credentialSetup { box.app.locateCredentialManager($0) }.manager)
        try await settings.setCredentialManager(manager)
        let setup = await settings.credentialSetup { box.app.locateCredentialManager($0) }
        #expect(setup.managerActive)
        let accounts = try box.app.credentialAccounts(setup)
        #expect(accounts.manager == manager)

        let before = await accounts.lookup(url: "https://github.com/vrai-app/vrai.git")
        #expect(before.usernames == ["mira"])
        #expect(before.managed == ["mira"])
        let added = try await box.app.signInWithCredentialManager(url: "https://github.com", setup: setup, known: before.usernames)
        #expect(added == "avery-gcm")
        #expect(box.app.preferences.accounts.map(\.id) == ["https://github.com\u{0}avery-gcm"])
        let login = try #require(fake.calls.first { $0.arguments.hasPrefix("github login") })
        #expect(login.arguments == "github login --url https://github.com")
        #expect(login.modes == "browser")
        #expect(login.interactive.isEmpty)

        let after = await accounts.lookup(url: "https://github.com/vrai-app/vrai.git")
        #expect(Set(after.usernames) == ["mira", "avery-gcm"])
        #expect(after.managed == ["mira", "avery-gcm"])
        let lists = fake.calls.filter { $0.arguments.hasPrefix("github list") }
        #expect(lists.allSatisfy { $0.arguments == "github list" && $0.interactive == "never" })

        try fake.nextLogin("avery-enterprise")
        #expect(try await accounts.signIn(url: "https://github.example.com/team/app.git") == ["avery-enterprise"])
        #expect(fake.calls.contains { $0.arguments == "github login --url https://github.example.com" })
        #expect(await accounts.lookup(url: "https://github.example.com/team/app.git").managed == ["avery-enterprise"])
        #expect(fake.calls.contains { $0.arguments == "github list --url https://github.example.com" })

        try await box.app.signOut(url: "https://github.com/vrai-app/vrai.git", username: "avery-gcm", setup: setup)
        #expect(fake.calls.contains { $0.arguments == "github logout avery-gcm" && $0.interactive == "never" })
        #expect(!fake.stored.contains("avery-gcm"))
        #expect(box.app.preferences.accounts.isEmpty)
        #expect(await accounts.lookup(url: "https://github.com").usernames == ["mira"])

        try await box.app.credentials().approve(url: "https://github.com", username: "rowan", password: "ghp_sandbox_store")
        let mixed = await accounts.lookup(url: "https://github.com")
        #expect(mixed.usernames.first == "rowan")
        #expect(!mixed.managed.contains("rowan"))
        try await box.app.signOut(url: "https://github.com", username: "rowan", setup: setup)
        #expect(!fake.calls.contains { $0.arguments == "github logout rowan" })
        #expect(try String(contentsOf: box.credentials, encoding: .utf8).contains("ghp_sandbox_store") == false)
    }

    @Test func credentialManagerFailuresSurface() async throws {
        let box = try await SettingsSandbox.make([])
        defer { box.remove() }
        let fake = try FakeCredentialManager.install(in: box.root)
        let accounts = CredentialAccounts(store: CredentialStore(git: try box.app.configProcess()), manager: CredentialManager(executable: fake.executable))
        #expect(try await accounts.listAccounts(url: "https://github.com").isEmpty)
        #expect(await accounts.version() == "2.6.1")
        await #expect(throws: GitError.self) {
            try await accounts.git.runCredentialManager(CredentialManager(executable: fake.executable), CredentialManager.logoutCommand(account: "nobody", url: "https://github.com"))
        }
        try Data().write(to: fake.state.appending(path: "fail-login"))
        await #expect(throws: GitError.self) { try await accounts.signIn(url: "https://github.com") }
        #expect(fake.stored.isEmpty)
        let none = CredentialAccounts(store: CredentialStore(git: try box.app.configProcess()))
        await #expect(throws: GitError.self) { try await none.signIn(url: "https://github.com") }
        #expect(try await none.listAccounts(url: "https://github.com").isEmpty)
    }
}
