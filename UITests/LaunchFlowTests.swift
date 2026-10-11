import XCTest

final class LaunchFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(appearance: String) -> XCUIApplication {
        let sandbox = ProcessInfo.processInfo.environment["VRAI_SANDBOX"] ?? NSTemporaryDirectory() + "vrai-sandbox"
        let app = XCUIApplication()
        app.launchArguments = ["-VraiSandbox", sandbox, "-VraiAppearance", appearance, "-VraiNow", "1791720000", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        return app
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testEmptyRepositoryWindowLight() throws {
        let app = launch(appearance: "light")
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No repository open"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.outlines.firstMatch.staticTexts["History"].exists)
        XCTAssertTrue(app.toolbars.buttons["Fetch"].exists)
        attach(app, name: "m0-empty-window-light")
        app.terminate()
    }

    @MainActor
    func testEmptyRepositoryWindowDark() throws {
        let app = launch(appearance: "dark")
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No repository open"].waitForExistence(timeout: 5))
        attach(app, name: "m0-empty-window-dark")
        app.terminate()
    }

    @MainActor
    func testAppIconInTheDock() throws {
        let app = launch(appearance: "light")
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        let dock = XCUIApplication(bundleIdentifier: "com.apple.dock")
        let item = dock.descendants(matching: .any).matching(NSPredicate(format: "title == %@", "Vrai")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: item.screenshot())
        shot.name = "m0-dock-icon"
        shot.lifetime = .keepAlways
        add(shot)
        app.terminate()
    }
}
