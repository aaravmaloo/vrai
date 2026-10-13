import SwiftUI
import VraiCore
import VraiGit

struct AccountHost: Hashable, Sendable {
    var host: String
    var url: String
    var probe: String
    var hint: String?
    var remote: String?
    var repository: String
    var optional = false
}

struct AccountItem: Identifiable, Hashable {
    enum Status: Hashable {
        case checking
        case ok
        case expired
        case none
    }

    var entry: AccountHost
    var username: String?
    var managed = false
    var status: Status

    var host: String { entry.host }
    var url: String { entry.url }
    var remote: String? { entry.remote }
    var repository: String { entry.repository }

    var id: String { url + "\u{0}" + (username ?? "") }
}

struct AccountProbeKey: Hashable {
    var hosts: [AccountHost]
    var accounts: [SignedInAccount]
    var setup: CredentialSetup?
    var refresh: Int
}

enum AccountList {
    @MainActor static func failing(_ windows: [WindowModel]) -> Set<String> {
        var failing: Set<String> = []
        for window in windows {
            if case .authFailed(let host?) = window.store.snapshot?.network { failing.insert(host.lowercased()) }
        }
        return failing
    }

    static func isFailing(_ host: String, in failing: Set<String>) -> Bool {
        let bare = host.split(separator: ":").first.map(String.init) ?? host
        return failing.contains(host.lowercased()) || failing.contains(bare.lowercased())
    }

    static func hosts(accounts: [SignedInAccount], remotes: [Remote], managed: Bool) -> [AccountHost] {
        var hosts: [AccountHost] = []
        func add(_ entry: AccountHost) {
            if let index = hosts.firstIndex(where: { $0.host.lowercased() == entry.host.lowercased() }) {
                if hosts[index].remote == nil, entry.remote != nil {
                    hosts[index].remote = entry.remote
                    hosts[index].probe = entry.probe
                    hosts[index].hint = hosts[index].hint ?? entry.hint
                }
                if hosts[index].repository.isEmpty { hosts[index].repository = entry.repository }
                hosts[index].optional = hosts[index].optional && entry.optional
                return
            }
            hosts.append(entry)
        }
        for account in accounts {
            add(AccountHost(host: account.host, url: account.url, probe: account.url, remote: nil, repository: ""))
        }
        for remote in remotes {
            let address = remote.pushURL ?? remote.fetchURL
            guard let parsed = RemoteURL(address), parsed.kind == .network, parsed.scheme == "https" || parsed.scheme == "http", let host = parsed.hostAndPort else { continue }
            add(AccountHost(host: host, url: (parsed.scheme ?? "https") + "://" + host, probe: address, hint: parsed.user, remote: remote.name, repository: parsed.repositoryPath))
        }
        if managed {
            add(AccountHost(host: "github.com", url: CredentialManager.defaultURL, probe: CredentialManager.defaultURL, repository: "", optional: true))
        }
        return hosts
    }

