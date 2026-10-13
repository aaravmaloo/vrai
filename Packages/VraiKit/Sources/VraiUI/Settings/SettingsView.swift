import AppKit
import SwiftUI
import VraiCore
import VraiGit

public struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appearsActive) private var active

    public init() {}

    public var body: some View {
        @Bindable var hub = SettingsHub.shared
        let context = hub.context(for: app)
        TabView(selection: $hub.pane.animation(Animation.Vrai.outSlow)) {
            ForEach(SettingsPane.allCases) { pane in
                Tab(value: pane) {
                    SettingsPaneHost(pane: pane, context: context)
                } label: {
                    Label {
                        Text(pane.title)
                    } icon: {
                        Image(systemName: pane.icon)
                            .symbolEffect(.bounce, value: hub.pane == pane)
                    }
                }
                .accessibilityIdentifier("settings.tab." + pane.rawValue)
            }
        }
        .windowResizeAnchor(.top)
        .modifier(SettingsHosts(context: context))
        .environment(app.preferences)
        .environment(\.expert, app.preferences.expert)
        .environment(\.vraiNow, app.launch.now)
        .environment(\.captureMode, app.launch.capture)
        .background(WindowConfigurator(launch: app.launch).accessibilityHidden(true))
        .accessibilityHostLabel()
        .task { await context.reload() }
        .onChange(of: active) { _, value in
            if value { Task { await context.reload() } }
        }
        .onChange(of: app.preferences.theme, initial: true) { _, _ in applyTheme() }
    }

    func applyTheme() {
        guard app.launch.appearance == nil else { return }
        switch app.preferences.theme {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

struct SettingsHosts: ViewModifier {
    let context: SettingsContext

    func body(content: Content) -> some View {
        if let window = context.window {
            content
                .overlay(alignment: .bottom) { ToastHost() }
                .modifier(AlertHost(center: window.alerts))
                .modifier(SheetHost(center: window.sheets))
                .background { SyncAlertHosts(sync: window.sync) }
                .environment(window)
                .environment(window.store)
                .environment(window.toasts)
        } else {
            content
        }
    }
}

struct SettingsPaneHost: View {
    let pane: SettingsPane
    let context: SettingsContext
    @State private var width: CGFloat = Vrai.Size.sheetWide
    @State private var content: CGFloat?

    var body: some View {
        Group {
            switch pane {
            case .general: GeneralPane(context: context)
            case .notch: NotchPane(context: context)
            case .git: GitPane(context: context)
            case .accounts: AccountsPane(context: context)
            case .appearance: AppearancePane(context: context)
            case .shortcuts: ShortcutsPane()
            case .repository: RepositoryPane(context: context)
            case .expert: ExpertPane(context: context)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.Vrai.bg)
        .onPreferenceChange(SettingsContentHeightKey.self) { next in
            guard let next, next != content else { return }
            withAnimation(content == nil ? nil : Animation.Vrai.outSlow) { content = next }
        }
        .frame(width: SettingsMetrics.width, height: SettingsMetrics.height(for: content, pane: pane))
        .environment(\.settingsNarrow, width < SettingsMetrics.narrowBelow)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.pane." + pane.rawValue)
        .accessibilityHostLabel(pane.title, scope: .any)
    }
}

struct GitSettingsGate<Content: View>: View {
    let context: SettingsContext
    @ViewBuilder let content: (GitSettings) -> Content

    var body: some View {
        if let git = context.git {
            switch git.phase {
            case .loaded:
                content(git)
            case .failed(let error):
                let copy = ErrorCopy(error)
                SettingsNotice(icon: "exclamationmark.triangle", title: copy.title, message: copy.message)
            case .idle, .loading:
                VStack(spacing: Vrai.Space.s8) {
                    Spinner()
                    Text("Reading your git configuration", bundle: .module)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            GitUnavailable(context: context)
        }
    }
}

struct GitUnavailable: View {
    let context: SettingsContext

    var body: some View {
        let copy = ErrorCopy(context.app.gitError ?? GitError(.gitNotFound))
        SettingsNotice(icon: "exclamationmark.triangle", title: copy.title, message: copy.message)
    }
}
