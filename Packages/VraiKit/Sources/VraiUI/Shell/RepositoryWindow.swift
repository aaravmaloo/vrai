import AppKit
import SwiftUI
import VraiCore
import VraiGit

public struct RepositoryWindowRoot: View {
    @Binding var reference: RepositoryReference?
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var model: WindowModel?
    @State private var failure: GitError?
    @State private var missing: URL?

    public init(reference: Binding<RepositoryReference?>) {
        _reference = reference
    }

    public var body: some View {
        Group {
            if let model {
                RepositoryShell()
                    .environment(model)
                    .environment(model.store)
                    .environment(model.toasts)
                    .environment(model.preferences)
            } else if let missing {
                RepositoryGoneView(name: missing.lastPathComponent, path: missing.path(percentEncoded: false)) {
                    self.missing = nil
                    Task { await open(missing) }
                }
            } else if let failure {
                EmptyStateView(icon: "exclamationmark.triangle", title: ErrorCopy(failure).title, message: ErrorCopy(failure).message) {
                    VraiButton(title: String(localized: "Try again", bundle: .module), icon: "arrow.clockwise", variant: .primary) {
                        self.failure = nil
                        Task { await load() }
                    }
                }
                .background(Color.Vrai.bg)
            } else {
                Color.Vrai.bg
            }
        }
        .frame(minWidth: WidthClass.compactBelow - Vrai.Space.s24, minHeight: Vrai.Size.sheet - Vrai.Space.s64)
        .background(WindowConfigurator(launch: app.launch).accessibilityHidden(true))
        .accessibilityHostLabel()
        .task(id: reference) { await load() }
        .onAppear {
            AppSheets.register(app: app, openWindow: openWindow)
            SettingsHub.shared.editTextFile = { window, name in
                if let kind = TextFileKind(rawValue: name) { LongTailActions.openTextFile(window, kind) }
            }
        }
        .onDisappear {
            if let reference { app.release(reference) }
        }
    }

    func open(_ pending: URL) async {
        if RepositoryGone.check(pending.path(percentEncoded: false)) {
            missing = pending
            return
        }
        do {
            reference = try await app.open(path: pending.path(percentEncoded: false))
        } catch let error as GitError {
            failure = error
        } catch {
            failure = GitError(.notARepository)
        }
    }

    func load() async {
        if reference == nil {
            if let pending = app.takePendingOpen() {
                await open(pending)
            } else {
                openWindow(id: "welcome")
                dismissWindow()
            }
            return
        }
        guard let reference, model?.reference != reference else { return }
        if app.launch.isSandboxed, !app.wasRequested(reference) {
            if app.launch.open == nil { openWindow(id: "welcome") }
            dismissWindow()
            return
        }
        do {
            let store = try app.store(for: reference)
            let window = WindowModel(reference: reference, store: store, preferences: app.preferences, now: app.launch.now)
            model = window
            if app.launch.isSandboxed, let delay = app.launch.openDelay {
                try? await store.refresh()
                try? await Task.sleep(for: .milliseconds(delay))
            }
            await store.open()
            app.saveColors(store.branchColors, for: reference)
        } catch let error as GitError {
            failure = error
        } catch {
            failure = GitError(.gitNotFound)
        }
    }
}