    static func items(hosts: [AccountHost], lookups: [String: AccountLookup], failing: Set<String> = []) -> [AccountItem] {
        var items: [AccountItem] = []
        for entry in hosts {
            let expired = isFailing(entry.host, in: failing)
            let lookup = lookups[entry.url]
            let names = lookup?.usernames ?? []
            if names.isEmpty {
                guard !entry.optional else { continue }
                let status: AccountItem.Status = expired ? .expired : (lookup == nil ? .checking : .none)
                items.append(AccountItem(entry: entry, username: entry.hint, status: status))
                continue
            }
            for name in names {
                items.append(AccountItem(entry: entry, username: name, managed: lookup?.managed.contains(name) == true, status: expired ? .expired : .ok))
            }
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
    @State private var signingIn: String?
    @State private var login: Task<Void, Never>?
    @State private var setup: CredentialSetup?
    @State private var lookups: [String: AccountLookup] = [:]
    @State private var refresh = 0

    var hub: SettingsHub { SettingsHub.shared }
    var file: String { context.app.globalConfigDisplay }

    var hosts: [AccountHost] {
        AccountList.hosts(accounts: preferences.accounts, remotes: hub.activeWindow?.store.snapshot?.remotes ?? [], managed: setup?.managerActive == true)
    }

    var body: some View {
        let hosts = hosts
        let list = AccountList.items(hosts: hosts, lookups: lookups, failing: AccountList.failing(hub.openWindows))
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
            SettingsSection(String(localized: "Accounts", bundle: .module)) {
                if list.isEmpty {
                    SettingsRow(String(localized: "No accounts yet", bundle: .module), description: String(localized: "Open a repository with an HTTPS remote to sign in to its host, or sign in when git asks.", bundle: .module), icon: "globe")
                } else {
                    ForEach(list) { item in
                        AccountRow(
                            item: item,
                            busy: signingOut == item.id,
                            waiting: signingIn == item.id,
                            locked: signingIn != nil,
                            signIn: { signIn(item) },
                            signOut: { signOut(item) },
                            cancel: { login?.cancel() }
                        )
                    }
                }
            }
            CredentialHelperSection(context: context, git: git, setup: setup)
            SettingsSection(String(localized: "SSH keys", bundle: .module)) {
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
            SettingsSection(String(localized: "Signing", bundle: .module)) {
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
            SettingsSection(String(localized: "Identity", bundle: .module)) {
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
        }
        .task(id: git.revision) {
            setup = await git.credentialSetup { context.app.locateCredentialManager($0) }
        }
        .task(id: AccountProbeKey(hosts: hosts, accounts: preferences.accounts, setup: setup, refresh: refresh)) {
            await probe(hosts)
        }
        .onDisappear { login?.cancel() }
    }

    func probe(_ hosts: [AccountHost]) async {
        guard let setup, let accounts = try? context.app.credentialAccounts(setup) else { return }
        let found = await withTaskGroup(of: (String, AccountLookup).self) { group in
            for host in hosts {
                group.addTask { (host.url, await accounts.lookup(url: host.probe, username: host.hint)) }
            }
            var found: [String: AccountLookup] = [:]
            for await (url, lookup) in group { found[url] = lookup }
            return found
        }
        guard !Task.isCancelled else { return }
        lookups = found
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
        if let setup, setup.managerActive, CredentialManager.isGitHub(host: item.host) {
            signInInBrowser(item, setup: setup)
            return
        }
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

    func signInInBrowser(_ item: AccountItem, setup: CredentialSetup) {
        guard signingIn == nil else { return }
        signingIn = item.id
        let known = lookups[item.url]?.usernames ?? []
        let host = RemoteURL(item.url)?.host ?? item.host
        login = Task { @MainActor in
            defer {
                signingIn = nil
                login = nil
            }
            do {
                let added = try await context.app.signInWithCredentialManager(url: item.url, setup: setup, known: known)
                refresh += 1
                guard let added else { return }
                context.toast(String(localized: "Signed in to \(host) as \(added)", bundle: .module), detail: AccountsCopy.storage(setup, environment: context.app.environment.base), icon: "checkmark.seal")
            } catch let error as GitError where error.code == .cancelled {
                return
            } catch {
                context.fail(error)
            }
        }
    }

    func signOut(_ item: AccountItem) {
        guard let name = item.username else { return }
        let host = RemoteURL(item.url)?.host ?? item.host
        let request = SensitiveRequest(
            title: String(localized: "Sign out of \(host) as \(name)", bundle: .module),
            detail: String(localized: "git forgets the token. HTTPS remotes on \(host) ask you to sign in again.", bundle: .module),
            reason: String(localized: "sign out of \(host)", bundle: .module),
            icon: "person.crop.circle"
        )
        Sensitive.confirm(request, preferences: context.app.preferences, source: nil, alert: { signOutNow(item) }, perform: { signOutNow(item) })
    }

    func signOutNow(_ item: AccountItem) {
        guard let name = item.username, let setup else { return }
        let host = RemoteURL(item.url)?.host ?? item.host
        signingOut = item.id
        context.run {
            defer { signingOut = nil }
            try await context.app.signOut(url: item.entry.probe, username: name, setup: setup)
            refresh += 1
            context.toast(String(localized: "Signed out of \(host)", bundle: .module), detail: String(localized: "Remotes that use SSH keep working. HTTPS remotes ask you to sign in.", bundle: .module), icon: "person.crop.circle")
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
    let waiting: Bool
    let locked: Bool
    let signIn: () -> Void
    let signOut: () -> Void
    let cancel: () -> Void

    var detail: String {
        let name = item.username ?? ""
        if waiting { return String(localized: "Waiting for your browser\u{2026}", bundle: .module) }
        switch item.status {
        case .checking:
            if let remote = item.remote { return String(localized: "Used by \(remote). Checking with git\u{2026}", bundle: .module) }
            return String(localized: "Checking with git\u{2026}", bundle: .module)
        case .ok:
            if let remote = item.remote { return String(localized: "Used by \(remote). Signed in as \(name)", bundle: .module) }
            return String(localized: "Signed in as \(name)", bundle: .module)
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
            if waiting {
                Spinner()
                VraiButton(title: String(localized: "Cancel", bundle: .module), size: .small, action: cancel)
                    .accessibilityIdentifier("settings.signInCancel." + item.host)
            } else if busy || item.status == .checking {
                Spinner()
            } else {
                switch item.status {
                case .ok:
                    VraiButton(title: String(localized: "Sign out", bundle: .module), size: .small, action: signOut)
                        .accessibilityIdentifier("settings.signOut." + item.host)
                case .expired:
                    VraiButton(title: String(localized: "Sign in again", bundle: .module), variant: .primary, size: .small, action: signIn)
                        .disabled(locked)
                        .accessibilityIdentifier("settings.signIn." + item.host)
                case .none, .checking:
                    VraiButton(title: String(localized: "Sign in\u{2026}", bundle: .module), size: .small, action: signIn)
                        .disabled(locked)
                        .accessibilityIdentifier("settings.signIn." + item.host)
                }
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
