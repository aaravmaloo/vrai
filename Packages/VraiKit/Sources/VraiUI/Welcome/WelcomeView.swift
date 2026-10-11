import AppKit
import SwiftUI
import VraiCore
import VraiGit

enum AppInfo {
    static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return String(localized: "Version \(version) (\(build))", bundle: .module)
    }

    @MainActor static var icon: NSImage { NSApp.applicationIconImage }
}

public struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selected = 0

    public init() {}

    public var body: some View {
        @Bindable var preferences = app.preferences
        let recents = app.recents.sorted { $0.lastOpened > $1.lastOpened }
        HStack(spacing: 0) {
            VStack(spacing: Vrai.Space.s12) {
                Spacer(minLength: 0)
                Image(nsImage: AppInfo.icon)
                    .resizable()
                    .frame(width: Metrics.welcomeMark, height: Metrics.welcomeMark)
                    .accessibilityHidden(true)
                Text(verbatim: "Vrai")
                    .font(Font.Vrai.display)
                    .foregroundStyle(Color.Vrai.text)
                Text(AppInfo.version)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.textSecondary)
                VStack(spacing: Vrai.Space.s8) {
                    VraiButton(title: String(localized: "Open a repository\u{2026}", bundle: .module), icon: "folder", size: .large, shortcut: "\u{2318}O", full: true) {
                        OpenPanel.choose(app: app) { open($0) }
                    }
                    VraiButton(title: String(localized: "Clone a repository\u{2026}", bundle: .module), icon: "square.and.arrow.down", size: .large, shortcut: "\u{21E7}\u{2318}O", full: true) {}
                        .disabled(true)
                    VraiButton(title: String(localized: "New repository\u{2026}", bundle: .module), icon: "folder.badge.plus", size: .large, shortcut: "\u{2325}\u{2318}N", full: true) {}
                        .disabled(true)
                }
                .padding(.top, Vrai.Space.s16)
                .frame(width: Vrai.Size.field)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(Vrai.Space.s32)
            VStack(alignment: .leading, spacing: 0) {
                Text("Recent", bundle: .module)
                    .font(Font.Vrai.captionStrong)
                    .foregroundStyle(Color.Vrai.textSecondary)
                    .padding(.horizontal, Vrai.Space.s16)
                    .padding(.top, Vrai.Space.s40)
                    .padding(.bottom, Vrai.Space.s8)
                if recents.isEmpty {
                    EmptyStateView(icon: "clock", title: String(localized: "No recent repositories", bundle: .module), message: String(localized: "Repositories you open, clone or create show up here.", bundle: .module), small: true) {
                        EmptyView()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: Vrai.Space.s2) {
                            ForEach(Array(recents.enumerated()), id: \.element.id) { offset, recent in
                                Button {
                                    selected = offset
                                    open(RepositoryReference(path: recent.path))
                                } label: {
                                    HStack(spacing: Vrai.Space.s10) {
                                        Symbol("folder", font: Font.Vrai.title3)
                                            .foregroundStyle(Color.Vrai.accent)
                                        VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                                            Text(recent.name)
                                                .font(Font.Vrai.headline)
                                                .foregroundStyle(Color.Vrai.text)
                                            Text(PathText.abbreviated(recent.path))
                                                .font(Font.Vrai.caption)
                                                .foregroundStyle(Color.Vrai.textSecondary)
                                                .truncationMode(.middle)
                                        }
                                        .lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, Vrai.Space.s10)
                                    .padding(.vertical, Vrai.Space.s6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .hoverHighlight(radius: Vrai.Radius.md, selected: offset == selected)
                                .contextMenu {
                                    Button(String(localized: "Remove from recents", bundle: .module)) { app.removeRecent(recent) }
                                }
                            }
                        }
                        .padding(.horizontal, Vrai.Space.s8)
                    }
                }
                Toggle(String(localized: "Show this window when no repository is open", bundle: .module), isOn: $preferences.welcomeOnLaunch)
                    .toggleStyle(.checkbox)
                    .font(Font.Vrai.callout)
                    .padding(Vrai.Space.s16)
                    .hairline(.top)
            }
            .frame(width: Vrai.Size.sheet - Vrai.Space.s24)
            .frame(maxHeight: .infinity)
            .background(Color.Vrai.bgSubtle)
            .hairline(.leading)
        }
        .frame(width: Vrai.Size.sheetWide + Vrai.Space.s64 * 2, height: Vrai.Size.sheet - Vrai.Space.s40)
        .background(Color.Vrai.bg)
        .ignoresSafeArea()
        .background(WindowConfigurator(launch: app.launch))
        .tint(Color.Vrai.accent)
    }

    func open(_ reference: RepositoryReference) {
        openWindow(value: app.request(reference))
        dismissWindow(id: "welcome")
    }
}

