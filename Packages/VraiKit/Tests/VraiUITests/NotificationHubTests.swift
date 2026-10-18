import Foundation
import Testing
import VraiGit
@testable import VraiCore
@testable import VraiUI

actor Posted {
    var notes: [VraiNotification] = []
    var removed: [String] = []

    func append(_ note: VraiNotification) { notes.append(note) }
    func remove(_ ids: [String]) { removed += ids }
}

@MainActor
@Suite(.serialized)
struct NotificationHubTests {
    let start = Date(timeIntervalSince1970: 2_000)

    func setUp() throws -> (NotificationHub, WindowModel, Posted, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "vrai-hub-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let app = AppModel(launch: LaunchOptions(sandbox: dir))
        let reference = app.request(RepositoryReference(url: dir))
        let window = WindowModel(reference: reference, store: try app.store(for: reference), preferences: app.preferences, now: nil)
        let posted = Posted()
        let hub = NotificationHub()
        hub.notifierOverride = ClosureNotifier({ await posted.append($0) }, removal: { await posted.remove($0) })
        hub.now = { start.addingTimeInterval(5) }
        hub.focusAlertsOnly = { false }
        return (hub, window, posted, dir)
    }

    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func toastsLeaveTheWindowOnlyWhenTaggedAndTheWindowIsAway() async throws {
        let (hub, window, posted, dir) = try setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pushed = Toast(message: "Pushed 3 commits to origin/main", category: .sync, target: .ref("origin/main"))

        window.sync.unfocusedSince = nil
        #expect(!hub.route(pushed, window: window))
        window.sync.unfocusedSince = start.addingTimeInterval(4)
        #expect(!hub.route(pushed, window: window))
        window.sync.unfocusedSince = start
        #expect(!hub.route(Toast(message: "Copied abc123"), window: window))
        #expect(!hub.route(Toast(message: "Pushing main", busy: true, category: .sync), window: window))
        #expect(hub.route(pushed, window: window))
        window.preferences.notifySync = false
        #expect(!hub.route(pushed, window: window))

        await settle()
        let notes = await posted.notes
        #expect(notes.count == 1)
        #expect(notes.first?.title == window.repositoryName)
        #expect(notes.first?.body == "Pushed 3 commits to origin/main")
        #expect(notes.first?.target == .ref("origin/main"))
        #expect(notes.first?.level == .quiet)
        #expect(notes.first?.sound == false)
        window.sync.unfocusedSince = nil
    }

    @Test func toastActionsBecomeButtonsThatRunWhenClicked() async throws {
        let (hub, window, posted, dir) = try setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        window.sync.unfocusedSince = start
        var undone = 0
        let pulled = Toast(tone: .danger, message: "Pull failed", action: "Retry", category: .sync) { undone += 1 }
        #expect(hub.route(pulled, window: window))
        await settle()
        let note = try #require(await posted.notes.first)
        #expect(note.buttons.map(\.title) == ["Retry"])
        #expect(note.level == .alert)
        #expect(note.sound)
        hub.respond(id: note.id, action: "action", repository: note.repository, target: nil)
        #expect(undone == 1)
        hub.respond(id: note.id, action: "action", repository: nil, target: nil)
        #expect(undone == 1)
        window.sync.unfocusedSince = nil
    }

    @Test func newCommitsAddUpUntilTheWindowIsBack() async throws {
        let (hub, window, posted, dir) = try setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(hub.unseenCommits(["origin/main": 2], window: window) == ["origin/main": 2])
        #expect(hub.unseenCommits(["origin/main": 3, "origin/dev": 1, "origin/old": 0], window: window) == ["origin/main": 5, "origin/dev": 1])
        hub.focused(window)
        await settle()
        #expect(await posted.removed == ["fetch:" + window.reference.path])
        #expect(hub.unseenCommits(["origin/main": 1], window: window) == ["origin/main": 1])
    }

    @Test func handlersAreForgottenAfterAHundredNotifications() throws {
        let (hub, window, _, dir) = try setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        var ran: [Int] = []
        for index in 0..<(NotificationHub.remembered + 1) {
            hub.post(VraiNotification(id: "n\(index)", category: .sync, repository: "", title: "", body: ""), preferences: window.preferences, actions: [NotificationAction("go", "Go") { ran.append(index) }])
        }
        hub.respond(id: "n0", action: "go", repository: nil, target: nil)
        hub.respond(id: "n1", action: "go", repository: nil, target: nil)
        #expect(ran == [1])
    }

    @Test func showButtonsStayOutOfTheNotification() async throws {
        let (hub, window, posted, dir) = try setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        window.sync.unfocusedSince = start
        #expect(hub.route(Toast(message: "Fetched 2 commits", action: "Show", category: .sync, target: .ref("origin/main"), notifyButton: false) {}, window: window))
        await settle()
        #expect(await posted.notes.first?.buttons.isEmpty == true)
        window.sync.unfocusedSince = nil
    }

