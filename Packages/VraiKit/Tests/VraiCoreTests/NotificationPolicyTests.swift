import Foundation
import Testing
@testable import VraiCore

@MainActor
struct NotificationPolicyTests {
    let start = Date(timeIntervalSince1970: 1_000)

    func preferences() -> (Preferences, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "vrai-notify-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (Preferences(defaults: LaunchOptions(sandbox: dir).makeDefaults()), dir)
    }

    @Test func deliversOnlyOnceTheWindowHasBeenAwayForAMoment() {
        let policy = NotificationPolicy(enabled: true, categories: Set(VraiNotification.Category.allCases))
        #expect(!policy.delivers(.sync, unfocusedSince: nil, now: start))
        #expect(!policy.delivers(.sync, unfocusedSince: start, now: start.addingTimeInterval(1)))
        #expect(policy.delivers(.sync, unfocusedSince: start, now: start.addingTimeInterval(NotificationPolicy.grace)))
        #expect(policy.delivers(.checks, unfocusedSince: start, now: start.addingTimeInterval(60)))
    }

    @Test func switchesAndPermissionCanStopDelivery() {
        let away = start.addingTimeInterval(10)
        #expect(!NotificationPolicy(enabled: false, categories: [.sync]).delivers(.sync, unfocusedSince: start, now: away))
        #expect(!NotificationPolicy(enabled: true, categories: [.fetch]).delivers(.sync, unfocusedSince: start, now: away))
        #expect(!NotificationPolicy(enabled: true, categories: [.sync], authorized: false).delivers(.sync, unfocusedSince: start, now: away))
    }

    @Test func onlyAlertsPlayASound() {
        let policy = NotificationPolicy(enabled: true, categories: [.sync], sound: true)
        let quiet = VraiNotification(category: .sync, repository: "/r", title: "r", body: "Pushed main")
        let alert = VraiNotification(category: .sync, repository: "/r", title: "r", body: "Push rejected", level: .alert)
        #expect(!policy.prepared(quiet).sound)
        #expect(policy.prepared(alert).sound)
        #expect(!NotificationPolicy(enabled: true, categories: [.sync], sound: false).prepared(alert).sound)
    }

    @Test func targetsSurviveTheTripThroughUserInfo() {
        let targets: [VraiNotification.Target] = [.history, .changes, .conflicts, .console, .ref("origin/main"), .commit("abc123")]
        for target in targets {
            #expect(VraiNotification.Target(link: target.link) == target)
        }
        #expect(VraiNotification.Target(link: "elsewhere") == nil)
    }

    @Test func fetchNotificationsReplaceEachOtherPerRepository() {
        let first = VraiNotification.fetched(repository: "/r", name: "r", newCommits: ["origin/main": 2, "origin/dev": 0])
        let second = VraiNotification.fetched(repository: "/r", name: "r", newCommits: ["origin/dev": 1])
        #expect(first.id == second.id)
        #expect(first.body == "2 new commits on origin/main")
        #expect(first.target == .ref("origin/main"))
        #expect(first.category == .fetch)
        #expect(VraiNotification(category: .sync, repository: "/r", title: "r", body: "").id != VraiNotification(category: .sync, repository: "/r", title: "r", body: "").id)
    }

    @Test func everyCategoryIsOnByDefaultAndRemembered() {
        let (preferences, dir) = preferences()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(preferences.notify)
        #expect(preferences.notifySound)
        #expect(preferences.notificationPolicy().categories == Set(VraiNotification.Category.allCases))
        preferences[keyPath: Preferences.notifyKey(.maintenance)] = false
        preferences.notify = false
        let reloaded = Preferences(defaults: preferences.defaults)
        #expect(!reloaded.notify)
        #expect(!reloaded.notificationPolicy().categories.contains(.maintenance))
        #expect(reloaded.notificationPolicy().categories.contains(.sync))
    }

    @Test func upstreamChangesListRewritesBeforeDeletions() {
        let note = VraiNotification.upstreamChanged(repository: "/r", name: "r", rewritten: ["origin/main"], gone: ["origin/old", "origin/done"])
        #expect(note.isUpstreamChange)
        #expect(note.body == "origin/main was force-pushed\norigin/done was deleted on the remote\norigin/old was deleted on the remote")
        #expect(note.target == .ref("origin/main"))
        #expect(VraiNotification.upstreamChanged(repository: "/r", name: "r", rewritten: [], gone: ["origin/old"]).target == .history)
        #expect(!VraiNotification.fetched(repository: "/r", name: "r", newCommits: ["origin/main": 1]).isUpstreamChange)
    }

    @Test func aFocusCanLimitVraiToFailuresAndRequests() {
        let policy = NotificationPolicy(enabled: true, categories: [.sync], alertsOnly: true)
        let away = start.addingTimeInterval(10)
        #expect(!policy.delivers(.sync, level: .quiet, unfocusedSince: start, now: away))
        #expect(policy.delivers(.sync, level: .alert, unfocusedSince: start, now: away))
        let (preferences, dir) = preferences()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(!preferences.dockBadge)
        #expect(preferences.notificationPolicy(alertsOnly: true).alertsOnly)
    }
}
