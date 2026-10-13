import Foundation
import Testing
@testable import VraiCore
@testable import VraiUI

@MainActor
struct IslandLogicTests {
    func center(_ mode: Preferences.Island = .activity) -> IslandCenter {
        let center = IslandCenter(headless: true)
        center.mode = mode
        return center
    }

    @Test func offModeShowsNothing() {
        let island = center(.off)
        island.show(IslandActivity(phase: .success, title: "Pushed main"))
        #expect(island.activities.isEmpty)
        #expect(!island.isActive)
    }

    @Test func resultsStayCompactThenLeave() {
        let island = center()
        let id = island.show(IslandActivity(phase: .success, title: "Added origin", linger: 2))
        #expect(island.current?.id == id)
        #expect(!island.expanded)
        #expect(island.stage == .compact)
        island.tick(Date().addingTimeInterval(1))
        #expect(island.contains(id))
        island.tick(Date().addingTimeInterval(2.5))
        #expect(!island.contains(id))
    }

    @Test func onlyActivitiesThatNeedYouExpand() {
        let island = center()
        island.show(IslandActivity(phase: .running, title: "Pushing main"))
        #expect(!island.expanded)
        island.show(IslandActivity(phase: .failure, title: "Couldn't reach github.com"))
        #expect(!island.expanded)
        let rejected = island.show(IslandActivity(phase: .failure, title: "Push rejected", actions: [IslandAction(title: "Pull and push") {}], attention: true))
        #expect(island.expanded)
        #expect(island.stage == .expanded)
        island.tick(Date().addingTimeInterval(30))
        #expect(!island.contains(rejected))
        island.show(IslandActivity(phase: .authenticating, title: "Force push main"))
        #expect(island.expanded)
    }

    @Test func compactWingsAreIconSized() {
        let notch = IslandMetrics(notch: true, notchWidth: 185, height: 32)
        #expect(notch.compactWidth == 185 + IslandMetrics.wing * 2 + IslandMetrics.ear * 2)
        #expect(IslandMetrics.wing <= Vrai.Space.s40)
    }

    @Test func hoveringHoldsAnActivityOpen() {
        let island = center()
        let id = island.show(IslandActivity(phase: .success, title: "Added origin", linger: 1))
        #expect(!island.expanded)
        island.hovering = true
        #expect(island.expanded)
        island.tick(Date().addingTimeInterval(10))
        #expect(island.contains(id))
        #expect(island.expanded)
        island.hovering = false
        island.tick(Date().addingTimeInterval(0.2))
        #expect(island.contains(id))
        island.tick(Date().addingTimeInterval(3))
        #expect(!island.contains(id))
    }

    @Test func runningActivitiesStayUntilFinished() {
        let island = center()
        let id = island.show(IslandActivity(phase: .running, title: "Pushing main to origin"))
        island.tick(Date().addingTimeInterval(120))
        #expect(island.contains(id))
        #expect(!island.expanded)
        island.update(id) { $0.badge = "40%" }
        #expect(island.current?.badge == "40%")
        island.finish(id) { activity in
            activity.phase = .success
            activity.title = "Pushed main"
            activity.linger = 1
        }
        #expect(island.current?.phase == .success)
        #expect(!island.expanded)
        island.tick(Date().addingTimeInterval(3))
        #expect(island.activities.isEmpty)
    }

    @Test func aNewResultReplacesFinishedOnesButKeepsLiveOnes() {
        let island = center()
        let live = island.show(IslandActivity(phase: .running, title: "Checks running on main"))
        let first = island.show(IslandActivity(phase: .success, title: "Fetched origin"))
        let second = island.show(IslandActivity(phase: .success, title: "Added mira"))
        #expect(island.contains(live))
        #expect(!island.contains(first))
        #expect(island.current?.id == second)
    }

    @Test func dismissedActivitiesLeaveAfterTheirGrace() {
        let island = center()
        let id = island.show(IslandActivity(phase: .running, title: "Fetching origin"))
        island.dismiss(id, after: 0.3)
        #expect(island.contains(id))
        island.tick(Date().addingTimeInterval(0.5))
        #expect(!island.contains(id))
    }

    @Test func aResultArrivingDuringTheGraceTakesItsPlace() {
        let island = center()
        let busy = island.show(IslandActivity(phase: .running, title: "Pushing main"))
        island.dismiss(busy, after: 0.3)
        let done = island.show(IslandActivity(phase: .success, title: "Pushed main"))
        #expect(!island.contains(busy))
        #expect(island.current?.id == done)
    }

