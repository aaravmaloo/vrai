import AppKit
import Network
import Observation
import SwiftUI
import UserNotifications
import VraiCore
import VraiGit

enum SyncKind: String, Sendable {
    case fetch
    case pull
    case push
}

struct SyncRun {
    var cancel: @MainActor () -> Void
    var progress: GitProgress?
    var toast: UUID?
}

struct SyncAlert: Identifiable {
    let id = UUID()
    var icon: String
    var title: String
    var message: String?
    var toggle: String?
    var toggleDefault = false
    var actions: [AlertAction]
}

struct SignInAnswer: Sendable {
    var username: String
    var token: String
}

@MainActor
final class PromptReply {
    private var continuation: CheckedContinuation<SignInAnswer?, Never>?

    init(_ continuation: CheckedContinuation<SignInAnswer?, Never>) {
        self.continuation = continuation
    }

    func finish(_ answer: SignInAnswer?) {
        continuation?.resume(returning: answer)
        continuation = nil
    }
}

@MainActor
@Observable
final class SyncModel {
    let window: WindowModel
    var running: [SyncKind: SyncRun] = [:]
    var surfaced = false
    var alert: SyncAlert?
    var toggleOn = false
    var isKey = true
    var windowHeight: CGFloat = 0
    var userNetwork = 0
    @ObservationIgnored var fetcher: BackgroundFetcher?
    @ObservationIgnored var retryWhenOnline: (@MainActor () -> Void)?
    @ObservationIgnored var monitor: NWPathMonitor?
    @ObservationIgnored var lastPathSatisfied: Bool?
    @ObservationIgnored var alertClosed = Date.distantPast

    init(window: WindowModel) {
        self.window = window
    }

    var store: RepositoryStore { window.store }
    var snapshot: RepositorySnapshot? { store.snapshot }
    var toasts: ToastCenter { window.toasts }
    var preferences: Preferences { window.preferences }
    var headName: String { window.headName }
    var currentBranch: Branch? { snapshot?.currentBranch }
    var defaultRemote: String? {
        let names = snapshot?.remotes.map(\.name) ?? []
        return names.contains("origin") ? "origin" : names.first
    }

    func isBusy(_ kind: SyncKind) -> Bool {
        running[kind] != nil || store.busy.contains(kind.rawValue)
    }

    func matches(context: String?) -> Bool {
        guard let context else { return false }
        return Self.normalized(context) == Self.normalized(window.reference.path)
    }

    static func normalized(_ path: String) -> String {
        var value = URL(filePath: path).standardizedFileURL.path(percentEncoded: false)
        while value.count > 1, value.hasSuffix("/") { value.removeLast() }
        return value
    }

    func present(_ alert: SyncAlert) {
        let delay = window.sheets.current != nil
        window.sheets.dismiss()
        if delay {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                self?.show(alert)
            }
        } else {
            show(alert)
        }
    }

    private func show(_ alert: SyncAlert) {
        toggleOn = alert.toggleDefault
        self.alert = alert
    }

    func closeAlert(then action: (@MainActor () -> Void)?) {
        alert = nil
        alertClosed = Date()
        action?()
    }

    func showSheet<Content: View>(@ViewBuilder _ content: @escaping () -> Content) {
        let request = SheetRequest(content)
        let wait = Date().timeIntervalSince(alertClosed) < 0.5 || window.alerts.current != nil
        if wait {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                self?.window.sheets.present(request)
            }
        } else {
            window.sheets.present(request)
        }
    }

    func toast(_ summary: ActionSummary, icon: String, action: String? = nil, onAction: (@MainActor () -> Void)? = nil) {
        toasts.show(Toast(message: summary.message, detail: summary.detail, icon: icon, action: action, onAction: onAction))
    }

    func run<Value: Sendable>(_ kind: SyncKind, _ handle: OperationHandle<Value>, busy: String, retry: (@MainActor () -> Void)?, done: @escaping @MainActor (Value) -> Void) {
        running[kind] = SyncRun(cancel: { handle.cancel() })
        userNetwork += 1
        Task { [weak self] in
            for await progress in handle.progress {
                self?.running[kind]?.progress = progress
            }
        }
        let notice = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled, let self, self.running[kind] != nil else { return }
            self.running[kind]?.toast = self.toasts.show(Toast(message: busy, action: String(localized: "Cancel", bundle: .module), timeout: 3600, busy: true) { [weak self] in
                self?.running[kind]?.cancel()
            })
        }
        Task { [weak self] in
            let outcome: Result<Value, any Error>
            do {
                outcome = .success(try await handle.value)
            } catch {
                outcome = .failure(error)
            }
            notice.cancel()
            guard let self else { return }
            if let id = self.running[kind]?.toast { self.toasts.dismiss(id) }
            self.running[kind] = nil
            self.userNetwork -= 1
            switch outcome {
            case .success(let value):
                self.surfaced = false
                done(value)
            case .failure(let error):
                self.failed(error, kind: kind, retry: retry)
            }
        }
    }

    func perform(network: Bool = false, _ body: @escaping @MainActor () async throws -> Void, retry: (@MainActor () -> Void)? = nil, kind: SyncKind? = nil) {
        if network { userNetwork += 1 }
        Task { [weak self] in
            do {
                try await body()
                if network { self?.surfaced = false }
            } catch {
                self?.failed(error, kind: kind, retry: retry)
            }
            if network { self?.userNetwork -= 1 }
        }
    }
}

