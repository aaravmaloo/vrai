import Foundation
import Observation

@MainActor
@Observable
public final class Preferences {
    public enum Theme: String, Sendable, CaseIterable {
        case system
        case light
        case dark
    }

    public enum Density: String, Sendable, CaseIterable {
        case compact
        case regular
        case comfortable
    }

    public enum DiffMode: String, Sendable, CaseIterable {
        case unified
        case split
    }

    public enum OpenAt: String, Sendable, CaseIterable {
        case reopen
        case welcome
    }

    public enum Island: String, Sendable, CaseIterable {
        case off
        case activity
        case everything
    }

    public enum IslandLinger: String, Sendable, CaseIterable {
        case short
        case standard
        case long

        public var scale: Double {
            switch self {
            case .short: 0.6
            case .standard: 1
            case .long: 2
            }
        }
    }

    public enum IslandScreen: String, Sendable, CaseIterable {
        case window
        case builtIn
        case pointer
    }

    @ObservationIgnored public let defaults: UserDefaults

    public var theme: Theme { didSet { write("theme", theme.rawValue) } }
    public var expert: Bool { didSet { write("expert", expert) } }
    public var density: Density { didSet { write("density", density.rawValue) } }
    public var diffMode: DiffMode { didSet { write("diffMode", diffMode.rawValue) } }
    public var whitespace: Bool { didSet { write("whitespace", whitespace) } }
    public var wrap: Bool { didSet { write("wrap", wrap) } }
    public var inspector: Bool { didSet { write("inspector", inspector) } }
    public var consoleOnFailure: Bool { didSet { write("consoleOnFailure", consoleOnFailure) } }
    public var backgroundFetch: Bool { didSet { write("backgroundFetch", backgroundFetch) } }
    public var fetchInterval: Int { didSet { write("fetchInterval", fetchInterval) } }
    public var showRemotes: Bool { didSet { write("showRemotes", showRemotes) } }
    public var notifications: Bool { didSet { write("notifications", notifications) } }
    public var welcomeOnLaunch: Bool { didSet { write("welcomeOnLaunch", welcomeOnLaunch) } }
    public var confirmForcePush: Bool { didSet { write("confirmForcePush", confirmForcePush) } }
    public var commandPreviews: Bool { didSet { write("commandPreviews", commandPreviews) } }
    public var renameThreshold: Int { didSet { write("renameThreshold", renameThreshold) } }
    public var codeSize: Int { didSet { write("codeSize", codeSize) } }
    public var terminal: String { didSet { write("terminal", terminal) } }
    public var openAt: OpenAt { didSet { write("openAt", openAt.rawValue) } }
    public var gitPath: String? { didSet { writeOptional("gitPath", gitPath) } }
    public var accounts: [SignedInAccount] { didSet { writeAccounts() } }
    public var island: Island { didSet { write("island", island.rawValue) } }
    public var touchID: Bool { didSet { write("touchID", touchID) } }
    public var checks: Bool { didSet { write("checks", checks) } }
    public var checksNotify: Bool { didSet { write("checksNotify", checksNotify) } }
    public var islandSync: Bool { didSet { write("islandSync", islandSync) } }
    public var islandStates: Bool { didSet { write("islandStates", islandStates) } }
    public var islandFetch: Bool { didSet { write("islandFetch", islandFetch) } }
    public var islandChecks: Bool { didSet { write("islandChecks", islandChecks) } }
    public var islandAuth: Bool { didSet { write("islandAuth", islandAuth) } }
    public var islandAttention: Bool { didSet { write("islandAttention", islandAttention) } }
    public var islandHover: Bool { didSet { write("islandHover", islandHover) } }
    public var islandLinger: IslandLinger { didSet { write("islandLinger", islandLinger.rawValue) } }
    public var islandScreen: IslandScreen { didSet { write("islandScreen", islandScreen.rawValue) } }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        theme = Theme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system
        expert = defaults.object(forKey: "expert") as? Bool ?? false
        density = Density(rawValue: defaults.string(forKey: "density") ?? "") ?? .regular
        diffMode = DiffMode(rawValue: defaults.string(forKey: "diffMode") ?? "") ?? .unified
        whitespace = defaults.object(forKey: "whitespace") as? Bool ?? false
        wrap = defaults.object(forKey: "wrap") as? Bool ?? false
        inspector = defaults.object(forKey: "inspector") as? Bool ?? true
        consoleOnFailure = defaults.object(forKey: "consoleOnFailure") as? Bool ?? true
        backgroundFetch = defaults.object(forKey: "backgroundFetch") as? Bool ?? true
        fetchInterval = defaults.object(forKey: "fetchInterval") as? Int ?? 15
        showRemotes = defaults.object(forKey: "showRemotes") as? Bool ?? true
        notifications = defaults.object(forKey: "notifications") as? Bool ?? true
        welcomeOnLaunch = defaults.object(forKey: "welcomeOnLaunch") as? Bool ?? true
        confirmForcePush = defaults.object(forKey: "confirmForcePush") as? Bool ?? true
        commandPreviews = defaults.object(forKey: "commandPreviews") as? Bool ?? true
        renameThreshold = defaults.object(forKey: "renameThreshold") as? Int ?? 50
        codeSize = defaults.object(forKey: "codeSize") as? Int ?? 12
        terminal = defaults.string(forKey: "terminal") ?? "Terminal"
        openAt = OpenAt(rawValue: defaults.string(forKey: "openAt") ?? "") ?? .reopen
        gitPath = defaults.string(forKey: "gitPath").flatMap { $0.isEmpty ? nil : $0 }
        accounts = defaults.data(forKey: "accounts").flatMap { try? JSONDecoder().decode([SignedInAccount].self, from: $0) } ?? []
        island = Island(rawValue: defaults.string(forKey: "island") ?? "") ?? .everything
        touchID = defaults.object(forKey: "touchID") as? Bool ?? true
        checks = defaults.object(forKey: "checks") as? Bool ?? true
        checksNotify = defaults.object(forKey: "checksNotify") as? Bool ?? true
        islandSync = defaults.object(forKey: "islandSync") as? Bool ?? true
        islandStates = defaults.object(forKey: "islandStates") as? Bool ?? true
        islandFetch = defaults.object(forKey: "islandFetch") as? Bool ?? true
        islandChecks = defaults.object(forKey: "islandChecks") as? Bool ?? true
        islandAuth = defaults.object(forKey: "islandAuth") as? Bool ?? true
        islandAttention = defaults.object(forKey: "islandAttention") as? Bool ?? true
        islandHover = defaults.object(forKey: "islandHover") as? Bool ?? true
        islandLinger = IslandLinger(rawValue: defaults.string(forKey: "islandLinger") ?? "") ?? .standard
        islandScreen = IslandScreen(rawValue: defaults.string(forKey: "islandScreen") ?? "") ?? .window
    }

    private func write(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
    }

    private func writeOptional(_ key: String, _ value: String?) {
        if let value, !value.isEmpty { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    private func writeAccounts() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(accounts) else { return }
        defaults.set(data, forKey: "accounts")
    }
}
