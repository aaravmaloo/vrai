import Observation
import SwiftUI
import VraiCore
import VraiGit

public enum SettingsPane: String, Sendable, Hashable, CaseIterable, Identifiable {
    case general
    case git
    case accounts
    case appearance
    case shortcuts
    case repository
    case expert

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "General", bundle: .module)
        case .git: String(localized: "Git", bundle: .module)
        case .accounts: String(localized: "Accounts", bundle: .module)
        case .appearance: String(localized: "Appearance", bundle: .module)
        case .shortcuts: String(localized: "Shortcuts", bundle: .module)
        case .repository: String(localized: "Repository", bundle: .module)
        case .expert: String(localized: "Expert", bundle: .module)
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .git: "arrow.triangle.branch"
        case .accounts: "person.crop.circle"
        case .appearance: "paintbrush"
        case .shortcuts: "keyboard"
        case .repository: "folder"
        case .expert: "terminal"
        }
    }
}

@MainActor
@Observable
public final class SettingsHub {
    public static let shared = SettingsHub()

    public var pane: SettingsPane = .general
    public private(set) var activeWindow: WindowModel?
    @ObservationIgnored public private(set) var context: SettingsContext?
    public var editTextFile: (@MainActor (WindowModel, String) -> Void)?
    @ObservationIgnored private var windows: [ObjectIdentifier: WindowModel] = [:]
    @ObservationIgnored var openSettingsAction: OpenSettingsAction?
    @ObservationIgnored var openedForLaunch = false

    public var openWindows: [WindowModel] { Array(windows.values) }

    public func open(_ pane: SettingsPane? = nil) {
        if let pane { self.pane = pane }
        openSettingsAction?()
    }

    func register(_ window: WindowModel) {
        windows[ObjectIdentifier(window)] = window
        if activeWindow == nil { activeWindow = window }
    }

    func activate(_ window: WindowModel) {
        windows[ObjectIdentifier(window)] = window
        if activeWindow !== window { activeWindow = window }
    }

    func remove(_ window: WindowModel) {
        windows.removeValue(forKey: ObjectIdentifier(window))
        if activeWindow === window { activeWindow = windows.values.first }
    }

    func context(for app: AppModel) -> SettingsContext {
        if let context, context.app === app { return context }
        let created = SettingsContext(app: app)
        context = created
        return created
    }
}

@MainActor
@Observable
public final class SettingsContext {
    let app: AppModel
    let window: WindowModel?
    let git: GitSettings?
    var gitVersion: String?
    var sshKeys: [SSHKey] = []
    var binaries: [GitBinary] = []

    init(app: AppModel) {
        self.app = app
        let process = try? app.configProcess()
        if let process {
            let store = RepositoryStore(git: process)
            window = WindowModel(reference: RepositoryReference(url: app.configDirectory), store: store, preferences: app.preferences, now: app.launch.now)
            git = GitSettings(git: process)
        } else {
            window = nil
            git = nil
        }
    }

    var preferences: Preferences { app.preferences }

    func reload() async {
        await git?.reload()
        let home = app.homeDirectory
        sshKeys = await Task.detached(priority: .utility) { SSHKeys.list(home: home) }.value
    }

    func loadBinaries() async {
        binaries = await AppModel.gitBinaries(including: app.preferences.gitPath ?? app.gitExecutable?.path)
    }

    func toast(_ message: String, detail: String? = nil, icon: String? = nil, tone: Tone = .neutral) {
        window?.toasts.show(Toast(tone: tone, message: message, detail: detail, icon: icon))
    }

    func fail(_ error: any Error) {
        let gitError = error as? GitError ?? GitError(.unknown(exit: -1, stderr: String(describing: error)))
        window?.alerts.present(gitError)
    }

    func run(_ body: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do {
                try await body()
            } catch let error as GitError where error.code == .cancelled {
                return
            } catch {
                fail(error)
            }
        }
    }
}