public struct AboutView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismissWindow) private var dismissWindow

    public init() {}

    public var body: some View {
        VStack(spacing: Vrai.Space.s8) {
            Image(nsImage: AppInfo.icon)
                .resizable()
                .frame(width: Vrai.Space.s64, height: Vrai.Space.s64)
                .accessibilityHidden(true)
            Text(verbatim: "Vrai")
                .font(Font.Vrai.title2)
            Text(AppInfo.version)
                .font(Font.Vrai.callout)
                .foregroundStyle(Color.Vrai.textSecondary)
            Text("A beautiful Git client, made for Mac.", bundle: .module)
                .font(Font.Vrai.callout)
                .padding(.top, Vrai.Space.s4)
            Text(gitLine)
                .font(Font.Vrai.caption)
                .foregroundStyle(Color.Vrai.textTertiary)
                .multilineTextAlignment(.center)
            HStack(spacing: Vrai.Space.s8) {
                VraiButton(title: String(localized: "Release notes", bundle: .module), full: true) {}
                    .disabled(true)
                VraiButton(title: String(localized: "Close", bundle: .module), variant: .primary, full: true) {
                    dismissWindow(id: "about")
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, Vrai.Space.s12)
        }
        .padding(Vrai.Space.s20)
        .frame(width: Vrai.Size.alert)
        .background(Color.Vrai.surface)
        .background(WindowConfigurator(launch: app.launch))
        .tint(Color.Vrai.accent)
    }

    var gitLine: String {
        guard let git = app.gitExecutable else { return String(localized: "Git was not found", bundle: .module) }
        return String(localized: "Uses git \(git.version.description) at \(git.path)", bundle: .module)
    }
}

public struct SettingsView: View {
    @Environment(AppModel.self) private var app

    public init() {}

    public var body: some View {
        @Bindable var preferences = app.preferences
        Form {
            Picker(String(localized: "Appearance", bundle: .module), selection: $preferences.theme) {
                Text("Match the system", bundle: .module).tag(Preferences.Theme.system)
                Text("Light", bundle: .module).tag(Preferences.Theme.light)
                Text("Dark", bundle: .module).tag(Preferences.Theme.dark)
            }
            Picker(String(localized: "Density", bundle: .module), selection: $preferences.density) {
                Text("Compact", bundle: .module).tag(Preferences.Density.compact)
                Text("Regular", bundle: .module).tag(Preferences.Density.regular)
                Text("Comfortable", bundle: .module).tag(Preferences.Density.comfortable)
            }
            Toggle(String(localized: "Show the Welcome window when no repository is open", bundle: .module), isOn: $preferences.welcomeOnLaunch)
            Toggle(String(localized: "Expert mode", bundle: .module), isOn: $preferences.expert)
        }
        .formStyle(.grouped)
        .frame(width: Vrai.Size.sheet)
        .background(WindowConfigurator(launch: app.launch))
        .tint(Color.Vrai.accent)
    }
}
