import AppKit
import SwiftUI
import VraiCore
import VraiGit

struct RepositoryPane: View {
    let context: SettingsContext

    var body: some View {
        if let window = SettingsHub.shared.activeWindow, window.store.snapshot != nil {
            RepositoryPaneForm(context: context, window: window)
                .id(ObjectIdentifier(window))
        } else {
            SettingsNotice(icon: "folder", title: String(localized: "No repository is open", bundle: .module), message: String(localized: "Open a repository to change its identity, hooks and maintenance. The settings here apply to the repository you used last.", bundle: .module))
        }
    }
}

struct RepositoryPaneForm: View {
    let context: SettingsContext
    let window: WindowModel
    @Environment(Preferences.self) private var preferences
    @State private var config: RepositoryConfig?
    @State private var registered: Bool?
    @State private var lfs: LFSStatus?
    @State private var running: Set<String> = []

    var store: RepositoryStore { window.store }
    var snapshot: RepositorySnapshot? { store.snapshot }
    var global: String { context.app.globalConfigDisplay }

    var name: String { window.repositoryName }
    var path: String { GlobalConfigFile.display(SettingsCopy.trimmed(window.reference.path), environment: context.app.environment.base) }

    var body: some View {
        SettingsForm {
            identity
            hooks
            if SettingsHub.shared.editTextFile != nil { files }
            largeFiles
            maintenance
        }
        .task(id: snapshot?.headOID) { await load() }
    }

    func load() async {
        config = try? await store.repositoryConfig()
        registered = try? await store.maintenanceRegistered()
        lfs = await store.lfsStatus()
    }

    var hasLocal: Bool { config?.hasLocalIdentity ?? false }

    @ViewBuilder var identity: some View {
        let identity = config?.identity ?? Identity()
        let scope: ConfigEntry.Scope = hasLocal ? .local : .global
        let badge = hasLocal ? String(localized: "This repository", bundle: .module) : nil
        SettingsSection(
            String(localized: "Identity", bundle: .module),
            description: hasLocal ? String(localized: "Commits here use their own identity, not your global one.", bundle: .module) : String(localized: "Commits here use your global identity.", bundle: .module),
            footer: SettingsCopy.stored(in: hasLocal ? ".git/config" : global, as: [ConfigKeys.userName, ConfigKeys.userEmail]),
            top: AnyView(RepositoryHeader(name: name, path: path, terminal: preferences.terminal, reveal: reveal, openInTerminal: openInTerminal))
        ) {
            SettingsRow(String(localized: "Name", bundle: .module), badge: badge) {
                CommitField(value: identity.name ?? "", label: String(localized: "Name", bundle: .module), id: "settings.repository.name", validate: { $0.isEmpty ? String(localized: "Enter a name.", bundle: .module) : nil }) { value in
                    write(ConfigKeys.userName, value, scope: scope)
                }
            }
            SettingsRow(String(localized: "Email", bundle: .module), badge: badge) {
                CommitField(value: identity.email ?? "", label: String(localized: "Email", bundle: .module), id: "settings.repository.email", validate: { Identity.isValidEmail($0) ? nil : String(localized: "Enter an email address.", bundle: .module) }) { value in
                    write(ConfigKeys.userEmail, value, scope: scope)
                }
            }
            SettingsRow(String(localized: "Use a different identity in this repository", bundle: .module), description: String(localized: "Writes user.name and user.email to .git/config instead of \(global).", bundle: .module)) {
                SettingsSwitch(label: String(localized: "Use a different identity in this repository", bundle: .module), isOn: hasLocal, id: "settings.repository.localIdentity", disabled: config == nil) { on in
                    context.run {
                        try await store.setLocalIdentity(on ? identity : nil)
                        await load()
                    }
                }
            }
        }
    }

    func write(_ key: String, _ value: String, scope: ConfigEntry.Scope) {
        context.run {
            try await store.setConfig(key: key, value: value, scope: scope)
            await load()
            if scope == .global { await context.git?.reload() }
        }
    }

    var hooksFolder: String {
        guard let first = snapshot?.hooks.first else { return ".git/hooks" }
        let folder = SettingsCopy.trimmed(URL(filePath: first.path).deletingLastPathComponent().path(percentEncoded: false))
        if let root = snapshot?.root.map({ SettingsCopy.trimmed($0.path(percentEncoded: false)) }), folder.hasPrefix(root + "/") {
            return String(folder.dropFirst(root.count + 1))
        }
        return GlobalConfigFile.display(folder, environment: context.app.environment.base)
    }