@MainActor
final class SyncHub: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SyncHub()
    private var models: [ObjectIdentifier: SyncModel] = [:]
    private var secrets: [String: (answer: SignInAnswer, expires: Date)] = [:]
    private(set) weak var app: AppModel?
    private var installed = false

    func model(for window: WindowModel) -> SyncModel {
        let key = ObjectIdentifier(window)
        if let existing = models[key] { return existing }
        let created = SyncModel(window: window)
        models[key] = created
        return created
    }

    func remove(_ window: WindowModel) {
        let key = ObjectIdentifier(window)
        models[key]?.stop()
        models.removeValue(forKey: key)
    }

    func install(app: AppModel) {
        guard !installed else { return }
        installed = true
        self.app = app
        app.askpass?.setHandler { request in
            await SyncHub.answer(request)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SyncHub.shared.app?.askpass?.close() }
        }
        if app.launch.sandbox == nil { UNUserNotificationCenter.current().delegate = self }
    }

    var sandbox: URL? { app?.launch.sandbox }

    var credentialHelper: String? {
        sandbox.map { CredentialStore.storeHelper(file: $0.appending(path: "git-credentials")) }
    }

    var notifier: any Notifier {
        if let sandbox {
            let log = sandbox.appending(path: "notifications.log")
            return ClosureNotifier { notification in
                let line = notification.title + "\t" + notification.body.replacingOccurrences(of: "\n", with: " | ") + "\n"
                if let handle = try? FileHandle(forWritingTo: log) {
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: Data(line.utf8))
                    try? handle.close()
                } else {
                    try? Data(line.utf8).write(to: log)
                }
            }
        }
        return SystemNotifier()
    }

    static func answer(_ request: AskpassRequest) async -> String? {
        await shared.respond(request)
    }

    func respond(_ request: AskpassRequest) async -> String? {
        guard let model = models.values.first(where: { $0.matches(context: request.context) }), model.userNetwork > 0 else { return nil }
        let host = request.host ?? ""
        switch request.kind {
        case .password:
            if let pending = secrets[host], pending.expires > Date(), request.username == nil || request.username == pending.answer.username {
                secrets[host] = nil
                return pending.answer.token
            }
            return await model.askCredentials(request)?.token
        case .username:
            guard let answer = await model.askCredentials(request) else { return nil }
            secrets[host] = (answer, Date().addingTimeInterval(60))
            return answer.username
        case .passphrase, .other:
            return await model.askCredentials(request)?.token
        case .confirm:
            return await model.askConfirm(request) ? "yes" : nil
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

struct SystemNotifier: Notifier {
    func post(_ notification: FetchNotification) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        } else if status == .denied {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.threadIdentifier = notification.repository
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

extension WindowModel {
    var sync: SyncModel { SyncHub.shared.model(for: self) }
}

extension SyncModel {
    func start(app: AppModel) {
        restartFetcher()
    }

    func stop() {
        fetcher?.stop()
        fetcher = nil
        monitor?.cancel()
        monitor = nil
    }

    func restartFetcher() {
        fetcher?.stop()
        fetcher = nil
        guard preferences.backgroundFetch else { return }
        let fetcher = BackgroundFetcher(
            store: store,
            notifier: SyncHub.shared.notifier,
            interval: BackgroundFetcher.interval(minutes: preferences.fetchInterval),
            notifyAboutNewCommits: preferences.notifications,
            isWindowKey: { [weak self] in self?.isKey ?? false }
        )
        fetcher.start()
        self.fetcher = fetcher
    }

    func askCredentials(_ request: AskpassRequest) async -> SignInAnswer? {
        await withCheckedContinuation { continuation in
            let reply = PromptReply(continuation)
            showSheet { SignInSheet(prompt: request, reply: reply) }
        }
    }

    func askConfirm(_ request: AskpassRequest) async -> Bool {
        await withCheckedContinuation { continuation in
            let reply = PromptReply(continuation)
            present(SyncAlert(
                icon: "key",
                title: String(localized: "git is asking to continue", bundle: .module),
                message: request.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                actions: [
                    AlertAction(title: String(localized: "Continue", bundle: .module)) { reply.finish(SignInAnswer(username: "", token: "yes")) },
                    AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel) { reply.finish(nil) }
                ]
            ))
        } != nil
    }

    func watchConnection() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.pathChanged(satisfied) }
        }
        monitor.start(queue: .main)
        self.monitor = monitor
    }

    func pathChanged(_ satisfied: Bool) {
        defer { lastPathSatisfied = satisfied }
        guard satisfied, lastPathSatisfied == false, let retry = retryWhenOnline else { return }
        retryWhenOnline = nil
        retry()
    }
}