    @Test func alertsWaitingWhileAwayOfferTheirFirstChoice() async throws {
        let (hub, window, posted, dir) = try setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        var steps: [String] = []
        let actions = [
            AlertAction(title: "Cancel", role: .cancel) { steps.append("cancel") },
            AlertAction(title: "Pull and push") { steps.append("pull") },
            AlertAction(title: "Force push with lease") { steps.append("force") }
        ]
        hub.alertShown(title: "Push rejected", message: "origin/main has 2 commits you don't have.", actions: actions, slot: "sync", window: window) { steps.append("close") }
        await settle()
        #expect(await posted.notes.isEmpty)

        window.sync.unfocusedSince = start
        hub.alertShown(title: "Push rejected", message: "origin/main has 2 commits you don't have.", actions: actions, slot: "sync", window: window) { steps.append("close") }
        await settle()
        let note = try #require(await posted.notes.first)
        #expect(note.category == .needsYou)
        #expect(note.level == .alert)
        #expect(note.body == "Push rejected\norigin/main has 2 commits you don't have.")
        #expect(note.buttons.map(\.title) == ["Pull and push"])
        #expect(note.buttons.first?.opensApp == false)
        hub.respond(id: note.id, action: "choice", repository: note.repository, target: nil)
        #expect(steps == ["close", "pull"])

        hub.alertShown(title: "Sign in to github.com", message: nil, actions: [AlertAction(title: "Sign in again\u{2026}") {}], slot: "sync", window: window) {}
        hub.alertShown(title: "git is asking to continue", message: nil, actions: actions, buttons: false, slot: "window", window: window) {}
        await settle()
        let notes = await posted.notes
        #expect(notes[1].buttons.first?.opensApp == true)
        #expect(notes[2].buttons.isEmpty)
        #expect(notes[1].id != notes[2].id)
        hub.alertClosed(slot: "sync", window: window)
        hub.alertClosed(slot: "sync", window: window)
        await settle()
        #expect(await posted.removed == [NotificationHub.alertID(window, slot: "sync")])
        window.sync.unfocusedSince = nil
    }

    @Test func passwordPromptsAreAnnouncedAndWithdrawn() async throws {
        let (hub, window, posted, dir) = try setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let request = AskpassRequest(prompt: "Password for 'https://avery@github.com': ")
        window.sync.unfocusedSince = start
        hub.promptShown(request, window: window)
        hub.promptAnswered(window: window)
        await settle()
        #expect(await posted.notes.map(\.body) == ["git is waiting for your password for github.com."])
        #expect(await posted.removed == [NotificationHub.promptID(window)])
        #expect(NotificationHub.promptCopy(AskpassRequest(prompt: "Enter passphrase for key '/Users/a/.ssh/id_ed25519': ")) == "git is waiting for the passphrase of your SSH key.")
        window.sync.unfocusedSince = nil
    }

    @Test func appWideWorkUsesTheAppsFocus() throws {
        let (hub, window, _, dir) = try setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        hub.appInactiveSince = nil
        #expect(!hub.deliversWhileAway(.sync, preferences: window.preferences))
        hub.appInactiveSince = start.addingTimeInterval(4)
        #expect(!hub.deliversWhileAway(.sync, preferences: window.preferences))
        hub.appInactiveSince = start
        #expect(hub.deliversWhileAway(.sync, preferences: window.preferences))
    }

    @Test func historyEditsCarryTheirCategoryAndUndo() throws {
        let (_, window, _, dir) = try setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let merged = RewriteActions.undoToast(window, message: "Merged feature into main", icon: "arrow.triangle.merge", category: .history)
        #expect(merged.category == .history)
        #expect(merged.target == .history)
        #expect(merged.action == "Undo")
        #expect(RewriteActions.undoToast(window, message: "Reset main", icon: "arrow.counterclockwise").category == nil)
    }

    @Test func stopNotificationsLeaveOnceTheOperationEnds() async throws {
        let (hub, window, posted, dir) = try setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = NotificationHub.stoppedID(window)
        hub.stateChanged(nil, window: window)
        hub.track(id)
        hub.stateChanged(nil, window: window)
        hub.stateChanged(nil, window: window)
        await settle()
        #expect(await posted.removed == [id])
    }

    @Test func duringAFocusOnlyFailuresLeaveTheWindow() async throws {
        let (hub, window, posted, dir) = try setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        hub.focusAlertsOnly = { true }
        window.sync.unfocusedSince = start
        #expect(!hub.route(Toast(message: "Pushed main", category: .sync), window: window))
        #expect(hub.route(Toast(tone: .danger, message: "Couldn't reach github.com", category: .sync), window: window))
        await settle()
        #expect(await posted.notes.map(\.body) == ["Couldn't reach github.com"])
        window.sync.unfocusedSince = nil
    }

    @Test func someNotificationsClearWhenTheWindowIsBack() async throws {
        let (hub, window, posted, dir) = try setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        hub.focusAlertsOnly = { false }
        window.sync.unfocusedSince = start
        let console = VraiNotification(id: "console:" + window.reference.path, category: .maintenance, repository: window.reference.path, title: "r", body: "Finished git lfs pull")
        let pushed = VraiNotification(id: "pushed", category: .sync, repository: window.reference.path, title: "r", body: "Pushed main")
        #expect(hub.deliver(console, window: window, clearsOnReturn: true))
        #expect(hub.deliver(pushed, window: window))
        hub.focused(window)
        hub.focused(window)
        await settle()
        #expect(await posted.removed == [console.id])
        window.sync.unfocusedSince = nil
    }

    @Test func theDockBadgeAddsCommitsToPullAndFailingCI() {
        #expect(DockBadge.label(behind: [], failing: 0) == nil)
        #expect(DockBadge.label(behind: [0, 0], failing: 0) == nil)
        #expect(DockBadge.label(behind: [3, 2], failing: 1) == "6")
    }
}
