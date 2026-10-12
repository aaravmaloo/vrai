import XCTest

final class ScenarioScreenshotTests: XCTestCase {
    typealias Variant = HistoryScreenshotTests.Variant

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ path: String?, variant: Variant) -> XCUIApplication {
        let defaults = UserDefaults(suiteName: Sandbox.root + "/com.aaravmaloo.vrai.sandbox")
        defaults?.set(false, forKey: "expert")
        defaults?.synchronize()
        let app = XCUIApplication()
        var arguments = ["-VraiSandbox", Sandbox.root]
        if let path { arguments += ["-VraiOpen", path, "-VraiWindowSize", variant.size] }
        arguments += ["-VraiAppearance", variant.appearance, "-VraiNow", Sandbox.now, "-VraiCapture", "YES", "-ApplePersistenceIgnoreState", "YES"]
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.activate()
        return app
    }

    @MainActor
    private func waitForHistory(_ app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1.5)
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ scenario: String, _ variant: Variant) {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.02)).hover()
        Thread.sleep(forTimeInterval: 0.3)
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = "scenario-\(scenario)-\(variant.rawValue)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func button(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    private func textContaining(_ app: XCUIApplication, _ value: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", value, value)).firstMatch
    }

    @MainActor
    private func history(_ scenario: String) {
        for variant in Variant.allCases {
            let app = launch(Sandbox.fixture(scenario), variant: variant)
            waitForHistory(app)
            attach(app, scenario, variant)
            app.terminate()
        }
    }

    @MainActor
    private func network(_ scenario: String, press: String, expect: String) {
        for variant in Variant.allCases {
            if scenario == "auth" { try? plantExpiredCredential() }
            let app = launch(Sandbox.fixture(scenario), variant: variant)
            waitForHistory(app)
            let control = button(app, press)
            if control.waitForExistence(timeout: 5), control.isHittable {
                control.click()
            } else {
                app.menuBars.menuBarItems["Repository"].click()
                app.menuBars.menuItems[press].firstMatch.click()
            }
            XCTAssertTrue(textContaining(app, expect).waitForExistence(timeout: 20), "\(scenario) \(variant.rawValue): \(expect)")
            Thread.sleep(forTimeInterval: 0.6)
            attach(app, scenario, variant)
            app.terminate()
        }
    }

    private func plantExpiredCredential() throws {
        let current = (try? String(contentsOfFile: SyncFlowTests.credentials, encoding: .utf8)) ?? ""
        let lines = current.split(separator: "\n").map(String.init).filter { !$0.contains("127.0.0.1%3a" + SyncFlowTests.authPort) }
        try (lines + [SyncFlowTests.expiredLine]).joined(separator: "\n").appending("\n").write(toFile: SyncFlowTests.credentials, atomically: true, encoding: .utf8)
    }

    @MainActor
    private func changes(_ scenario: String) {
        for variant in Variant.allCases {
            let app = launch(Sandbox.fixture(scenario), variant: variant)
            ChangesFixtureCopy.openChanges(app)
            Thread.sleep(forTimeInterval: 1.0)
            attach(app, scenario, variant)
            app.terminate()
        }
    }

    @MainActor
    func testEveryday() throws { history("everyday") }

    @MainActor
    func testPushRejected() throws { network("push-rejected", press: "Push 2 commits", expect: "Push rejected") }

    @MainActor
    func testConflict() throws { changes("conflict") }

    @MainActor
    func testRebase() throws { history("rebase") }

    @MainActor
    func testDetached() throws { history("detached") }

    @MainActor
    func testBisect() throws { history("bisect") }

    @MainActor
    func testAuth() throws { network("auth", press: "Fetch", expect: "didn't accept your credentials") }

    @MainActor
    func testOffline() throws { network("offline", press: "Fetch", expect: "is reachable") }

    @MainActor
    func testEmpty() throws { changes("empty") }

    @MainActor
    func testLoading() throws {
        for variant in Variant.allCases {
            let app = launch(Sandbox.root + "/fixtures/large/monorepo", variant: variant)
            attach(app, "loading", variant)
            waitForHistory(app)
            app.terminate()
        }
    }

    @MainActor
    func testWelcome() throws {
        let recents = URL(filePath: Sandbox.root + "/recents.json")
        let saved = try? Data(contentsOf: recents)
        defer { if let saved { try? saved.write(to: recents, options: .atomic) } }
        let fixture = try Data(contentsOf: URL(filePath: Sandbox.root + "/fixtures/welcome/recents.json"))
        for variant in [Variant.light, .dark] {
            try fixture.write(to: recents, options: .atomic)
            let app = launch(nil, variant: variant)
            XCTAssertTrue(app.buttons["welcome-clone"].waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 1.0)
            attach(app, "welcome", variant)
            app.terminate()
        }
    }
}
