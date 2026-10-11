import SwiftUI
import VraiCore
import VraiGit

struct ExpertPane: View {
    let context: SettingsContext
    @Environment(Preferences.self) private var preferences
    @State private var entries: [ConfigEntry] = []
    @State private var loaded = false

    var hub: SettingsHub { SettingsHub.shared }
    var window: WindowModel? { hub.activeWindow?.store.snapshot != nil ? hub.activeWindow : nil }
    var repositoryName: String? { window?.repositoryName }

    var body: some View {
        SettingsForm {
            SettingsSection(String(localized: "Expert mode", bundle: .module), footer: String(localized: "Everything Expert mode adds is also in the menus and the palette.", bundle: .module)) {
                SettingsRow(String(localized: "Expert mode", bundle: .module), description: String(localized: "Command previews in every sheet, a git prompt in the console, Reflog and Refs in the sidebar, and tools that rewrite history.", bundle: .module)) {
                    SettingsSwitch(label: String(localized: "Expert mode", bundle: .module), isOn: preferences.expert, id: "settings.expert") { preferences.expert = $0 }
                }
                SettingsRow(String(localized: "Show commands in sheets", bundle: .module), description: preferences.expert ? String(localized: "Always on in Expert mode.", bundle: .module) : String(localized: "Each sheet shows the git command it runs, under Options.", bundle: .module)) {
                    SettingsSwitch(label: String(localized: "Show commands in sheets", bundle: .module), isOn: preferences.expert || preferences.commandPreviews, id: "settings.commandPreviews", disabled: preferences.expert) { preferences.commandPreviews = $0 }
                }
            }
            if !preferences.expert {
                Section {
                    SettingsCallout(tone: .info, title: String(localized: "Git configuration is read only", bundle: .module), message: String(localized: "Turn on Expert mode to edit these values. Everyday settings are in the other tabs.", bundle: .module)) {
                        VraiButton(title: String(localized: "Turn on Expert mode", bundle: .module), icon: "terminal", size: .small) { preferences.expert = true }
                            .accessibilityIdentifier("settings.expert.turnOn")
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            SettingsSection(
                String(localized: "Git configuration", bundle: .module),
                description: repositoryName.map { String(localized: "Every value git reads in \($0). Local beats global, and global beats system.", bundle: .module) } ?? String(localized: "Every value git reads outside a repository. Global beats system.", bundle: .module),
                footer: String(localized: "local is .git/config, global is \(context.app.globalConfigDisplay), system is the gitconfig that ships with git.", bundle: .module)
            ) {
                ConfigTableHeader()
                if loaded && entries.isEmpty {
                    Text("git reads no configuration here.", bundle: .module)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textTertiary)
                }
                let config = RepositoryConfig(entries: entries)
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    ConfigRow(entry: entry, editable: preferences.expert && entry.scope.isWritable, overridden: config.isOverridden(entry), update: { update(entry, to: $0) }, remove: { remove(entry) })
                }
                if preferences.expert {
                    AddConfigRow(scopes: window == nil ? [.global] : [.local, .global]) { scope, key, value in add(scope: scope, key: key, value: value) }
                }
            }
        }
        .task(id: window.map { ObjectIdentifier($0) }) { await load() }
        .onChange(of: context.git?.revision) { _, _ in
            if window == nil { Task { await load() } }
        }
    }

    func load() async {
        if let window {
            entries = (try? await window.store.configTable()) ?? []
        } else if let git = context.git {
            await git.reload()
            entries = git.table
        }
        loaded = true
    }

    func perform(_ body: @escaping @MainActor () async throws -> Void) {
        context.run {
            defer { Task { await load() } }
            try await body()
            await context.git?.reload()
        }
    }

    func update(_ entry: ConfigEntry, to value: String) {
        perform {
            if let window {
                try await window.store.replaceConfig(key: entry.key, old: entry.value, new: value, scope: entry.scope)
            } else if let git = context.git {
                try await git.git.run(ConfigCommands.replace(entry.key, old: entry.value, new: value, scope: entry.scope))
            }
        }
    }

    func remove(_ entry: ConfigEntry) {
        perform {
            if let window {
                try await window.store.removeConfig(key: entry.key, value: entry.value, scope: entry.scope)
            } else if let git = context.git {
                try await git.git.run(ConfigCommands.remove(entry.key, value: entry.value, scope: entry.scope))
            }
        }
    }

    func add(scope: ConfigEntry.Scope, key: String, value: String) {
        perform {
            if let window {
                try await window.store.setConfig(key: key, value: value, scope: scope)
            } else if let git = context.git {
                try await git.set(key, value)
            }
        }
    }
}

struct ConfigTableHeader: View {
    var body: some View {
        HStack(spacing: Vrai.Space.s12) {
            Text("Scope", bundle: .module).frame(width: SettingsMetrics.scopeColumn, alignment: .leading)
            Text("Key", bundle: .module).frame(maxWidth: .infinity, alignment: .leading)
            Text("Value", bundle: .module).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(Font.Vrai.captionStrong)
        .foregroundStyle(Color.Vrai.textSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct ConfigRow: View {
    let entry: ConfigEntry
    let editable: Bool
    let overridden: Bool
    let update: (String) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: Vrai.Space.s12) {
            Badge(text: entry.scope.rawValue, tone: entry.scope == .local || entry.scope == .worktree ? .accent : .neutral)
                .frame(width: SettingsMetrics.scopeColumn, alignment: .leading)
            Text(entry.key)
                .font(Font.Vrai.codeSmall)
                .foregroundStyle(overridden ? Color.Vrai.textTertiary : Color.Vrai.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(entry.key)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Vrai.Space.s4) {
                if editable {
                    CommitField(value: entry.value, label: entry.key, mono: true, small: true, width: .infinity, id: "settings.config." + entry.scope.rawValue + "." + entry.key, validate: { $0.isEmpty ? String(localized: "Enter a value.", bundle: .module) : nil }, onCommit: update)
                    IconButton(icon: "minus.circle", label: String(localized: "Remove \(entry.key)", bundle: .module), small: true, action: remove)
                        .accessibilityIdentifier("settings.config.remove." + entry.scope.rawValue + "." + entry.key)
                } else {
                    Text(entry.value)
                        .font(Font.Vrai.codeSmall)
                        .foregroundStyle(overridden ? Color.Vrai.textTertiary : Color.Vrai.textSecondary)
                        .strikethrough(overridden)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(entry.scope == .system ? entry.value + ", " + (entry.origin ?? "") : entry.value)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(overridden && editable ? 0.7 : 1)
        .help(overridden ? String(localized: "Overridden by a closer scope", bundle: .module) : "")
        .contextMenu {
            Button(String(localized: "Copy value", bundle: .module)) { Clipboard.copy(entry.value) }
            if editable {
                Button(String(localized: "Remove", bundle: .module), role: .destructive, action: remove)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct AddConfigRow: View {
    let scopes: [ConfigEntry.Scope]
    let add: (ConfigEntry.Scope, String, String) -> Void
    @State private var scope: ConfigEntry.Scope = .local
    @State private var key = ""
    @State private var value = ""

    var validKey: Bool { ConfigCommands.isValidKey(key.trimmingCharacters(in: .whitespaces)) }
    var ready: Bool { validKey && !value.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        HStack(spacing: Vrai.Space.s12) {
            Picker(String(localized: "Scope", bundle: .module), selection: $scope) {
                ForEach(scopes, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: SettingsMetrics.scopeColumn, alignment: .leading)
            .accessibilityLabel(String(localized: "Scope", bundle: .module))
            .accessibilityIdentifier("settings.config.add.scope")
            TextField(String(localized: "Key", bundle: .module), text: $key, prompt: Text(verbatim: "merge.conflictStyle"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(Font.Vrai.codeSmall)
                .controlSize(.small)
                .onSubmit(submit)
                .accessibilityIdentifier("settings.config.add.key")
                .frame(maxWidth: .infinity)
            HStack(spacing: Vrai.Space.s6) {
                TextField(String(localized: "Value", bundle: .module), text: $value, prompt: Text(verbatim: "zdiff3"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(Font.Vrai.codeSmall)
                    .controlSize(.small)
                    .onSubmit(submit)
                    .accessibilityIdentifier("settings.config.add.value")
                VraiButton(title: String(localized: "Add", bundle: .module), size: .small, action: submit)
                    .disabled(!ready)
                    .accessibilityIdentifier("settings.config.add")
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear { if !scopes.contains(scope) { scope = scopes.first ?? .global } }
        .onChange(of: scopes) { _, next in if !next.contains(scope) { scope = next.first ?? .global } }
    }

    func submit() {
        guard ready else { return }
        add(scope, key.trimmingCharacters(in: .whitespaces), value.trimmingCharacters(in: .whitespaces))
        key = ""
        value = ""
    }
}
