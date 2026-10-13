import AppKit
import SwiftUI
import UniformTypeIdentifiers
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

    static let releases = URL(string: "https://github.com/aaravmaloo/vrai/releases")!

    // Only builds made from a release tag carry an update feed, and only those
    // have a release page of their own.
    static var releaseNotes: URL {
        let info = Bundle.main.infoDictionary ?? [:]
        guard UpdateFeed(info: info, arguments: []) != nil, let version = info["CFBundleShortVersionString"] as? String else { return releases }
        return releases.appending(path: "tag/v" + version)
    }
}

struct MarkImage: View {
    let size: CGFloat
    var color = true

    var body: some View {
        Group {
            if color {
                Image("VraiMarkColor", bundle: .main)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image("VraiMark", bundle: .main)
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .foregroundStyle(Color.Vrai.text)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
        .accessibilityLabel(Text(verbatim: "Vrai"))
    }
}

public struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    public init() {}

    public var body: some View {
        Group {
            if let problem = app.gitProblem {
                OnboardingView(problem: problem)
            } else {
                WelcomeContent(context: AppSheets.welcomeContext(openWindow: openWindow, dismissWindow: dismissWindow, app: app))
            }
        }
        .environment(app.preferences)
        .background(WindowConfigurator(launch: app.launch).accessibilityHidden(true))
        .accessibilityHostLabel()
        .onAppear { AppSheets.register(app: app, openWindow: openWindow) }
        .perfLaunch("launch")
    }
}

struct WelcomeContent: View {
    let context: AppSheetContext
    @Environment(AppModel.self) private var app
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var model = WelcomeModel.shared
    @FocusState private var listFocused: Bool

    var recents: [RecentRepository] { Array(app.recents.sorted { $0.lastOpened > $1.lastOpened }.prefix(AppModel.shownRecents)) }

