import AppKit
import SwiftUI
import VraiCore
import VraiGit

struct GitPane: View {
    let context: SettingsContext
    @Environment(Preferences.self) private var preferences

    var body: some View {
        GitSettingsGate(context: context) { git in
            GitPaneForm(context: context, git: git)
        }
    }
}

struct GitPaneForm: View {
    let context: SettingsContext
    let git: GitSettings
    @Environment(Preferences.self) private var preferences

    var file: String { context.app.globalConfigDisplay }

    static func pullHelp(_ mode: PullMode) -> String {
        switch mode {
        case .merge: String(localized: "Pull makes a merge commit that joins both histories.", bundle: .module)
        case .rebase: String(localized: "Pull replays your commits on top of the upstream. Their hashes change.", bundle: .module)
        case .fastForwardOnly: String(localized: "Pull stops and lets you choose when the histories have diverged.", bundle: .module)
        }
    }

    static func algorithmHelp(_ algorithm: DiffAlgorithm) -> String {
        switch algorithm {
        case .myers: String(localized: "Fast, and git's default. Can pair unrelated lines when code moves.", bundle: .module)
        case .minimal: String(localized: "Spends extra time to find the smallest possible diff.", bundle: .module)
        case .patience: String(localized: "Matches unique lines first, so moved blocks stay together.", bundle: .module)
        case .histogram: String(localized: "Patience, extended for lines that repeat. Reads best for code.", bundle: .module)
        }
    }

    static func algorithmName(_ algorithm: DiffAlgorithm) -> String {
        switch algorithm {
        case .myers: String(localized: "Myers", bundle: .module)
        case .minimal: String(localized: "Minimal", bundle: .module)
        case .patience: String(localized: "Patience", bundle: .module)
        case .histogram: String(localized: "Histogram", bundle: .module)
        }
    }

    var body: some View {
        SettingsForm {
            SettingsSection(String(localized: "New repositories", bundle: .module)) {
                SettingsRow(String(localized: "First branch name", bundle: .module), description: String(localized: "Used by New repository and by git init.", bundle: .module)) {
                    CommitField(
                        value: git.defaultBranch ?? "master",
                        label: String(localized: "First branch name", bundle: .module),
                        mono: true,
                        id: "settings.defaultBranch",
                        validate: { $0.isEmpty ? String(localized: "Enter a branch name.", bundle: .module) : SyncForm.branchNameError($0, existing: []) }
                    ) { name in context.run { try await git.setDefaultBranch(name) } }
                }
            }
            SettingsSection(String(localized: "Pulling", bundle: .module)) {
                SettingsRow(String(localized: "When both sides have new commits", bundle: .module), description: Self.pullHelp(git.pullMode)) {
                    SettingsSelect(
                        label: String(localized: "Pull mode", bundle: .module),
                        options: [
                            SettingsOption(value: PullMode.merge, label: String(localized: "Merge", bundle: .module)),
                            SettingsOption(value: PullMode.rebase, label: String(localized: "Rebase", bundle: .module)),
                            SettingsOption(value: PullMode.fastForwardOnly, label: String(localized: "Fast-forward only", bundle: .module))
                        ],
                        selection: git.pullMode,
                        id: "settings.pullMode"
                    ) { mode in context.run { try await git.setPullMode(mode) } }
                }
                SettingsRow(String(localized: "Set uncommitted changes aside while pulling", bundle: .module), description: String(localized: "Stashes them first and brings them back after, so a pull never refuses to start.", bundle: .module)) {
                    SettingsSwitch(label: String(localized: "Set uncommitted changes aside while pulling", bundle: .module), isOn: git.autostash, id: "settings.autostash") { on in context.run { try await git.setAutostash(on) } }
                }
            }
            SettingsSection(String(localized: "Conflicts", bundle: .module)) {
                SettingsRow(String(localized: "Reuse recorded resolutions", bundle: .module), description: String(localized: "When a conflict you resolved before comes back, during a rebase for example, git resolves it the same way.", bundle: .module)) {
                    SettingsSwitch(label: String(localized: "Reuse recorded resolutions", bundle: .module), isOn: git.rerere, id: "settings.rerere") { on in context.run { try await git.setRerere(on) } }
                }
            }
            SettingsSection(String(localized: "Pushing", bundle: .module)) {
                SettingsRow(String(localized: "Confirm before force pushing", bundle: .module), description: String(localized: "Vrai asks before --force-with-lease or --force replaces commits on a remote.", bundle: .module)) {
                    SettingsSwitch(label: String(localized: "Confirm before force pushing", bundle: .module), isOn: preferences.confirmForcePush, id: "settings.confirmForcePush") { preferences.confirmForcePush = $0 }
                }
            }
            SettingsSection(String(localized: "Diffs", bundle: .module)) {
                SettingsRow(String(localized: "Diff algorithm", bundle: .module), description: Self.algorithmHelp(git.diffAlgorithm)) {
                    SettingsSelect(
                        label: String(localized: "Diff algorithm", bundle: .module),
                        options: DiffAlgorithm.allCases.map { SettingsOption(value: $0, label: Self.algorithmName($0), detail: $0 == .myers ? String(localized: "git's default", bundle: .module) : nil) },
                        selection: git.diffAlgorithm,
                        id: "settings.diffAlgorithm"
                    ) { algorithm in context.run { try await git.setDiffAlgorithm(algorithm) } }
                }
                SettingsRow(String(localized: "Detect renames", bundle: .module), description: String(localized: "Files at least \(preferences.renameThreshold)% alike count as renamed, like --find-renames=\(preferences.renameThreshold)%.", bundle: .module), stacked: true) {
                    SettingsSlider(label: String(localized: "Detect renames", bundle: .module), value: preferences.renameThreshold, range: 10...100, step: 5, format: { "\($0)%" }, id: "settings.renameThreshold") { preferences.renameThreshold = $0 }
                }
            }
            SettingsSection(String(localized: "Git", bundle: .module)) {
                GitBinaryRow(context: context)
            }
        }
    }
}

