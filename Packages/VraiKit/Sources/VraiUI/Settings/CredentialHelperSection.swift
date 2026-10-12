import SwiftUI
import VraiCore
import VraiGit

enum CredentialChoices {
    static let none = ""
    static let manager = CredentialHelper.Kind.manager.rawValue
    static let keychain = CredentialHelper.Kind.keychain.rawValue
    static let store = CredentialHelper.Kind.store.rawValue
    static let cache = CredentialHelper.Kind.cache.rawValue

    static func selection(_ setup: CredentialSetup) -> String {
        guard let first = setup.primary else { return none }
        switch first.kind {
        case .manager: return setup.manager == nil ? first.value : manager
        case .keychain, .cache, .store: return first.kind.rawValue
        case .other: return first.value
        }
    }

    static func options(_ setup: CredentialSetup) -> [SettingsOption<String>] {
        let current = selection(setup)
        var out: [SettingsOption<String>] = []
        if setup.manager != nil { out.append(SettingsOption(value: manager, label: String(localized: "Git Credential Manager", bundle: .module))) }
        if setup.keychainAvailable || current == keychain { out.append(SettingsOption(value: keychain, label: String(localized: "Your login keychain", bundle: .module))) }
        out.append(SettingsOption(value: store, label: String(localized: "A plain text file", bundle: .module)))
        if current == cache { out.append(SettingsOption(value: cache, label: String(localized: "Memory, for 15 minutes", bundle: .module))) }
        if current != none, !out.contains(where: { $0.value == current }) {
            out.append(SettingsOption(value: current, label: setup.primary?.displayName ?? current))
        }
        out.append(SettingsOption(value: none, label: String(localized: "Nowhere, ask every time", bundle: .module)))
        return out
    }

    static func label(_ value: String) -> String {
        switch value {
        case manager: String(localized: "Git Credential Manager", bundle: .module)
        case keychain: String(localized: "your login keychain", bundle: .module)
        case cache: String(localized: "memory", bundle: .module)
        case store: String(localized: "a plain text file", bundle: .module)
        default: String(localized: "another helper", bundle: .module)
        }
    }
}

enum AccountsCopy {
    static func names(_ setup: CredentialSetup) -> [String] {
        CredentialHelper.displayNames(setup.helpers).map { name in
            guard name == CredentialHelper.managerName, let version = setup.managerVersion else { return name }
            return name + " " + version
        }
    }

    static func summary(_ setup: CredentialSetup?) -> String {
        guard let setup else { return String(localized: "Reading credential.helper\u{2026}", bundle: .module) }
        let names = names(setup)
        switch names.count {
        case 0: return String(localized: "No helper is set, so git asks for a password every time.", bundle: .module)
        case 1: return String(localized: "git uses \(names[0]).", bundle: .module)
        default: return String(localized: "git asks \(SettingsCopy.list(names)), in that order.", bundle: .module)
        }
    }

    static func storage(_ setup: CredentialSetup, environment: [String: String]) -> String {
        guard let first = setup.primary else { return String(localized: "No credential helper is set, so git saves no tokens and asks every time.", bundle: .module) }
        switch first.kind {
        case .manager:
            let store = setup.managerStore?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            if !store.isEmpty, store != "keychain" { return String(localized: "Git Credential Manager keeps tokens in its \(store) store.", bundle: .module) }
            return String(localized: "Git Credential Manager keeps tokens in your login keychain.", bundle: .module)
        case .keychain:
            return String(localized: "git's osxkeychain helper keeps tokens in your login keychain.", bundle: .module)
        case .store:
            let path = CredentialHelperCommands.expandHome(first.file ?? "~/.git-credentials", home: environment["HOME"])
            return String(localized: "git credential-store keeps tokens unencrypted in \(GlobalConfigFile.display(path, environment: environment)).", bundle: .module)
        case .cache:
            return String(localized: "git credential-cache keeps tokens in memory for a while, then forgets them.", bundle: .module)
        case .other:
            return String(localized: "git hands tokens to \(first.displayName).", bundle: .module)
        }
    }

    static func origin(_ entries: [ConfigEntry], file: String, environment: [String: String]) -> String {
        let helpers = entries.filter { ConfigCommands.canonical($0.key) == CredentialHelperCommands.key }
        let outside = helpers.filter { $0.scope != .global }
        guard !helpers.isEmpty, !helpers.contains(where: { $0.scope == .global }), !outside.isEmpty else {
            return SettingsCopy.stored(in: file, as: [CredentialHelperCommands.key])
        }
        var seen: Set<String> = []
        let origins = outside.compactMap { entry -> String? in
            guard let origin = entry.origin else { return nil }
            let path = origin.hasPrefix("file:") ? String(origin.dropFirst("file:".count)) : origin
            return GlobalConfigFile.display(path, environment: environment)
        }.filter { seen.insert($0).inserted }
        guard !origins.isEmpty else { return SettingsCopy.stored(in: file, as: [CredentialHelperCommands.key]) }
        return String(localized: "Set in \(SettingsCopy.list(origins)) as credential.helper. A new choice goes in \(file).", bundle: .module)
    }
}

