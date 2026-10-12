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
        .tint(Color.Vrai.accent)
        .onAppear { AppSheets.register(app: app, openWindow: openWindow) }
    }
}

struct WelcomeContent: View {
    let context: AppSheetContext
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var model = WelcomeModel.shared
    @FocusState private var listFocused: Bool

    var recents: [RecentRepository] { app.recents.sorted { $0.lastOpened > $1.lastOpened } }

    var body: some View {
        @Bindable var preferences = app.preferences
        @Bindable var model = model
        let list = recents
        HStack(spacing: 0) {
            VStack(spacing: Vrai.Space.s8) {
                Spacer(minLength: 0)
                MarkImage(size: Metrics.welcomeMark)
                    .padding(.bottom, Vrai.Space.s8)
                Text(verbatim: "Vrai")
                    .font(Font.Vrai.display)
                    .foregroundStyle(Color.Vrai.text)
                Text(AppInfo.version)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.textSecondary)
                    .padding(.bottom, Vrai.Space.s16)
                VStack(spacing: Vrai.Space.s8) {
                    WelcomeAction(title: String(localized: "Open a repository\u{2026}", bundle: .module), icon: "folder", shortcut: "\u{2318}O", identifier: "welcome-open") { model.sheet = .open }
                    WelcomeAction(title: String(localized: "Clone a repository\u{2026}", bundle: .module), icon: "square.and.arrow.down", shortcut: "\u{21E7}\u{2318}O", identifier: "welcome-clone") { model.sheet = .clone(url: nil) }
                    WelcomeAction(title: String(localized: "New repository\u{2026}", bundle: .module), icon: "folder.badge.plus", shortcut: "\u{2325}\u{2318}N", identifier: "welcome-new") { model.sheet = .newRepository(folder: nil) }
                }
                .frame(maxWidth: LongTailMetrics.welcomeActions)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Vrai.Space.s32)
            .padding(.horizontal, Vrai.Space.s24)
            VStack(alignment: .leading, spacing: 0) {
                Text("Recent", bundle: .module)
                    .font(Font.Vrai.captionStrong)
                    .foregroundStyle(Color.Vrai.textSecondary)
                    .padding(.horizontal, Vrai.Space.s12)
                    .padding(.top, Vrai.Space.s16)
                    .padding(.bottom, Vrai.Space.s8)
                if list.isEmpty {
                    EmptyStateView(icon: "clock", title: String(localized: "No recent repositories", bundle: .module), message: String(localized: "Repositories you open, clone or create show up here.", bundle: .module), small: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: Vrai.Space.s2) {
                                ForEach(Array(list.enumerated()), id: \.element.id) { offset, recent in
                                    RepoRowView(recent: recent, status: model.statuses[recent.path], selected: offset == min(model.selected, list.count - 1), now: app.now)
                                        .id(recent.id)
                                        .onTapGesture {
                                            model.selected = offset
                                            open(recent)
                                        }
                                        .accessibilityAction {
                                            model.selected = offset
                                            open(recent)
                                        }
                                        .contextMenu { rowMenu(recent) }
                                }
                            }
                            .padding(.horizontal, Vrai.Space.s6)
                            .padding(.bottom, Vrai.Space.s8)
                        }
                        .focusable()
                        .focused($listFocused)
                        .focusEffectDisabled()
                        .onKeyPress(.downArrow) { move(1, in: list, proxy: proxy) }
                        .onKeyPress(.upArrow) { move(-1, in: list, proxy: proxy) }
                        .onKeyPress(.home) { move(-list.count, in: list, proxy: proxy) }
                        .onKeyPress(.end) { move(list.count, in: list, proxy: proxy) }
                        .onKeyPress(.return) {
                            guard list.indices.contains(model.selected) else { return .ignored }
                            open(list[model.selected])
                            return .handled
                        }
                        .onKeyPress(keys: [.delete], phases: .down) { press in
                            guard press.modifiers.contains(.command), list.indices.contains(model.selected) else { return .ignored }
                            remove(list[model.selected])
                            return .handled
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(Text("Recent repositories", bundle: .module))
                        .accessibilityIdentifier("welcome-recents")
                    }
                }
                Toggle(String(localized: "Show this window when no repository is open", bundle: .module), isOn: $preferences.welcomeOnLaunch)
                    .toggleStyle(SyncForm.CheckboxStyle())
                    .font(Font.Vrai.callout)
                    .padding(.vertical, Vrai.Space.s10)
                    .padding(.horizontal, Vrai.Space.s16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hairline(.top)
            }
            .frame(width: LongTailMetrics.welcomeRight)
            .frame(maxHeight: .infinity)
            .background(Color.Vrai.bgSubtle)
            .hairline(.leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.Vrai.bg)
        .ignoresSafeArea()
        .frame(width: LongTailMetrics.welcomeWidth, height: LongTailMetrics.welcomeContentHeight)
        .sheet(item: $model.sheet, onDismiss: {
            guard model.closeAfterSheet else { return }
            model.closeAfterSheet = false
            AppSheets.closeWelcome(dismissWindow)
        }) { kind in
            AppSheetView(kind: kind, context: context)
                .environment(app)
                .environment(app.preferences)
                .environment(\.longTailRoom, LongTailMetrics.welcomeSheetRoom)
                .tint(Color.Vrai.accent)
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
            model.statuses = await app.recentStatuses()
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

    func move(_ delta: Int, in list: [RecentRepository], proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !list.isEmpty else { return .ignored }
        model.selected = max(0, min(list.count - 1, model.selected + delta))
        proxy.scrollTo(list[model.selected].id)
        return .handled
    }

    func open(_ recent: RecentRepository) {
        if model.statuses[recent.path]?.missing == true || !FileManager.default.fileExists(atPath: recent.path) {
            model.missing = recent
            return
        }
        context.opened(RepositoryReference(path: recent.path))
    }

    func remove(_ recent: RecentRepository) {
        app.removeRecent(recent)
        model.selected = max(0, min(model.selected, app.recents.count - 1))
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
            HStack(spacing: ButtonSize.large.gap) {
                Symbol(icon, font: ButtonSize.large.iconFont)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: Vrai.Space.s8)
                Text(shortcut)
                    .opacity(0.72)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(VraiButtonStyle(variant: .secondary, size: .large, full: true))
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}

struct RepoRowView: View {
    let recent: RecentRepository
    let status: RecentStatus?
    let selected: Bool
    let now: Date
    @State private var hovering = false
    @Environment(AppModel.self) private var app

    var body: some View {
        let lane = RepoRowView.lane(for: recent.name)
        HStack(spacing: Vrai.Space.s12) {
            RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous)
                .fill(Color.Vrai.lane(lane))
                .frame(width: Vrai.Space.s32, height: Vrai.Space.s32)
                .overlay {
                    Text(String(recent.name.prefix(1)).uppercased())
                        .font(Font.Vrai.title3)
                        .foregroundStyle(Color.Vrai.onLane)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                Text(recent.name)
                    .font(Font.Vrai.headline)
                    .foregroundStyle(Color.Vrai.text)
                    .lineLimit(1)
                Text(app.displayPath(URL(filePath: recent.path)))
                    .font(Font.Vrai.caption)
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: LongTailMetrics.repoText, maxWidth: .infinity, alignment: .leading)
            meta
                .layoutPriority(1)
            Text(RelativeDate.ago(recent.lastOpened, now: now))
                .font(Font.Vrai.caption)
                .foregroundStyle(Color.Vrai.textTertiary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: LongTailMetrics.repoTime, alignment: .trailing)
        }
        .padding(.vertical, Vrai.Space.s8)
        .padding(.horizontal, Vrai.Space.s12)
        .frame(minHeight: Vrai.Size.controlLg + Vrai.Space.s16)
        .background(selected ? Color.Vrai.accentSoft : (hovering ? Color.Vrai.fill : Color.clear), in: RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("recent-" + recent.name)
    }

    @ViewBuilder var meta: some View {
        if let status {
            if status.missing {
                Text("Missing", bundle: .module)
                    .font(Font.Vrai.caption)
                    .foregroundStyle(Color.Vrai.warning)
                    .lineLimit(1)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Vrai.Space.s8) {
                        pill(status)
                        if status.changes > 0 {
                            Text(n(status.changes, "change"))
                                .font(Font.Vrai.caption)
                                .foregroundStyle(Color.Vrai.warning)
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
        }
        parts.append(String(localized: "opened \(RelativeDate.ago(recent.lastOpened, now: now))", bundle: .module))
        return parts.joined(separator: ", ")
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
                .foregroundStyle(Color.Vrai.text)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Font.Vrai.body)
                .foregroundStyle(Color.Vrai.textSecondary)
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
        .background(Color.Vrai.bg)
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
                VraiButton(title: String(localized: "Release notes", bundle: .module), full: true) {}
                    .disabled(true)
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
        .tint(Color.Vrai.accent)
    }

    var gitLine: String {
        guard let git = app.gitExecutable else { return String(localized: "Git was not found", bundle: .module) }
        return String(localized: "Uses git \(git.version.description) at \(git.path)", bundle: .module)
    }
}
