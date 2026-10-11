import SwiftUI
import VraiCore
import VraiGit

struct MaintenanceEverywhereRow: View {
    let context: SettingsContext
    let store: RepositoryStore
    var registered: Bool?
    @State private var count: Int?
    @State private var running = false

    var body: some View {
        SettingsRow(String(localized: "Run for every registered repository", bundle: .module), description: description) {
            if running {
                Spinner()
            } else {
                VraiButton(title: String(localized: "Run all", bundle: .module), icon: "wrench.and.screwdriver", size: .small, action: run)
                    .disabled(count == 0)
                    .accessibilityIdentifier("settings.maintenance.everywhere")
            }
        }
        .task(id: registered) { count = await store.registeredRepositories().count }
    }

    var description: String {
        guard let count else { return String(localized: "Runs git maintenance in each repository listed in maintenance.repo.", bundle: .module) }
        if count == 0 { return String(localized: "No repository is registered yet. Turn on Background maintenance to add this one.", bundle: .module) }
        return String(localized: "Runs git maintenance in the \(n(count, "repository")) listed in maintenance.repo.", bundle: .module)
    }

    func run() {
        running = true
        context.run {
            defer { running = false }
            let summary = try await store.runMaintenanceEverywhere()
            count = summary.repositories
            if summary.unreachable.isEmpty {
                context.toast(String(localized: "Maintenance finished in \(n(summary.ran, "repository"))", bundle: .module), detail: String(localized: "git for-each-repo ran it in every registered repository.", bundle: .module), icon: "wrench.and.screwdriver")
            } else {
                let missing = summary.unreachable.map { URL(filePath: $0).lastPathComponent }.joined(separator: ", ")
                context.toast(String(localized: "Maintenance ran in \(summary.ran) of \(n(summary.repositories, "repository"))", bundle: .module), detail: String(localized: "git couldn't open \(missing). Remove it from maintenance.repo if it's gone.", bundle: .module), icon: "wrench.and.screwdriver", tone: .warning)
            }
        }
    }
}

struct CredentialHelperSection: View {
    let context: SettingsContext
    let git: GitSettings
    @State private var helpers: [CredentialHelper]?
    @State private var working: String?

    static let none = ""

    var body: some View {
        let list = helpers ?? []
        SettingsSection(String(localized: "Passwords", bundle: .module), description: String(localized: "git asks a credential helper for HTTPS passwords and tokens.", bundle: .module), footer: SettingsCopy.stored(in: context.app.globalConfigDisplay, as: [CredentialHelperCommands.key])) {
            SettingsRow(String(localized: "Remember passwords in", bundle: .module), description: summary(list)) {
                SettingsSelect(label: String(localized: "Remember passwords in", bundle: .module), options: options(list), selection: selection(list), id: "settings.credentialHelper", disabled: helpers == nil || working != nil) { value in
                    choose(value)
                }
            }
            if list.contains(where: { $0.kind == .cache }) {
                SettingsRow(String(localized: "Passwords in memory", bundle: .module), description: String(localized: "git credential-cache keeps them for a while after you sign in.", bundle: .module)) {
                    if working == "cache" {
                        Spinner()
                    } else {
                        VraiButton(title: String(localized: "Forget now", bundle: .module), icon: "trash", size: .small, action: forgetCached)
                            .accessibilityIdentifier("settings.credentialCache.exit")
                    }
                }
            }
            if let store = list.first(where: { $0.kind == .store }) {
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
        .task(id: git.revision) { helpers = await git.credentialHelpers() }
    }

    func selection(_ list: [CredentialHelper]) -> String {
        guard let first = list.first else { return Self.none }
        return first.kind == .other ? first.value : first.kind.rawValue
    }

    func options(_ list: [CredentialHelper]) -> [SettingsOption<String>] {
        var out = [
            SettingsOption(value: CredentialHelper.Kind.keychain.rawValue, label: String(localized: "Your login keychain", bundle: .module)),
            SettingsOption(value: CredentialHelper.Kind.cache.rawValue, label: String(localized: "Memory, for 15 minutes", bundle: .module)),
            SettingsOption(value: CredentialHelper.Kind.store.rawValue, label: String(localized: "A plain text file", bundle: .module))
        ]
        if let first = list.first, first.kind == .other { out.append(SettingsOption(value: first.value, label: first.value)) }
        if list.isEmpty { out.insert(SettingsOption(value: Self.none, label: String(localized: "Nowhere, ask every time", bundle: .module)), at: 0) }
        return out
    }

    func summary(_ list: [CredentialHelper]) -> String {
        guard helpers != nil else { return String(localized: "Reading credential.helper\u{2026}", bundle: .module) }
        if list.isEmpty { return String(localized: "No helper is set, so git asks for a password every time.", bundle: .module) }
        let names = list.map(\.name)
        if names.count == 1 { return String(localized: "git uses \(names[0]).", bundle: .module) }
        return String(localized: "git asks \(SettingsCopy.list(names)), in that order.", bundle: .module)
    }

    func choose(_ value: String) {
        guard let kind = CredentialHelper.Kind(rawValue: value), kind != .other, value != selection(helpers ?? []) else { return }
        working = "helper"
        context.run {
            defer { working = nil }
            try await git.setCredentialHelper(kind)
            helpers = await git.credentialHelpers()
            context.toast(String(localized: "git now remembers passwords in \(label(kind))", bundle: .module), detail: String(localized: "Passwords saved by the previous helper stay where they are.", bundle: .module), icon: "key")
        }
    }

    func label(_ kind: CredentialHelper.Kind) -> String {
        switch kind {
        case .keychain: String(localized: "your login keychain", bundle: .module)
        case .cache: String(localized: "memory", bundle: .module)
        case .store: String(localized: "a plain text file", bundle: .module)
        case .other: String(localized: "another helper", bundle: .module)
        }
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
