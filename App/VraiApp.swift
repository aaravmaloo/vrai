import AppKit
import SwiftUI
import VraiCore
import VraiUI

@main
struct VraiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var app = AppModel(launch: AppDelegate.launch)

    var body: some Scene {
        WindowGroup(String(localized: "Vrai"), id: "repository", for: RepositoryReference.self) { $reference in
            RepositoryWindowRoot(reference: $reference)
                .environment(app)
        }
        .defaultSize(AppDelegate.windowSize)
        .defaultLaunchBehavior(app.launch.open == nil ? .suppressed : .presented)
        .restorationBehavior(app.launch.isSandboxed || app.preferences.openAt == .welcome ? .disabled : .automatic)
        .windowResizability(.contentMinSize)
        .commands { RepositoryCommands(app: app, updates: appDelegate.updater.check) }

        Window(String(localized: "Welcome to Vrai"), id: "welcome") {
            WelcomeView()
                .environment(app)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(app.launch.open == nil && app.preferences.welcomeOnLaunch ? .presented : .suppressed)
        .restorationBehavior(.disabled)

        Window(String(localized: "About Vrai"), id: "about") {
            AboutView()
                .environment(app)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .environment(app)
        }
        .windowResizability(.contentSize)
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

    let updater = SoftwareUpdater()

    static var windowSize: CGSize {
        launch.windowSize ?? WindowDefaults.size
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        if Self.launch.isSandboxed { WindowPersistence.guardFrameSaving() }
        switch Self.launch.appearance {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case nil: break
        }
    }
}
