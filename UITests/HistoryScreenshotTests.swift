import XCTest

final class HistoryScreenshotTests: XCTestCase {
    enum Variant: String, CaseIterable {
        case light
        case dark
        case w700
        case w460

        var appearance: String { self == .dark ? "dark" : "light" }

        var size: String {
            switch self {
            case .light, .dark: "1280x800"
            case .w700: "700x800"
            case .w460: "460x800"
            }
        }
    }

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(path: String, variant: Variant) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-VraiSandbox", Sandbox.root,
            "-VraiOpen", path,
            "-VraiAppearance", variant.appearance,
            "-VraiNow", Sandbox.now,
            "-VraiWindowSize", variant.size,
            "-VraiCapture", "YES",
            "-ApplePersistenceIgnoreState", "YES"
        ]
        app.launch()
        return app
    }

    @MainActor
    private func waitForHistory(_ app: XCUIApplication) {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.5)
    }

    @MainActor
    private func capture(_ scenario: String) {
        for variant in Variant.allCases {
            let app = launch(path: Sandbox.fixture(scenario), variant: variant)
            waitForHistory(app)
            app.activate()
            let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            shot.name = "history-\(scenario)-\(variant.rawValue)"
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }

    @MainActor
    func testEveryday() throws {
        capture("everyday")
    }

    @MainActor
    func testDetached() throws {
        capture("detached")
    }

    @MainActor
    func testEmpty() throws {
        capture("empty")
    }

    @MainActor
    func testBisect() throws {
        capture("bisect")
    }

    @MainActor
    func testRebase() throws {
        capture("rebase")
    }

    @MainActor
    func testOutsideCommitAppearsWithoutInteraction() throws {
        let folder = Sandbox.root + "/tests/" + UUID().uuidString
        let copy = folder + "/vrai"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: Sandbox.fixture("everyday"), toPath: copy)
        FixtureHooks.useOriginals(copy: copy, original: Sandbox.fixture("everyday"))
        defer {
            try? FileManager.default.removeItem(atPath: folder)
            Sandbox.forgetRecent(copy)
        }

        let app = launch(path: copy, variant: .light)
        waitForHistory(app)
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "test, ")).firstMatch
        XCTAssertFalse(row.exists)

        let started = Date()
        let outcome = try Sandbox.git(["-c", "core.hooksPath=/dev/null", "commit", "--allow-empty", "-m", "test"], in: copy)
        XCTAssertEqual(outcome.status, 0, outcome.output)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 2.5)

        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = "history-outside-commit"
        shot.lifetime = .keepAlways
        add(shot)
        app.terminate()
    }
}