struct SyncWiring: ViewModifier {
    let window: WindowModel
    @Environment(AppModel.self) private var app
    @Environment(\.appearsActive) private var active

    func body(content: Content) -> some View {
        let sync = window.sync
        content
            .background { SyncAlertHosts(sync: sync) }
            .onAppear {
                SyncHub.shared.install(app: app)
                sync.start(app: app)
            }
            .onDisappear { SyncHub.shared.remove(window) }
            .onChange(of: active, initial: true) { _, value in sync.isKey = value }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sync.windowHeight = $0 }
            .onChange(of: window.preferences.backgroundFetch) { _, _ in sync.restartFetcher() }
            .onChange(of: window.preferences.fetchInterval) { _, _ in sync.restartFetcher() }
            .onChange(of: window.preferences.notifications) { _, value in sync.fetcher?.notifyAboutNewCommits = value }
            .onChange(of: window.store.snapshot?.network) { _, value in
                if value == .ok { sync.surfaced = false }
            }
    }
}

struct SyncAlertHosts: View {
    @Bindable var sync: SyncModel

    var body: some View {
        ZStack {
            Color.clear
                .alert(sync.alert?.title ?? "", isPresented: binding(toggle: false), presenting: sync.alert) { request in
                    actions(request)
                } message: { request in
                    if let message = request.message { Text(message) }
                }
                .dialogIcon(sync.alert.map { Image(systemName: $0.icon) })
            Color.clear
                .alert(sync.alert?.title ?? "", isPresented: binding(toggle: true), presenting: sync.alert) { request in
                    actions(request)
                } message: { request in
                    if let message = request.message { Text(message) }
                }
                .dialogIcon(sync.alert.map { Image(systemName: $0.icon) })
                .dialogSuppressionToggle(Text(sync.alert?.toggle ?? ""), isSuppressed: $sync.toggleOn)
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    func binding(toggle: Bool) -> Binding<Bool> {
        Binding(
            get: { sync.alert != nil && (sync.alert?.toggle != nil) == toggle },
            set: { if !$0, (sync.alert?.toggle != nil) == toggle { sync.alert = nil } }
        )
    }

    @ViewBuilder func actions(_ request: SyncAlert) -> some View {
        ForEach(request.actions) { action in
            Button(role: action.role.buttonRole) {
                sync.closeAlert(then: action.action)
            } label: {
                Text(action.title)
            }
            .disabled(!action.enabled)
        }
    }
}
