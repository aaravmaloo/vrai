import SwiftUI
import VraiCore
import VraiGit

struct SignInTarget: Sendable {
    var remote: String?
    var url: String?
    var host: String
    var repository: String
    var username: String
    var note: String? = nil
}

struct SignInSheet: View {
    enum Mode {
        case again(SignInTarget, retry: (@MainActor () -> Void)?)
        case prompt(AskpassRequest, PromptReply)
    }

    let mode: Mode
    @State private var username: String
    @State private var token = ""
    @State private var busy = false
    @State private var answered = false
    @Environment(WindowModel.self) private var window
    @Environment(RepositoryStore.self) private var store

    init(again target: SignInTarget, retry: (@MainActor () -> Void)?) {
        mode = .again(target, retry: retry)
        _username = State(initialValue: target.username)
    }

    init(prompt request: AskpassRequest, reply: PromptReply) {
        mode = .prompt(request, reply)
        _username = State(initialValue: request.username ?? "")
    }

    var request: AskpassRequest? {
        if case .prompt(let request, _) = mode { return request }
        return nil
    }

    var kind: AskpassRequest.Kind { request?.kind ?? .username }
    var asksForAccount: Bool { kind == .username || kind == .password }

    var host: String {
        switch mode {
        case .again(let target, _): target.host
        case .prompt(let request, _): request.host ?? String(localized: "the server", bundle: .module)
        }
    }

    var title: String {
        switch kind {
        case .passphrase: String(localized: "Unlock your SSH key", bundle: .module)
        case .other, .confirm: String(localized: "git needs an answer", bundle: .module)
        case .username, .password: String(localized: "Sign in to \(host)", bundle: .module)
        }
    }

    var description: String {
        switch mode {
        case .again(let target, _):
            if let note = target.note { return note }
            return SyncCopy.authTitle(host: target.host, repository: target.repository) + " " + String(localized: "Enter a personal access token to sign in again.", bundle: .module)
        case .prompt(let request, _):
            if asksForAccount, let url = request.url {
                return String(localized: "git needs a username and token to reach \(url).", bundle: .module)
            }
            return request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var fieldLabel: String {
        switch kind {
        case .passphrase: String(localized: "Passphrase", bundle: .module)
        case .other, .confirm: String(localized: "Answer", bundle: .module)
        case .username, .password: String(localized: "Token", bundle: .module)
        }
    }

    var helper: String? { SyncHub.shared.credentialHelper }

    var ok: Bool {
        !token.isEmpty && (!asksForAccount || !username.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        SyncForm.Sheet(
            title: title,
            description: description,
            primary: kind == .passphrase ? String(localized: "Unlock", bundle: .module) : (asksForAccount ? String(localized: "Sign in", bundle: .module) : String(localized: "Send", bundle: .module)),
            primaryEnabled: ok,
            busy: busy,
            onSubmit: go
        ) {
            if asksForAccount {
                SyncForm.Input(label: String(localized: "Username", bundle: .module), text: $username, placeholder: "avery-chen", mono: true, autofocus: username.isEmpty, onSubmit: go)
                    .disabled(kind == .password && request?.username != nil)
            }
            SyncForm.Input(label: fieldLabel, text: $token, placeholder: host.contains("github") ? "ghp_\u{2026}" : "", hint: asksForAccount ? String(localized: "Vrai never stores the token; git hands it to your credential helper.", bundle: .module) : nil, mono: true, secure: true, autofocus: !username.isEmpty || !asksForAccount, onSubmit: go)
            if case .again = mode {
                SyncForm.Options(commands: [CredentialStore(git: store.git, helper: helper).approveCommand()], hasContent: false) { EmptyView() }
            }
        }
        .onDisappear {
            if case .prompt(_, let reply) = mode, !answered { reply.finish(nil) }
        }
    }

    func go() {
        guard ok, !busy else { return }
        let name = username.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .prompt(_, let reply):
            answered = true
            reply.finish(SignInAnswer(username: name, token: token))
            window.sheets.dismiss()
        case .again(let target, let retry):
            busy = true
            let sync = window.sync
            let secret = token
            let helper = helper
            let store = store
            Task {
                do {
                    if let url = target.url {
                        try await store.perform("signIn", refresh: false) {
                            try await CredentialStore(git: store.git, helper: helper).approve(url: url, username: name, password: secret)
                        }
                    } else {
                        try await store.signIn(remote: target.remote, username: name, token: secret, helper: helper)
                    }
                    window.sheets.dismiss()
                    sync.signedIn(target, username: name, retry: retry)
                } catch {
                    busy = false
                    window.sheets.dismiss()
                    sync.failed(error, kind: nil, retry: nil)
                }
            }
        }
    }
}