    var body: some View {
        @Bindable var preferences = app.preferences
        @Bindable var model = model
        let list = recents
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                MarkImage(size: Metrics.welcomeMark)
                    .padding(.bottom, Vrai.Space.s12)
                Text(verbatim: "Vrai")
                    .font(Font.Vrai.display)
                Text(AppInfo.version)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, Vrai.Space.s2)
                VStack(spacing: Vrai.Space.s8) {
                    WelcomeAction(title: String(localized: "Open a repository\u{2026}", bundle: .module), icon: "folder", shortcut: "\u{2318}O", identifier: "welcome-open") { model.sheet = .open }
                    WelcomeAction(title: String(localized: "Clone a repository\u{2026}", bundle: .module), icon: "square.and.arrow.down", shortcut: "\u{21E7}\u{2318}O", identifier: "welcome-clone") { model.sheet = .clone(url: nil) }
                    WelcomeAction(title: String(localized: "New repository\u{2026}", bundle: .module), icon: "folder.badge.plus", shortcut: "\u{2325}\u{2318}N", identifier: "welcome-new") { model.sheet = .newRepository(folder: nil) }
                }
                .frame(maxWidth: LongTailMetrics.welcomeActions)
                .padding(.top, Vrai.Space.s32)
                Spacer(minLength: 0)
                Toggle(String(localized: "Show this window when no repository is open", bundle: .module), isOn: $preferences.welcomeOnLaunch)
                    .toggleStyle(.checkbox)
            }
            .padding(.top, LongTailMetrics.welcomeTitlebar)
            .padding(.bottom, Vrai.Space.s20)
            .padding(.horizontal, Vrai.Space.s24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            List(selection: $model.selected) {
                Section(String(localized: "Recent", bundle: .module)) {
                    ForEach(list) { recent in
                        RepoRowView(recent: recent, status: model.statuses[recent.path], now: app.now)
                            .accessibilityAction { open(recent) }
                    }
                }
            }
            .listStyle(.sidebar)
            .contentMargins(.top, Vrai.Space.s12, for: .scrollContent)
            .overlay {
                if list.isEmpty {
                    ContentUnavailableView(String(localized: "No recent repositories", bundle: .module), systemImage: "clock")
                        .help(String(localized: "Repositories you open, clone or create show up here.", bundle: .module))
                }
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let recent = chosen(ids, in: list) { rowMenu(recent) }
            } primaryAction: { ids in
                if let recent = chosen(ids, in: list) { open(recent) }
            }
            .focused($listFocused)
            .onKeyPress(.return) {
                guard let recent = chosen(model.selected.map { [$0] } ?? [], in: list) else { return .ignored }
                open(recent)
                return .handled
            }
            .onKeyPress(keys: [.delete], phases: .down) { press in
                guard press.modifiers.contains(.command), let recent = chosen(model.selected.map { [$0] } ?? [], in: list) else { return .ignored }
                remove(recent)
                return .handled
            }
            .accessibilityLabel(Text("Recent repositories", bundle: .module))
            .accessibilityIdentifier("welcome-recents")
            .frame(width: LongTailMetrics.welcomeRight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .frame(width: LongTailMetrics.welcomeWidth, height: LongTailMetrics.welcomeContentHeight)
        .defaultFocus($listFocused, true)
        .onAppear { keepSelection() }
        .onChange(of: app.recents) { keepSelection() }
        .sheet(item: $model.sheet, onDismiss: {
            guard model.closeAfterSheet else { return }
            model.closeAfterSheet = false
            AppSheets.closeWelcome(dismissWindow)
        }) { kind in
            AppSheetView(kind: kind, context: context)
                .environment(app)
                .environment(app.preferences)
                .environment(\.longTailRoom, LongTailMetrics.welcomeSheetRoom)
                .accessibilityHostLabel(scope: .any)
        }
        .alert(
            model.missing.map { String(localized: "\($0.name) isn't where it used to be", bundle: .module) } ?? "",
            isPresented: Binding(get: { model.missing != nil }, set: { if !$0 { model.missing = nil } }),
            presenting: model.missing
        ) { recent in
            Button(String(localized: "Locate\u{2026}", bundle: .module)) { model.sheet = .open }
            Button(String(localized: "Remove from list", bundle: .module)) { remove(recent) }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
        } message: { recent in
            Text("Vrai can't find a repository at \(app.displayPath(URL(filePath: recent.path))). It may have been moved, renamed or deleted.", bundle: .module)
        }
        .task(id: app.recents.map(\.path)) {
            model.statuses = await app.recentStatuses(for: recents)
        }
    }

    @ViewBuilder func rowMenu(_ recent: RecentRepository) -> some View {
        Button(String(localized: "Open", bundle: .module)) { open(recent) }
        Button(String(localized: "Reveal in Finder", bundle: .module)) { LongTailReveal.show([URL(filePath: recent.path)]) }
            .disabled(model.statuses[recent.path]?.missing == true)
        Button(String(localized: "Open in Terminal", bundle: .module)) { TerminalLauncher.open(URL(filePath: recent.path, directoryHint: .isDirectory), terminal: app.preferences.terminal) }
            .disabled(model.statuses[recent.path]?.missing == true)
        Divider()
        Button(String(localized: "Remove from list", bundle: .module)) { remove(recent) }
    }

    func chosen(_ ids: Set<String>, in list: [RecentRepository]) -> RecentRepository? {
        guard ids.count == 1 else { return nil }
        return list.first { ids.contains($0.id) }
    }

    func keepSelection() {
        let list = recents
        guard !list.contains(where: { $0.id == model.selected }) else { return }
        model.selected = list.first?.id
    }

    func open(_ recent: RecentRepository) {
        if model.statuses[recent.path]?.missing == true || !FileManager.default.fileExists(atPath: recent.path) {
            model.missing = recent
            return
        }
        PerfLog.begin("open")
        context.opened(RepositoryReference(path: recent.path))
    }

    func remove(_ recent: RecentRepository) {
        let index = recents.firstIndex { $0.id == recent.id } ?? 0
        app.removeRecent(recent)
        guard model.selected == recent.id else { return }
        let remaining = recents
        model.selected = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }
}

struct WelcomeAction: View {
    let title: String
    let icon: String
    let shortcut: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
                    .lineLimit(1)
            } icon: {
                Image(systemName: icon)
                    .frame(width: Vrai.Size.icon)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .help(title + "  " + shortcut)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}

struct RepoRowView: View {
    let recent: RecentRepository
    let status: RecentStatus?
    let now: Date
    @Environment(AppModel.self) private var app