    @Test func turningTheIslandOffClearsIt() {
        let island = center()
        island.show(IslandActivity(phase: .running, title: "Pulling"))
        island.mode = .off
        #expect(island.activities.isEmpty)
    }

    @Test func toastsBecomeActivities() {
        let busy = IslandRouter.activity(for: Toast(message: "Pushing main to origin", action: "Cancel", timeout: 3600, busy: true), source: "vrai")
        #expect(busy.phase == .running)
        #expect(busy.linger == nil)
        #expect(busy.actions.first?.activates == false)
        #expect(busy.source == "vrai")
        let done = IslandRouter.activity(for: Toast(message: "Added origin", detail: "github.com/team/vrai", icon: "network"), source: nil)
        #expect(done.phase == .success)
        #expect(done.icon == "network")
        let failed = IslandRouter.activity(for: Toast(tone: .danger, message: "Couldn't reach github.com", action: "Retry", onAction: {}), source: nil)
        #expect(failed.phase == .failure)
        #expect(failed.actions.first?.prominent == true)
        #expect(failed.attention)
        #expect(!done.attention)
        let warning = IslandRouter.activity(for: Toast(tone: .warning, message: "Stopped on 2 conflicts"), source: nil)
        #expect(warning.phase == .warning)
        let brief = IslandRouter.activity(for: Toast(message: "Copied", timeout: Toast.brief), source: nil)
        #expect(brief.linger == Toast.brief)
    }

    @Test func activityDurations() {
        #expect(IslandActivity(phase: .failure, title: "x").duration > IslandActivity(phase: .success, title: "x").duration)
        #expect(IslandActivity(phase: .running, title: "x").duration == .infinity)
        #expect(IslandActivity(phase: .success, title: "x", linger: 7).duration == 7)
    }

    @Test func compactAndExpandedSizes() {
        let notch = IslandMetrics(notch: true, notchWidth: 185, height: 32)
        #expect(notch.compactWidth > 185)
        #expect(notch.expandedWidth > notch.compactWidth)
        #expect(IslandMetrics.panelWidth > notch.expandedWidth)
        let flat = IslandMetrics(notch: false, notchWidth: 0, height: 24)
        #expect(flat.compactWidth == IslandMetrics.detachedWidth)
    }

    @Test func checksCopy() {
        func run(_ state: CheckState) -> CheckRun { CheckRun(id: UUID().uuidString, name: "job", state: state) }
        #expect(ChecksCopy.summary(CommitChecks(sha: "a", runs: [run(.passed), run(.passed)])) == "2 checks passed")
        #expect(ChecksCopy.summary(CommitChecks(sha: "a", runs: [run(.failed), run(.passed), run(.passed)])) == "1 of 3 checks failed")
        #expect(ChecksCopy.summary(CommitChecks(sha: "a", runs: [run(.failed)])) == "1 check failed")
        #expect(ChecksCopy.summary(CommitChecks(sha: "a", runs: [run(.passed), run(.running)])) == "1 of 2 checks done")
        #expect(ChecksCopy.summary(CommitChecks(sha: "a", runs: [run(.pending)])) == "1 check running")
        #expect(ChecksCopy.duration(42) == "42s")
        #expect(ChecksCopy.duration(120) == "2m")
        #expect(ChecksCopy.duration(192) == "3m 12s")
        #expect(ChecksCopy.duration(3720) == "1h 2m")
        let named = [CheckRun(id: "1", name: "test", workflow: "Tests", state: .failed), CheckRun(id: "2", name: "build", workflow: "Tests", state: .failed), CheckRun(id: "3", name: "deploy", state: .failed), CheckRun(id: "4", name: "lint", state: .failed)]
        #expect(ChecksCopy.names(named) == "Tests, deploy and 1 more")
    }

    @Test func sandboxAuthenticatorFollowsTheStub() {
        Authenticator.configure(launch: LaunchOptions(arguments: ["-VraiSandbox", "/tmp/vrai-sandbox", "-VraiAuth", "approve"]))
        #expect(Authenticator.biometricsAvailable)
        Authenticator.configure(launch: LaunchOptions(arguments: ["-VraiSandbox", "/tmp/vrai-sandbox"]))
        #expect(!Authenticator.biometricsAvailable)
    }
}
