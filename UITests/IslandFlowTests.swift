import XCTest

final class IslandFlowTests: XCTestCase {
    typealias Copy = SyncFlowTests.Copy

    static let checksFile = Sandbox.root + "/checks.json"
    static let checks = """
    {
      "9eb0cce": {"runs": [
        {"name": "test", "workflow": "Tests", "state": "failed", "seconds": 192, "summary": "2 tests failed"},
        {"name": "build", "workflow": "Tests", "state": "passed", "seconds": 95},
        {"name": "notarize", "workflow": "Release", "state": "skipped"}
      ]},
      "bfb5b91": {"runs": [{"name": "test", "workflow": "Tests", "state": "running", "seconds": 40}]},
      "81b9fd3": {"runs": [{"name": "test", "workflow": "Tests", "state": "passed", "seconds": 120}, {"name": "vercel", "state": "passed"}]}
    }
    """

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: Self.checksFile)
    }

    override func record(_ issue: XCTIssue) {
        var issue = issue
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "failure-" + name
        shot.lifetime = .keepAlways
        issue.add(shot)
        super.record(issue)
    }

    @MainActor
    private func launch(_ path: String, _ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-VraiSandbox", Sandbox.root,
            "-VraiOpen", path,
            "-VraiAppearance", "dark",
            "-VraiNow", Sandbox.now,
            "-VraiWindowSize", "1280x800",
            "-ApplePersistenceIgnoreState", "YES"
        ] + extra
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1)
        return app
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String, screen: Bool = false) {
        let shot = XCTAttachment(screenshot: screen ? XCUIScreen.main.screenshot() : app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func island(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["island"].firstMatch
    }

    @MainActor
    private func eventually(_ timeout: TimeInterval = 10, _ condition: () throws -> Bool) rethrows -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if try condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return try condition()
    }

    @MainActor
    func testChecksShowOnTheCommitAndInThePopover() throws {
        try Data(Self.checks.utf8).write(to: URL(filePath: Self.checksFile))
        let copy = try Copy.make("everyday")
        defer { copy.remove() }
        let app = launch(copy.repo, ["-VraiIsland", "off"])

        let head = app.tables["Commits"].tableRows.element(boundBy: 1)
        XCTAssertTrue(head.waitForExistence(timeout: 5))
        head.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let pill = app.buttons["checks-pill"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        let failed = app.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", "1 of 3 checks failed", "1 of 3 checks failed")).firstMatch.exists
        pill.click()
        let popover = app.descendants(matching: .any)["checks-popover"].firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Tests / test")).firstMatch.exists)
        if failed { XCTAssertTrue(app.buttons["checks-rerun"].exists) }
        attach(app, "checks-popover-dark")
        app.typeKey(.escape, modifierFlags: [])
        app.terminate()
    }

    @MainActor
    func testIslandAnnouncesAnAddedRemote() throws {
        let copy = try Copy.make("everyday")
        defer { copy.remove() }
        let app = launch(copy.repo, ["-VraiIsland", "everything"])

        app.menuBars.menuBarItems["Repository"].click()
        let remotes = app.menuItems["Remotes"]
        XCTAssertTrue(remotes.waitForExistence(timeout: 5))
        remotes.hover()
        let add = app.menuItems["Add remote\u{2026}"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.click()
        let name = app.textFields["Name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeText("upstream")
        let url = app.textFields["URL"].firstMatch
        url.click()
        url.typeText("https://github.com/aaravmaloo/vrai.git")
        app.buttons.matching(NSPredicate(format: "label == %@", "Add remote")).allElementsBoundByIndex.last?.click()

        let shown = island(app)
        XCTAssertTrue(shown.waitForExistence(timeout: 5))
        XCTAssertTrue(try eventually { try copy.git(["config", "--get", "remote.upstream.url"]).output.contains("aaravmaloo/vrai") })
        shown.hover()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", "Added remote upstream", "Added remote upstream")).firstMatch.waitForExistence(timeout: 5))
        attach(app, "island-remote-added", screen: true)
        XCTAssertTrue(eventually(12) { !island(app).exists })
        app.terminate()
    }

    @MainActor
    func testTouchIDInTheIslandConfirmsAForcePush() throws {
        let copy = try Copy.make("push-rejected")
        defer { copy.remove() }
        XCTAssertEqual(try copy.git(["fetch", "--quiet", "origin"]).status, 0)
        let app = launch(copy.repo, ["-VraiIsland", "activity", "-VraiAuth", "approve"])
        let local = try copy.value(["rev-parse", "refs/heads/feature/graph-renderer"])
        XCTAssertNotEqual(try copy.value(["rev-parse", "refs/heads/feature/graph-renderer"], in: copy.remote("origin")), local)

        app.typeKey("p", modifierFlags: [.option, .shift, .command])
        let shown = island(app)
        XCTAssertTrue(shown.waitForExistence(timeout: 5))
        attach(app, "island-touch-id", screen: true)
        XCTAssertTrue(try eventually(15) { try copy.value(["rev-parse", "refs/heads/feature/graph-renderer"], in: copy.remote("origin")) == local })
        app.terminate()
    }

    @MainActor
    func testCancelledTouchIDLeavesTheRemoteAlone() throws {
        let copy = try Copy.make("push-rejected")
        defer { copy.remove() }
        let app = launch(copy.repo, ["-VraiIsland", "activity", "-VraiAuth", "deny"])
        let remote = try copy.value(["rev-parse", "refs/heads/feature/graph-renderer"], in: copy.remote("origin"))

        app.typeKey("p", modifierFlags: [.option, .shift, .command])
        XCTAssertTrue(eventually(8) { !island(app).exists })
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(try copy.value(["rev-parse", "refs/heads/feature/graph-renderer"], in: copy.remote("origin")), remote)
        app.terminate()
    }

    @MainActor
    func testWithoutTouchIDTheAlertStillAsks() throws {
        let copy = try Copy.make("push-rejected")
        defer { copy.remove() }
        let app = launch(copy.repo, ["-VraiIsland", "activity"])
        app.typeKey("p", modifierFlags: [.option, .shift, .command])
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Force push")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(island(app).exists)
        app.terminate()
    }

    @MainActor
    func testAPausedRebaseLivesInTheNotch() throws {
        let copy = try Copy.make("rebase")
        defer { copy.remove() }
        let app = launch(copy.repo, ["-VraiIsland", "activity"])
        XCTAssertTrue(island(app).waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["island.action.Continue"].exists)
        attach(app, "island-rebase-compact", screen: true)
        island(app).hover()
        XCTAssertTrue(app.buttons["island.action.Continue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", "Rebasing", "Rebasing")).firstMatch.exists)
        XCTAssertTrue(app.buttons["island.action.Abort"].exists)
        attach(app, "island-rebase", screen: true)
        app.terminate()
    }

    @MainActor
    func testBisectCanBeMarkedFromTheNotch() throws {
        let copy = try Copy.make("bisect")
        defer { copy.remove() }
        let app = launch(copy.repo, ["-VraiIsland", "activity"])
        XCTAssertTrue(island(app).waitForExistence(timeout: 8))
        island(app).hover()
        let good = app.buttons["island.action.Good"]
        XCTAssertTrue(good.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["island.action.Bad"].exists)
        attach(app, "island-bisect", screen: true)
        let before = try copy.git(["bisect", "log"]).output
        good.click()
        XCTAssertTrue(try eventually(10) { try copy.git(["bisect", "log"]).output != before })
        app.terminate()
    }
}