    var body: some View {
        let missing = status?.missing == true
        HStack(spacing: Vrai.Space.s10) {
            Image(nsImage: RepoRowView.icon(recent.path, missing: missing))
                .resizable()
                .interpolation(.high)
                .frame(width: Vrai.Space.s32, height: Vrai.Space.s32)
                .opacity(missing ? 0.5 : 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                Text(recent.name)
                    .font(.headline)
                    .foregroundStyle(missing ? HierarchicalShapeStyle.secondary : .primary)
                    .lineLimit(1)
                Text(app.displayPath(URL(filePath: recent.path)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: LongTailMetrics.repoText, maxWidth: .infinity, alignment: .leading)
            meta
                .layoutPriority(1)
            Text(RelativeDate.ago(recent.lastOpened, now: now))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: LongTailMetrics.repoTime, alignment: .trailing)
        }
        .padding(.vertical, Vrai.Space.s4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("recent-" + recent.name)
    }

    @ViewBuilder var meta: some View {
        if let status {
            if status.missing {
                Label(String(localized: "Missing", bundle: .module), systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Vrai.Space.s8) {
                        pill(status)
                        if status.changes > 0 {
                            Text(n(status.changes, "change"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        AheadBehind(ahead: status.ahead, behind: status.behind)
                    }
                    HStack(spacing: Vrai.Space.s8) {
                        pill(status)
                        AheadBehind(ahead: status.ahead, behind: status.behind)
                    }
                    pill(status)
                }
            }
        }
    }

    @ViewBuilder func pill(_ status: RecentStatus) -> some View {
        if let branch = status.branch {
            RefPill(model: RefPillModel(kind: .branch, name: branch, lane: app.branchLane(for: recent.path, branch: branch) ?? RepoRowView.branchLane(branch), current: true))
        } else if let tag = status.tag {
            RefPill(model: RefPillModel(kind: .tag, name: tag, lane: RepoRowView.branchLane(tag), current: true))
        } else {
            RefPill(model: RefPillModel(kind: .head, name: String(localized: "detached", bundle: .module)))
        }
    }

    var accessibilityText: String {
        var parts = [recent.name, app.displayPath(URL(filePath: recent.path))]
        if let status {
            if status.missing { parts.append(String(localized: "missing", bundle: .module)) }
            if let branch = status.branch { parts.append(String(localized: "on \(branch)", bundle: .module)) }
            if status.changes > 0 { parts.append(n(status.changes, "change")) }
            let sync = AheadBehind.help(ahead: status.ahead, behind: status.behind)
            if !sync.isEmpty { parts.append(sync) }
        }
        parts.append(String(localized: "opened \(RelativeDate.ago(recent.lastOpened, now: now))", bundle: .module))
        return parts.joined(separator: ", ")
    }

    static func icon(_ path: String, missing: Bool) -> NSImage {
        missing ? NSWorkspace.shared.icon(for: .folder) : NSWorkspace.shared.icon(forFile: path)
    }

    static func branchLane(_ branch: String) -> Int {
        BranchColors.mainLines.contains(branch) ? 0 : 1 + lane(for: branch) % (BranchColors.laneCount - 1)
    }

    static func lane(for name: String) -> Int {
        var hash: UInt32 = 2166136261
        for byte in name.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16777619
        }
        return Int(hash % UInt32(BranchColors.laneCount))
    }
}

struct OnboardingView: View {
    let problem: GitError
    @Environment(AppModel.self) private var app
    @State private var installing = false

    var body: some View {
        VStack(spacing: Vrai.Space.s12) {
            MarkImage(size: Metrics.welcomeMark)
                .padding(.bottom, Vrai.Space.s8)
            Text(title)
                .font(Font.Vrai.title1)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Font.Vrai.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: LongTailMetrics.onboardingWidth)
            if installing {
                SyncForm.Callout(tone: .info, title: String(localized: "Follow the installer that just opened", bundle: .module), message: String(localized: "When it finishes, choose Check again.", bundle: .module))
                    .frame(maxWidth: LongTailMetrics.onboardingWidth)
            }
            VStack(spacing: Vrai.Space.s8) {
                VraiButton(title: String(localized: "Install command line tools", bundle: .module), icon: "arrow.down.to.line", variant: .primary, size: .large, full: true) {
                    app.installCommandLineTools()
                    installing = true
                }
                .accessibilityIdentifier("onboarding-install")
                VraiButton(title: String(localized: "Check again", bundle: .module), icon: "arrow.clockwise", size: .large, full: true) {
                    app.rediscoverGit()
                }
                .accessibilityIdentifier("onboarding-check")
                VraiButton(title: String(localized: "Choose a git binary\u{2026}", bundle: .module), icon: "terminal", variant: .plain, full: true) {
                    chooseGit()
                }
            }
            .frame(maxWidth: LongTailMetrics.welcomeActions)
            .padding(.top, Vrai.Space.s8)
        }
        .padding(Vrai.Space.s32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .frame(width: LongTailMetrics.welcomeWidth, height: LongTailMetrics.welcomeContentHeight)
    }

    var title: String {
        switch problem.code {
        case .gitTooOld(let found, _): String(localized: "Git \(found.description) is too old for Vrai", bundle: .module)
        default: String(localized: "Vrai needs git", bundle: .module)
        }
    }

    var message: String {
        switch problem.code {
        case .gitTooOld(_, let needed):
            String(localized: "Vrai runs the git already on this Mac, and it needs git \(needed.description) or later. Install the latest command line tools from Apple, or update git with Homebrew, then check again.", bundle: .module)
        default:
            String(localized: "Vrai runs the git already on this Mac, and it isn't installed yet. Install Apple's command line tools; it takes a few minutes. Nothing else is needed.", bundle: .module)
        }
    }

    func chooseGit() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(filePath: "/opt/homebrew/bin", directoryHint: .isDirectory)
        panel.prompt = String(localized: "Use this git", bundle: .module)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        app.defaults.set(url.path(percentEncoded: false), forKey: "gitPath")
        app.rediscoverGit()
    }
}

public struct AboutView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openURL) private var openURL

