import AppKit
import SwiftUI
import VraiCore
import VraiUI

@main
struct VraiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(String(localized: "Vrai"), id: "repository") {
            RepositoryWindowFrame()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let launch: LaunchOptions = {
        #if DEBUG
        LaunchOptions(arguments: ProcessInfo.processInfo.arguments)
        #else
        LaunchOptions()
        #endif
    }()

    func applicationWillFinishLaunching(_ notification: Notification) {
        switch Self.launch.appearance {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case nil: break
        }
    }
}