struct GitBinaryRow: View {
    let context: SettingsContext
    @Environment(Preferences.self) private var preferences

    static func source(_ source: GitBinary.Source) -> String? {
        switch source {
        case .commandLineTools: String(localized: "from the Xcode command line tools", bundle: .module)
        case .xcode: String(localized: "from Xcode", bundle: .module)
        case .homebrew: String(localized: "from Homebrew", bundle: .module)
        case .other: nil
        }
    }

    var current: GitExecutable? { context.app.gitExecutable }

    var description: String {
        guard let current else { return String(localized: "Vrai can't find git on this Mac.", bundle: .module) }
        let source = Self.source(GitBinaries.source(of: current.path))
        if let source { return String(localized: "\(current.version.description) at \(current.path), \(source).", bundle: .module) }
        return String(localized: "\(current.version.description) at \(current.path).", bundle: .module)
    }

    var body: some View {
        SettingsRow(String(localized: "Git binary", bundle: .module), description: description) {
            Menu {
                ForEach(context.binaries) { binary in
                    Toggle(isOn: Binding(get: { binary.path == current?.path }, set: { _ in choose(binary.path) })) {
                        Text(binary.path + "  " + binary.version.description)
                    }
                    .disabled(!binary.isSupported)
                }
                if !context.binaries.isEmpty { Divider() }
                Button(String(localized: "Other\u{2026}", bundle: .module)) { pick() }
                if preferences.gitPath != nil {
                    Button(String(localized: "Find git automatically", bundle: .module)) { choose(nil) }
                }
            } label: {
                Text("Choose\u{2026}", bundle: .module)
            }
            .menuStyle(.button)
            .controlSize(.small)
            .fixedSize()
            .accessibilityIdentifier("settings.gitBinary")
        }
        .task { await context.loadBinaries() }
    }

    func choose(_ path: String?) {
        do {
            let executable = try context.app.useGit(at: path)
            context.toast(String(localized: "Vrai now runs git \(executable.version.description)", bundle: .module), detail: String(localized: "\(executable.path). Repositories you open from now on use it.", bundle: .module), icon: "terminal")
            Task { await context.loadBinaries() }
        } catch {
            context.fail(error)
        }
    }

    func pick() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = String(localized: "Use this git", bundle: .module)
        panel.directoryURL = URL(filePath: "/usr/local/bin", directoryHint: .isDirectory)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        choose(url.path(percentEncoded: false))
    }
}