    public init() {}

    public var body: some View {
        VStack(spacing: Vrai.Space.s8) {
            MarkImage(size: Vrai.Space.s48 + Vrai.Space.s8, color: false)
                .padding(.bottom, Vrai.Space.s4)
            Text(verbatim: "Vrai")
                .font(Font.Vrai.headline)
                .foregroundStyle(Color.Vrai.text)
            Text(AppInfo.version)
                .font(Font.Vrai.callout)
                .foregroundStyle(Color.Vrai.textSecondary)
            VStack(spacing: Vrai.Space.s4) {
                Text("A beautiful Git client, made for Mac.", bundle: .module)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.text)
                Text(gitLine)
                    .font(Font.Vrai.caption)
                    .foregroundStyle(Color.Vrai.textTertiary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, Vrai.Space.s4)
            HStack(spacing: Vrai.Space.s8) {
                VraiButton(title: String(localized: "Release notes", bundle: .module), full: true) {
                    openURL(AppInfo.releaseNotes)
                }
                VraiButton(title: String(localized: "Close", bundle: .module), variant: .primary, full: true) {
                    dismissWindow(id: "about")
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, Vrai.Space.s8)
        }
        .padding(Vrai.Space.s20)
        .frame(width: Vrai.Size.alert)
        .background(Color.Vrai.surface)
        .background(WindowConfigurator(launch: app.launch).accessibilityHidden(true))
    }

    var gitLine: String {
        guard let git = app.gitExecutable else { return String(localized: "Git was not found", bundle: .module) }
        return String(localized: "Uses git \(git.version.description) at \(git.path)", bundle: .module)
    }
}
