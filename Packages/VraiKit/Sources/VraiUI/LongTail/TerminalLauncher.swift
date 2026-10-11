import AppKit
import Foundation

enum TerminalLauncher {
    static let bundleIdentifiers: [String: String] = [
        "Terminal": "com.apple.Terminal",
        "iTerm": "com.googlecode.iterm2",
        "Ghostty": "com.mitchellh.ghostty",
        "Warp": "dev.warp.Warp-Stable",
    ]

    static func applicationURL(for terminal: String) -> URL? {
        let workspace = NSWorkspace.shared
        if let identifier = bundleIdentifiers[terminal], let url = workspace.urlForApplication(withBundleIdentifier: identifier) {
            return url
        }
        return workspace.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
    }

    @MainActor
    @discardableResult
    static func open(_ folder: URL, terminal: String) -> Bool {
        guard let app = applicationURL(for: terminal) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: configuration)
        return true
    }

    static func name(for terminal: String) -> String {
        guard let identifier = bundleIdentifiers[terminal], NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) != nil else {
            return "Terminal"
        }
        return terminal
    }
}
