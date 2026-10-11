import SwiftUI
import VraiCore
import VraiGit

struct AccountItem: Identifiable, Hashable {
    enum Status: Hashable {
        case ok
        case expired
        case none
    }

    var host: String
    var url: String
    var username: String?
    var account: SignedInAccount?
    var status: Status
    var remote: String?
    var repository: String

    var id: String { url + "\u{0}" + (username ?? "") }
}

enum AccountList {
    @MainActor static func items(accounts: [SignedInAccount], windows: [WindowModel], active: WindowModel?) -> [AccountItem] {
        var failing: Set<String> = []
        for window in windows {
            if case .authFailed(let host?) = window.store.snapshot?.network { failing.insert(host.lowercased()) }
        }
        func expired(_ host: String) -> Bool {
            let bare = host.split(separator: ":").first.map(String.init) ?? host
            return failing.contains(host.lowercased()) || failing.contains(bare.lowercased())
        }
        var items: [AccountItem] = accounts.map { account in
            AccountItem(host: account.host, url: account.url, username: account.username, account: account, status: expired(account.host) ? .expired : .ok, remote: nil, repository: "")
        }
        let remotes = active?.store.snapshot?.remotes ?? []
        for remote in remotes {
            let address = remote.pushURL ?? remote.fetchURL
            guard let parsed = RemoteURL(address), parsed.kind == .network, parsed.scheme == "https" || parsed.scheme == "http", let host = parsed.hostAndPort else { continue }
            if let index = items.firstIndex(where: { $0.host.lowercased() == host.lowercased() }) {
                items[index].remote = items[index].remote ?? remote.name
                items[index].repository = items[index].repository.isEmpty ? parsed.repositoryPath : items[index].repository
                continue
            }
            items.append(AccountItem(host: host, url: (parsed.scheme ?? "https") + "://" + host, username: parsed.user, account: nil, status: expired(host) ? .expired : .none, remote: remote.name, repository: parsed.repositoryPath))
        }
        return items
    }
}

struct AccountsPane: View {
    let context: SettingsContext

    var body: some View {
        GitSettingsGate(context: context) { git in
            AccountsForm(context: context, git: git)
        }
    }
}

struct AccountsForm: View {
    let context: SettingsContext
    let git: GitSettings
    @Environment(Preferences.self) private var preferences
    @Environment(\.settingsNarrow) private var narrow
    @State private var signingOut: String?

    var hub: SettingsHub { SettingsHub.shared }
    var file: String { context.app.globalConfigDisplay }

    var items: [AccountItem] {
        AccountList.items(accounts: preferences.accounts, windows: hub.openWindows, active: hub.activeWindow)
    }

    var sshFolder: String {
        GlobalConfigFile.display(SettingsCopy.trimmed(context.app.sshFolder.path(percentEncoded: false)), environment: context.app.environment.base)
    }