    @ViewBuilder var hooks: some View {
        let list = snapshot?.hooks ?? []
        SettingsSection(String(localized: "Hooks", bundle: .module), footer: list.isEmpty ? nil : String(localized: "Scripts in \(hooksFolder), run exactly as git runs them. In Expert mode, Skip hooks in the commit composer bypasses them for one commit.", bundle: .module)) {
            if list.isEmpty {
                SettingsRow(String(localized: "No hooks yet", bundle: .module), description: String(localized: "Add executable scripts to .git/hooks, or share a folder of them with core.hooksPath.", bundle: .module))
            } else {
                ForEach(list) { hook in
                    SettingsRow(hook.name, description: HookCopy.description(hook), mono: true) {
                        HStack(spacing: Vrai.Space.s8) {
                            if running.contains(hook.name) {
                                Spinner()
                            } else {
                                VraiButton(title: String(localized: "Run now", bundle: .module), icon: "play.fill", size: .small) { run(hook) }
                                    .disabled(!hook.enabled)
                                    .help(hook.enabled ? String(localized: "Run \(hook.name) the way git would", bundle: .module) : String(localized: "Turn the hook on to run it", bundle: .module))
                                    .accessibilityIdentifier("settings.hook.run." + hook.name)
                            }
                            SettingsSwitch(label: hook.name, isOn: hook.enabled, id: "settings.hook." + hook.name) { on in
                                context.run { try await store.setHookEnabled(name: hook.name, enabled: on) }
                            }
                        }
                    }
                }
            }
        }
    }

    func run(_ hook: Hook) {
        running.insert(hook.name)
        context.run {
            defer { running.remove(hook.name) }
            let result = try await store.runHook(name: hook.name)
            let seconds = Double(result.duration.components.seconds) + Double(result.duration.components.attoseconds) / 1e18
            if result.passed {
                context.toast(String(localized: "\(hook.name) passed", bundle: .module), detail: String(localized: "Exit 0 after \(seconds.formatted(.number.precision(.fractionLength(1)))) s.", bundle: .module), icon: "checkmark.circle")
            } else {
                context.window?.alerts.present(AlertRequest(
                    title: String(localized: "\(hook.name) failed with exit \(result.exitCode)", bundle: .module),
                    message: result.output.isEmpty ? String(localized: "The hook printed nothing. Run it in Terminal to see more.", bundle: .module) : String(result.output.suffix(2000)),
                    actions: [AlertAction(title: String(localized: "Close", bundle: .module), role: .cancel)]
                ))
            }
        }
    }

    var files: some View {
        SettingsSection(String(localized: "Files", bundle: .module), footer: String(localized: "Edits show up in Changes, ready to commit.", bundle: .module)) {
            ForEach(RepositoryFiles.all, id: \.name) { file in
                SettingsRow(file.name, description: file.description, icon: file.icon, mono: true) {
                    VraiButton(title: String(localized: "Edit\u{2026}", bundle: .module), size: .small) {
                        SettingsHub.shared.editTextFile?(window, file.name)
                    }
                }
            }
        }
    }

    @ViewBuilder var largeFiles: some View {
        SettingsSection(String(localized: "Large files", bundle: .module), footer: String(localized: "Git LFS stores big binaries on the server and downloads them on checkout.", bundle: .module)) {
            switch lfs {
            case nil:
                SettingsRow(String(localized: "Checking Git LFS", bundle: .module), description: String(localized: "Running git lfs env.", bundle: .module), icon: "externaldrive")
            case .notInstalled?:
                SettingsRow(String(localized: "Git LFS isn't installed", bundle: .module), description: String(localized: "git lfs env can't run on this Mac. Install Git LFS, for example with brew install git-lfs, to keep large files out of the history.", bundle: .module), icon: "externaldrive")
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("settings.lfs.missing")
            case .installed(let info)?:
                SettingsRow(String(localized: "Git LFS \(info.version)", bundle: .module), description: LFSCopy.description(info), icon: "externaldrive")
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("settings.lfs.installed")
            }
        }
    }

    @ViewBuilder var maintenance: some View {
        SettingsSection(String(localized: "Maintenance", bundle: .module), footer: String(localized: "Registered in maintenance.repo in \(global). The schedule from git maintenance start runs it in the background.", bundle: .module)) {
            SettingsRow(String(localized: "Background maintenance", bundle: .module), description: String(localized: "Hourly prefetch and commit graph, daily loose objects, weekly pack cleanup.", bundle: .module)) {
                SettingsSwitch(label: String(localized: "Background maintenance", bundle: .module), isOn: registered ?? false, id: "settings.maintenance", disabled: registered == nil) { on in
                    registered = on
                    context.run {
                        defer { Task { await load() } }
                        let summary = try await store.setMaintenance(registered: on)
                        context.toast(summary.message, detail: summary.detail, icon: "wrench.and.screwdriver")
                    }
                }
            }
            SettingsRow(String(localized: "Run maintenance now", bundle: .module), description: String(localized: "Packs loose objects and refreshes the commit graph.", bundle: .module)) {
                if running.contains("maintenance") {
                    Spinner()
                } else {
                    VraiButton(title: String(localized: "Run now", bundle: .module), icon: "wrench.and.screwdriver", size: .small) {
                        running.insert("maintenance")
                        context.run {
                            defer { running.remove("maintenance") }
                            let summary = try await store.runMaintenance()
                            context.toast(summary.message, detail: summary.detail, icon: "wrench.and.screwdriver")
                        }
                    }
                    .accessibilityIdentifier("settings.maintenance.run")
                }
            }
        }
    }