struct RepositoryShell: View {
    @Environment(WindowModel.self) private var window
    @Environment(RepositoryStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(AppModel.self) private var app
    @Environment(\.vraiReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var window = window
        NavigationSplitView(columnVisibility: $window.columns) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: Vrai.Size.sidebar - Vrai.Space.s48, ideal: Vrai.Size.sidebar, max: Vrai.Size.sidebar + Vrai.Space.s64 * 2)
                .accessibilityHostLabel(String(localized: "Sidebar", bundle: .module), scope: .column)
        } detail: {
            VStack(spacing: 0) {
                ContentArea()
                    .safeAreaInset(edge: .top, spacing: 0) { BannerStack() }
                    .overlay(alignment: .bottom) { ToastHost() }
                ConsoleDrawerHost()
            }
            .accessibilityHostLabel(String(localized: "Content", bundle: .module), scope: .column)
        }
        .navigationTitle(window.repositoryName)
        .toolbar(removing: .title)
        .toolbar { RepositoryToolbar(window: window) }
        .overlay { PaletteHost() }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            let next = WidthClass(width: width)
            let previous = window.widthClass
            guard next != previous else { return }
            window.widthClass = next
            if next.isNarrow, !previous.isNarrow { window.columns = .detailOnly }
            if !next.isNarrow, previous.isNarrow { window.columns = .all }
            if next != .compact { window.pane = .list }
        }
        .onModifierKeysChanged(mask: .option, initial: true) { _, keys in
            window.optionDown = keys.contains(.option)
        }
        .environment(\.widthClass, window.widthClass)
        .environment(\.expert, preferences.expert)
        .environment(\.vraiNow, window.now)
        .environment(\.captureMode, app.launch.capture)
        .modifier(AlertHost(center: window.alerts))
        .modifier(SheetHost(center: window.sheets))
        .modifier(SyncWiring(window: window))
        .settingsWiring(window)
        .focusedSceneValue(\.windowModel, window)
        .tint(Color.Vrai.accent)
        .onChange(of: store.snapshotError) { _, error in
            guard let error, store.snapshot != nil, !RepositoryGone.check(window.reference.path) else { return }
            window.alerts.present(error) { Task { try? await store.refresh() } }
        }
        .onAppear { applyTheme() }
        .task { window.changes.listen(store) }
        .onChange(of: preferences.theme) { _, _ in applyTheme() }
    }

    func applyTheme() {
        guard app.launch.appearance == nil else { return }
        switch preferences.theme {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

struct ContentArea: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window

    var body: some View {
        Group {
            if store.snapshotError != nil, RepositoryGone.check(window.reference.path) {
                RepositoryGoneView(name: window.repositoryName, path: window.reference.path) {
                    Task { await store.open() }
                }
            } else if let error = store.snapshotError, store.snapshot == nil {
                EmptyStateView(icon: "exclamationmark.triangle", title: ErrorCopy(error).title, message: ErrorCopy(error).message) {
                    VraiButton(title: String(localized: "Try again", bundle: .module), icon: "arrow.clockwise", variant: .primary) {
                        Task { await store.open() }
                    }
                }
            } else if store.snapshot == nil || (store.history.phase != .loaded && store.history.commits.isEmpty && !isFailed) {
                LoadingView()
            } else {
                switch store.view {
                case .history:
                    HistoryView()
                case .changes:
                    ChangesView()
                case .stashes:
                    StashesView()
                case .reflog:
                    ReflogView()
                case .refs:
                    RefsView()
                case .worktrees:
                    WorktreesView()
                case .submodules:
                    SubmodulesView()
                case .blame:
                    BlameView()
                case .fileHistory:
                    FileHistoryView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.Vrai.bg)
    }

    var isFailed: Bool {
        if case .failed = store.history.phase { return true }
        return false
    }
}

struct LoadingView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(\.vraiReduceMotion) private var reduceMotion
    @State private var pulse = false

    static let widths: [CGFloat] = [64, 48, 72, 40, 56, 67, 45, 59, 38, 70, 52, 47, 61, 43]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Vrai.Space.s8) {
                Spinner()
                Text(note)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, Vrai.Space.s12)
            .padding(.horizontal, Vrai.Space.s16)
            .hairline(.bottom)
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ForEach(Array(Self.widths.enumerated()), id: \.offset) { _, share in
                        HStack(spacing: Vrai.Space.s12) {
                            Circle()
                                .fill(Color.Vrai.fillStrong)
                                .frame(width: Vrai.Space.s8, height: Vrai.Space.s8)
                            Capsule()
                                .fill(Color.Vrai.fillActive)
                                .frame(width: max(0, geometry.size.width - Vrai.Space.s32 - Vrai.Space.s8 - Vrai.Space.s12 * 2 - Metrics.loadingMeta) * share / 100, height: Vrai.Space.s8)
                                .opacity(pulse ? 1 : 0.45)
                            Spacer(minLength: 0)
                            Capsule()
                                .fill(Color.Vrai.fillActive)
                                .frame(width: Metrics.loadingMeta, height: Vrai.Space.s8)
                                .opacity(pulse ? 1 : 0.45)
                        }
                        .padding(.horizontal, Vrai.Space.s16)
                        .frame(height: Vrai.Size.row)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .background(Color.Vrai.bg)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Animation.Vrai.standardGraph.repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(note)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier("loading-view")
    }

    var note: String {
        guard let snapshot = store.snapshot else { return String(localized: "Reading \(window.repositoryName)", bundle: .module) }
        var parts: [String] = []
        if let total = store.history.totalCount { parts.append(n(total, "commit")) }
        parts.append(n(snapshot.branches.count, "branch"))
        parts.append(n(snapshot.tags.count, "tag"))
        return String(localized: "Reading \(window.repositoryName): \(parts.joined(separator: ", "))", bundle: .module)
    }
}

public enum WindowDefaults {
    public static let size = CGSize(width: Vrai.Size.sheetWide + Vrai.Size.sheet + Vrai.Space.s40, height: Vrai.Size.sheetWide + Vrai.Space.s64 + Vrai.Space.s16)
}

struct WindowConfigurator: NSViewRepresentable {
    let launch: LaunchOptions

    func makeNSView(context: Context) -> ConfiguringView {
        let view = ConfiguringView()
        view.launch = launch
        return view
    }

    func updateNSView(_ nsView: ConfiguringView, context: Context) {
        nsView.launch = launch
        nsView.configure()
    }

    final class ConfiguringView: NSView {
        var launch = LaunchOptions()

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configure()
        }

        func configure() {
            guard launch.isSandboxed, let window else { return }
            if launch.capture, window.level != .floating { window.level = .floating }
            if launch.capture, let screen = window.screen ?? NSScreen.main, !screen.frame.contains(window.frame) {
                window.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.minX, y: screen.visibleFrame.maxY))
            }
            WindowPersistence.disable(window)
        }
    }
}