    var body: some View {
        let list = items
        let signing = git.signing
        SettingsForm {
            if let failing = list.first(where: { $0.status == .expired }) {
                Section {
                    SettingsCallout(
                        tone: .danger,
                        title: SyncCopyBridge.authTitle(host: RemoteURL(failing.url)?.host ?? failing.host, repository: failing.repository),
                        message: String(localized: "Fetch, pull and push to \(failing.remote ?? failing.host) fail until you sign in again.", bundle: .module)
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            SettingsSection(String(localized: "Accounts", bundle: .module), footer: storageFooter) {
                if list.isEmpty {
                    SettingsRow(String(localized: "No accounts yet", bundle: .module), description: String(localized: "Open a repository with an HTTPS remote to sign in to its host, or sign in when git asks.", bundle: .module), icon: "globe")
                } else {
                    ForEach(list) { item in
                        AccountRow(item: item, busy: signingOut == item.id, signIn: { signIn(item) }, signOut: { signOut(item) })
                    }
                }
            }
            SettingsSection(String(localized: "Identity", bundle: .module), description: String(localized: "Every commit you make records this name and email.", bundle: .module), footer: SettingsCopy.stored(in: file, as: [ConfigKeys.userName, ConfigKeys.userEmail])) {
                SettingsRow(String(localized: "Name", bundle: .module)) {
                    CommitField(value: git.identity.name ?? "", label: String(localized: "Name", bundle: .module), placeholder: "Avery Chen", id: "settings.userName", validate: { $0.isEmpty ? String(localized: "Enter a name.", bundle: .module) : nil }) { name in
                        context.run { try await git.setName(name) }
                    }
                }
                SettingsRow(String(localized: "Email", bundle: .module)) {
                    CommitField(value: git.identity.email ?? "", label: String(localized: "Email", bundle: .module), placeholder: "avery@vrai.app", id: "settings.userEmail", validate: { Identity.isValidEmail($0) ? nil : String(localized: "Enter an email address.", bundle: .module) }) { email in
                        context.run { try await git.setEmail(email) }
                    }
                }
            }
            SettingsSection(String(localized: "SSH keys", bundle: .module), footer: String(localized: "Keys live in \(sshFolder). ssh-agent loads them from your keychain.", bundle: .module)) {
                if context.sshKeys.isEmpty {
                    SettingsRow(String(localized: "No SSH keys yet", bundle: .module), description: String(localized: "Create one in Terminal with ssh-keygen -t ed25519.", bundle: .module), icon: "key")
                } else {
                    ForEach(context.sshKeys) { key in
                        SettingsRow(key.name, description: keyDescription(key, signing: signing), icon: "key", mono: true) {
                            VraiButton(title: String(localized: "Copy public key", bundle: .module), icon: "doc.on.doc", size: .small) {
                                Clipboard.copy(key.publicKey)
                                context.toast(String(localized: "Copied the public key", bundle: .module), detail: key.name + ".pub", icon: "doc.on.doc")
                            }
                            .accessibilityIdentifier("settings.copyKey." + key.name)
                        }
                    }
                }
            }
            SettingsSection(String(localized: "Signing", bundle: .module), footer: SettingsCopy.stored(in: file, as: [ConfigKeys.commitSign, ConfigKeys.tagSign, ConfigKeys.signFormat, ConfigKeys.signingKey])) {
                SettingsRow(String(localized: "Sign commits and tags", bundle: .module), description: String(localized: "Lets others check that your commits really come from you.", bundle: .module)) {
                    SettingsSwitch(label: String(localized: "Sign commits and tags", bundle: .module), isOn: signing.commits, id: "settings.signing") { on in context.run { try await git.setSigning(on) } }
                }
                SettingsRow(String(localized: "Sign with", bundle: .module), description: formatDescription(signing), stacked: narrow) {
                    SettingsSegments(
                        label: String(localized: "Sign with", bundle: .module),
                        items: SignFormat.allCases.map { SegmentItem(value: $0, title: $0.keyType, label: $0.keyType) },
                        selection: signing.format,
                        id: "settings.signFormat"
                    ) { format in context.run { try await git.setSignFormat(format) } }
                }
                SigningKeyRow(context: context, git: git, signing: signing)
                SettingsRow(String(localized: "Your commits show as", bundle: .module)) {
                    SignatureBadge(state: signing.commits ? .verified : .unsigned, signer: git.identity.name, keyType: signing.format.keyType)
                }
            }
        }
    }

    var storageFooter: String {
        context.app.launch.isSandboxed
            ? String(localized: "Tokens are stored in the sandbox credential store, $VRAI_SANDBOX/git-credentials.", bundle: .module)
            : String(localized: "Tokens are stored in your login keychain through git's osxkeychain credential helper.", bundle: .module)
    }

    func keyDescription(_ key: SSHKey, signing: SigningSettings) -> String {
        var parts = [key.type]
        if let fingerprint = key.fingerprint { parts.append(fingerprint) }
        var text = parts.joined(separator: ", ") + "."
        if let comment = key.comment, !comment.isEmpty { text += " " + comment + "." }
        if signing.format == .ssh, SSHKeys.matches(key, signingKey: signing.key) { text += " " + String(localized: "Used for signing.", bundle: .module) }
        return text
    }

    func formatDescription(_ signing: SigningSettings) -> String {
        let key = signing.key.map { GlobalConfigFile.display($0, environment: context.app.environment.base) }
        switch signing.format {
        case .ssh:
            return key.map { String(localized: "Key \($0).", bundle: .module) } ?? String(localized: "Choose one of your SSH keys below.", bundle: .module)
        case .openpgp:
            return key.map { String(localized: "Key \($0) from your GPG keychain.", bundle: .module) } ?? String(localized: "Enter the ID of a key in your GPG keychain below.", bundle: .module)
        case .x509:
            return key.map { String(localized: "Certificate for \($0), through gpg.x509.program.", bundle: .module) } ?? String(localized: "Enter the certificate ID below.", bundle: .module)
        }
    }

    func signIn(_ item: AccountItem) {
        guard let window = context.window else { return }
        let fresh = item.status == .none
        let target = SignInTarget(
            remote: nil,
            url: item.url,
            host: RemoteURL(item.url)?.host ?? item.host,
            repository: item.repository,
            username: item.username ?? "",
            note: fresh ? String(localized: "Enter your username and a personal access token for \(item.host).", bundle: .module) : nil
        )
        window.sheets.present { SignInSheet(again: target, retry: nil) }
    }

    func signOut(_ item: AccountItem) {
        guard let account = item.account else { return }
        signingOut = item.id
        context.run {
            defer { signingOut = nil }
            try await context.app.signOut(account)
            context.toast(String(localized: "Signed out of \(account.displayHost)", bundle: .module), detail: String(localized: "Remotes that use SSH keep working. HTTPS remotes ask you to sign in.", bundle: .module), icon: "person.crop.circle")
        }
    }
}

enum SyncCopyBridge {
    static func authTitle(host: String, repository: String) -> String {
        SyncCopy.authTitle(host: host, repository: repository).trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}

struct AccountRow: View {
    let item: AccountItem
    let busy: Bool
    let signIn: () -> Void
    let signOut: () -> Void

    var detail: String {
        let name = item.username ?? ""
        switch item.status {
        case .ok:
            if let account = item.account { return String(localized: "\(name), signed in \(SettingsCopy.day(account.signedIn))", bundle: .module) }
            return name
        case .expired:
            return name.isEmpty ? String(localized: "The server no longer accepts the saved token", bundle: .module) : String(localized: "\(name), the server no longer accepts the saved token", bundle: .module)
        case .none:
            if let remote = item.remote { return String(localized: "Used by \(remote). Not signed in", bundle: .module) }
            return String(localized: "Not signed in", bundle: .module)
        }
    }

    var body: some View {
        HStack(spacing: Vrai.Space.s10) {
            Symbol("globe", font: Font.Vrai.title3.weight(.regular))
                .foregroundStyle(Color.Vrai.textSecondary)
                .frame(width: Vrai.Size.control + Vrai.Space.s4, height: Vrai.Size.control + Vrai.Space.s4)
                .background(Color.Vrai.fillActive, in: RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                Text(item.host)
                    .font(Font.Vrai.headline)
                    .foregroundStyle(Color.Vrai.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.status == .expired {
                Badge(text: String(localized: "Expired", bundle: .module), tone: .danger)
            }
            switch item.status {
            case .ok:
                if busy {
                    Spinner()
                } else {
                    VraiButton(title: String(localized: "Sign out", bundle: .module), size: .small, action: signOut)
                        .accessibilityIdentifier("settings.signOut." + item.host)
                }
            case .expired:
                VraiButton(title: String(localized: "Sign in again", bundle: .module), variant: .primary, size: .small, action: signIn)
                    .accessibilityIdentifier("settings.signIn." + item.host)
            case .none:
                VraiButton(title: String(localized: "Sign in\u{2026}", bundle: .module), size: .small, action: signIn)
                    .accessibilityIdentifier("settings.signIn." + item.host)
            }
        }
        .padding(.vertical, Vrai.Space.s4)
        .accessibilityElement(children: .contain)
    }
}

struct SigningKeyRow: View {
    let context: SettingsContext
    let git: GitSettings
    let signing: SigningSettings

    var current: String { signing.key ?? "" }

    var selected: String {
        context.sshKeys.first { SSHKeys.matches($0, signingKey: current) }.map { SSHKeys.signingKeyValue(for: $0) } ?? current
    }

    var options: [SettingsOption<String>] {
        var options = context.sshKeys.map { SettingsOption(value: SSHKeys.signingKeyValue(for: $0), label: $0.name + ".pub") }
        if !current.isEmpty, !options.contains(where: { $0.value == selected }) {
            options.append(SettingsOption(value: current, label: GlobalConfigFile.display(current, environment: context.app.environment.base)))
        }
        if selected.isEmpty { options.insert(SettingsOption(value: "", label: String(localized: "Choose a key", bundle: .module)), at: 0) }
        return options
    }

    var body: some View {
        switch signing.format {
        case .ssh:
            SettingsRow(String(localized: "Signing key", bundle: .module)) {
                SettingsSelect(label: String(localized: "Signing key", bundle: .module), options: options, selection: selected, id: "settings.signingKey") { value in
                    guard !value.isEmpty else { return }
                    context.run { try await git.setSigningKey(value) }
                }
            }
        case .openpgp, .x509:
            SettingsRow(signing.format == .x509 ? String(localized: "Certificate", bundle: .module) : String(localized: "Key ID", bundle: .module)) {
                CommitField(value: current, label: String(localized: "Signing key", bundle: .module), placeholder: signing.format == .x509 ? "avery@vrai.app" : "4AEE18F83AFDEB23", mono: true, id: "settings.signingKey") { value in
                    context.run { try await git.setSigningKey(value) }
                }
            }
        }
    }
}