struct CredentialHelperSection: View {
    let context: SettingsContext
    let git: GitSettings
    let setup: CredentialSetup?
    @State private var working: String?

    var helpers: [CredentialHelper] { setup?.helpers ?? [] }

    var footer: String {
        AccountsCopy.origin(git.table, file: context.app.globalConfigDisplay, environment: context.app.environment.base)
    }

    var body: some View {
        SettingsSection(String(localized: "Passwords", bundle: .module), description: String(localized: "git asks a credential helper for HTTPS passwords and tokens.", bundle: .module), footer: footer) {
            SettingsRow(String(localized: "Remember passwords in", bundle: .module), description: AccountsCopy.summary(setup)) {
                SettingsSelect(
                    label: String(localized: "Remember passwords in", bundle: .module),
                    options: setup.map(CredentialChoices.options) ?? [],
                    selection: setup.map(CredentialChoices.selection) ?? CredentialChoices.none,
                    id: "settings.credentialHelper",
                    disabled: setup == nil || working != nil
                ) { value in
                    choose(value)
                }
            }
            if let setup, setup.manager == nil {
                SettingsRow(String(localized: "Git Credential Manager", bundle: .module), description: String(localized: "Not installed. Install it to sign in to GitHub in your browser.", bundle: .module)) {
                    VraiButton(title: String(localized: "Copy install command", bundle: .module), icon: "doc.on.doc", size: .small, action: copyInstall)
                        .accessibilityIdentifier("settings.credentialManager.copyInstall")
                }
            }
            if helpers.contains(where: { $0.kind == .cache }) {
                SettingsRow(String(localized: "Passwords in memory", bundle: .module), description: String(localized: "git credential-cache keeps them for a while after you sign in.", bundle: .module)) {
                    if working == "cache" {
                        Spinner()
                    } else {
                        VraiButton(title: String(localized: "Forget now", bundle: .module), icon: "trash", size: .small, action: forgetCached)
                            .accessibilityIdentifier("settings.credentialCache.exit")
                    }
                }
            }
            if let store = helpers.first(where: { $0.kind == .store }) {
                SettingsRow(String(localized: "Saved passwords", bundle: .module), description: String(localized: "git credential-store keeps them unencrypted in \(store.file ?? "~/.git-credentials").", bundle: .module)) {
                    if working == "store" {
                        Spinner()
                    } else {
                        VraiButton(title: String(localized: "Delete\u{2026}", bundle: .module), icon: "trash", size: .small, action: confirmDelete)
                            .accessibilityIdentifier("settings.credentialStore.erase")
                    }
                }
            }
        }
    }

    func choose(_ value: String) {
        guard let setup, value != CredentialChoices.selection(setup) else { return }
        working = "helper"
        context.run {
            defer { working = nil }
            switch value {
            case CredentialChoices.none:
                try await git.clearCredentialHelpers()
                context.toast(String(localized: "git now asks for a password every time", bundle: .module), detail: String(localized: "Passwords saved by the previous helper stay where they are.", bundle: .module), icon: "key")
                return
            case CredentialChoices.manager:
                guard let manager = setup.manager else { return }
                try await git.setCredentialManager(manager)
            default:
                guard let kind = CredentialHelper.Kind(rawValue: value), kind.configValue != nil else { return }
                try await git.setCredentialHelper(kind)
            }
            context.toast(String(localized: "git now remembers passwords in \(CredentialChoices.label(value))", bundle: .module), detail: String(localized: "Passwords saved by the previous helper stay where they are.", bundle: .module), icon: "key")
        }
    }

    func copyInstall() {
        Clipboard.copy(CredentialManager.installCommand)
        context.toast(String(localized: "Copied the install command", bundle: .module), detail: CredentialManager.installCommand, icon: "doc.on.doc")
    }

    func forgetCached() {
        working = "cache"
        context.run {
            defer { working = nil }
            try await git.forgetCachedPasswords()
            context.toast(String(localized: "Forgot the passwords in memory", bundle: .module), detail: String(localized: "git asks again the next time a remote needs one.", bundle: .module), icon: "key")
        }
    }

    func confirmDelete() {
        context.window?.alerts.present(AlertRequest(
            title: String(localized: "Delete saved passwords?", bundle: .module),
            message: String(localized: "git credential-store removes every HTTPS password it saved. Remotes ask you to sign in again.", bundle: .module),
            actions: [
                AlertAction(title: String(localized: "Delete", bundle: .module), role: .destructive) { deleteSaved() },
                AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel)
            ]
        ))
    }

    func deleteSaved() {
        working = "store"
        context.run {
            defer { working = nil }
            try await git.deleteSavedPasswords()
            context.toast(String(localized: "Deleted the saved passwords", bundle: .module), detail: String(localized: "Sign in again when a remote asks.", bundle: .module), icon: "trash")
        }
    }
}