public enum WindowPersistence {
    @MainActor private static var guarded = false

    @MainActor public static func guardFrameSaving() {
        guard !guarded else { return }
        guarded = true
        if let method = class_getInstanceMethod(NSWindow.self, #selector(NSWindow.saveFrame(usingName:))) {
            let ignore: @convention(block) (NSWindow, NSString) -> Void = { _, _ in }
            method_setImplementation(method, imp_implementationWithBlock(ignore))
        }
        if let method = class_getInstanceMethod(NSWindow.self, #selector(NSWindow.setFrameAutosaveName(_:))) {
            let ignore: @convention(block) (NSWindow, NSString) -> Bool = { _, _ in false }
            method_setImplementation(method, imp_implementationWithBlock(ignore))
        }
        if let method = class_getInstanceMethod(NSWindow.self, #selector(getter: NSWindow.isRestorable)) {
            let never: @convention(block) (NSWindow) -> Bool = { _ in false }
            method_setImplementation(method, imp_implementationWithBlock(never))
        }
        if let method = class_getInstanceMethod(NSSplitView.self, #selector(setter: NSSplitView.autosaveName)) {
            let ignore: @convention(block) (NSSplitView, NSString?) -> Void = { _, _ in }
            method_setImplementation(method, imp_implementationWithBlock(ignore))
        }
    }

    @MainActor static func disable(_ window: NSWindow) {
        guardFrameSaving()
        window.isRestorable = false
    }
}

enum OpenPanel {
    @MainActor static func choose(app: AppModel, opened: @escaping @MainActor (RepositoryReference) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Open", bundle: .module)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            if let reference = try? await app.open(path: url.path(percentEncoded: false)) { opened(reference) }
        }
    }
}