    func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([window.reference.url])
    }

    func openInTerminal() {
        let names = [preferences.terminal, preferences.terminal + ".app"]
        let folders = ["/Applications", "/System/Applications/Utilities", "/Applications/Utilities"]
        let app = folders.flatMap { folder in names.map { URL(filePath: folder).appending(path: $0.hasSuffix(".app") ? $0 : $0 + ".app") } }.first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
        guard let app else {
            context.toast(String(localized: "Vrai can't find \(preferences.terminal)", bundle: .module), detail: String(localized: "Choose another Terminal app in General.", bundle: .module), icon: "terminal", tone: .warning)
            return
        }
        NSWorkspace.shared.open([window.reference.url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}

struct RepositoryHeader: View {
    let name: String
    let path: String
    let terminal: String
    let reveal: () -> Void
    let openInTerminal: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Vrai.Space.s8) {
                text
                Spacer(minLength: Vrai.Space.s8)
                buttons
            }
            VStack(alignment: .leading, spacing: Vrai.Space.s8) {
                text
                HStack(spacing: Vrai.Space.s8) { buttons }
            }
        }
        .padding(.vertical, Vrai.Space.s4)
    }

    var text: some View {
        VStack(alignment: .leading, spacing: Vrai.Space.s2) {
            Text(name)
                .font(Font.Vrai.title2)
                .foregroundStyle(Color.Vrai.text)
                .lineLimit(1)
            Text(path)
                .font(Font.Vrai.callout)
                .foregroundStyle(Color.Vrai.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder var buttons: some View {
        VraiButton(title: String(localized: "Reveal in Finder", bundle: .module), icon: "folder", size: .small, action: reveal)
        VraiButton(title: String(localized: "Open in \(terminal)", bundle: .module), icon: "terminal", size: .small, action: openInTerminal)
    }
}

enum RepositoryFiles {
    struct File {
        let name: String
        let description: String
        let icon: String
    }

    static var all: [File] {
        [
            File(name: ".gitignore", description: String(localized: "Files git should never track.", bundle: .module), icon: "eye.slash"),
            File(name: ".gitattributes", description: String(localized: "How git diffs, merges and stores particular paths.", bundle: .module), icon: "doc.text"),
            File(name: ".mailmap", description: String(localized: "Maps the names and emails in history to one person each.", bundle: .module), icon: "person.2")
        ]
    }
}

enum HookCopy {
    static func description(_ hook: Hook) -> String {
        if let summary = HookCommands.summary(of: hook.path) { return summary }
        let state = hook.enabled ? "" : " " + String(localized: "Off: the file isn't executable.", bundle: .module)
        return purpose(hook.name) + state
    }

    static func purpose(_ name: String) -> String {
        switch name {
        case "pre-commit": String(localized: "Runs before each commit. If it fails, the commit stops.", bundle: .module)
        case "commit-msg": String(localized: "Checks the commit message. If it fails, the commit stops.", bundle: .module)
        case "prepare-commit-msg": String(localized: "Fills in the commit message before you edit it.", bundle: .module)
        case "pre-push": String(localized: "Runs before each push. If it fails, nothing is pushed.", bundle: .module)
        case "post-commit": String(localized: "Runs after each commit.", bundle: .module)
        case "post-checkout": String(localized: "Runs after switching branches or checking out files.", bundle: .module)
        case "post-merge": String(localized: "Runs after a pull or merge finishes.", bundle: .module)
        case "pre-rebase": String(localized: "Runs before a rebase starts. If it fails, the rebase stops.", bundle: .module)
        case "pre-merge-commit": String(localized: "Runs before a merge commit. If it fails, the merge stops.", bundle: .module)
        default: String(localized: "A git hook in this repository.", bundle: .module)
        }
    }
}

enum LFSCopy {
    static func description(_ info: LFSInfo) -> String {
        guard info.configured else { return String(localized: "Installed, but not set up for your account. Run git lfs install once in Terminal.", bundle: .module) }
        guard !info.patterns.isEmpty else { return String(localized: "This repository doesn't track any files with Git LFS.", bundle: .module) }
        let patterns = SettingsCopy.list(info.patterns)
        if let files = info.files { return String(localized: "Tracking \(patterns): \(n(files, "file")).", bundle: .module) }
        return String(localized: "Tracking \(patterns).", bundle: .module)
    }
}
