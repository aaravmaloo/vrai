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
    }

    private func write(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
    }
}
