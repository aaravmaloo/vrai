import XCTest

final class PaletteFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCommandKFindsBranchesActionsAndFiles() throws {
        let app = ChangesFixtureCopy.launch(Sandbox.fixture("everyday"), size: "1280x800")
        ConsoleUI.waitForHistory(app)
        PaletteUI.open(app)
        let palette = PaletteUI.palette(app)
        XCTAssertTrue(palette.staticTexts["Suggestions"].exists || palette.staticTexts["Actions"].exists)
        ChangesFixtureCopy.attach(self, app, name: "palette-empty-light")
        PaletteUI.query(app, "line")
        XCTAssertTrue(PaletteUI.item(app, "feature/line-staging").waitForExistence(timeout: 5))
        ChangesFixtureCopy.attach(self, app, name: "palette-branch-light")
        PaletteUI.query(app, "lanelayout")
        XCTAssertTrue(PaletteUI.item(app, "LaneLayout.swift").waitForExistence(timeout: 10))
        PaletteUI.query(app, "fetch")
        XCTAssertTrue(PaletteUI.item(app, "Fetch").waitForExistence(timeout: 5))
        PaletteUI.query(app, "snap nodes")
        XCTAssertTrue(PaletteUI.item(app, "Graph: snap nodes to the pixel grid").waitForExistence(timeout: 10))
        ChangesFixtureCopy.attach(self, app, name: "palette-commit-light")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(ConsoleUI.wait { (PaletteUI.field(app).value as? String ?? "").isEmpty })
        XCTAssertTrue(palette.exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(ChangesFixtureCopy.waitUntilGone(palette, timeout: 5))
        app.terminate()
    }

    @MainActor
    func testToolbarFieldOpensThePaletteAndArrowsMoveTheSelection() throws {
        let app = ChangesFixtureCopy.launch(Sandbox.fixture("everyday"), size: "1280x800")
        ConsoleUI.waitForHistory(app)
        let field = app.descendants(matching: .any)["toolbar-palette-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        let palette = PaletteUI.palette(app)
        PaletteUI.query(app, "branch")
        let items = palette.descendants(matching: .any).matching(identifier: "palette-item")
        XCTAssertTrue(ConsoleUI.wait { items.count >= 3 })
        XCTAssertTrue(items.element(boundBy: 0).isSelected)
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(ConsoleUI.wait { items.element(boundBy: 1).isSelected })
        XCTAssertFalse(items.element(boundBy: 0).isSelected)
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(ConsoleUI.wait { items.element(boundBy: 0).isSelected })
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(ChangesFixtureCopy.waitUntilGone(palette, timeout: 5))
        ConsoleUI.menu(app, "Edit", "Command palette")
        XCTAssertTrue(palette.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        app.terminate()
    }

    @MainActor
    func testSwitchToListsBranchesAndSwitches() throws {
        let fixture = try RewriteFixture.copy("everyday")
        addTeardownBlock { fixture.remove() }
        try fixture.clean()
        let app = fixture.launch()
        ConsoleUI.waitForHistory(app)
        app.typeKey("b", modifierFlags: .command)
        let palette = PaletteUI.palette(app)
        XCTAssertTrue(palette.staticTexts["Branches"].waitForExistence(timeout: 5))
        XCTAssertTrue(PaletteUI.item(app, "main").exists)
        PaletteUI.query(app, "line-staging")
        XCTAssertTrue(PaletteUI.item(app, "feature/line-staging").waitForExistence(timeout: 5))
        ChangesFixtureCopy.attach(self, app, name: "palette-switch-light")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(ChangesFixtureCopy.waitUntilGone(palette, timeout: 5))
        XCTAssertTrue(ConsoleUI.wait(timeout: 15) { (try? fixture.git(["symbolic-ref", "--short", "HEAD"]).output.trimmingCharacters(in: .whitespacesAndNewlines)) == "feature/line-staging" })

        app.typeKey("b", modifierFlags: .command)
        XCTAssertTrue(palette.waitForExistence(timeout: 5))
        PaletteUI.query(app, "feature/palette-test")
        XCTAssertTrue(PaletteUI.item(app, "Create branch \u{201C}feature/palette-test\u{201D}\u{2026}").waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        app.terminate()
    }

    @MainActor
    func testGitCommandsAskForExpertMode() throws {
        let app = ChangesFixtureCopy.launch(Sandbox.fixture("everyday"), size: "1280x800")
        ConsoleUI.waitForHistory(app)
        ConsoleUI.setExpert(app, false)
        app.typeKey("j", modifierFlags: .command)
        PaletteUI.open(app)
        PaletteUI.query(app, "git status")
        XCTAssertTrue(PaletteUI.item(app, "git status").waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Running git commands is part of Expert mode"].waitForExistence(timeout: 5))
        ChangesFixtureCopy.attach(self, app, name: "palette-expert-toast-light")
        app.terminate()
    }

    @MainActor
    func testExpertRunsGitFromThePaletteWithItsRiskTag() throws {
        let fixture = try RewriteFixture.copy("everyday")
        addTeardownBlock { fixture.remove() }
        let app = fixture.launch()
        ConsoleUI.waitForHistory(app)
        ConsoleUI.setExpert(app, true)
        let head = try fixture.git(["rev-parse", "HEAD"]).output
        PaletteUI.open(app)
        let palette = PaletteUI.palette(app)
        XCTAssertTrue(palette.staticTexts["Expert"].exists)
        PaletteUI.query(app, "git reset --hard HEAD~1")
        XCTAssertTrue(PaletteUI.item(app, "git reset --hard HEAD~1").waitForExistence(timeout: 5))
        XCTAssertTrue(palette.staticTexts["Run in git"].exists)
        XCTAssertTrue(palette.staticTexts["Destructive"].exists)
        ChangesFixtureCopy.attach(self, app, name: "palette-expert-risk-light")
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(ChangesFixtureCopy.waitUntilGone(palette, timeout: 5))
        XCTAssertEqual(try fixture.git(["rev-parse", "HEAD"]).output, head)

        PaletteUI.open(app)
        PaletteUI.query(app, "git log --oneline -2")
        app.typeKey(.return, modifierFlags: [])
        let entry = ConsoleUI.entry(app, "git log --oneline -2")
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        XCTAssertTrue(entry.label.contains("succeeded"), entry.label)
        ConsoleUI.setExpert(app, false)
        app.terminate()
    }

    @MainActor
    func testPaletteFitsEveryWindowSize() throws {
        for (size, name) in [("1280x800", "default"), ("1000x700", "w1000"), ("700x800", "w700"), ("460x800", "w460"), ("1280x500", "h500")] {
            for appearance in ["light", "dark"] {
                let app = ChangesFixtureCopy.launch(Sandbox.fixture("everyday"), appearance: appearance, size: size)
                ConsoleUI.waitForHistory(app)
                PaletteUI.open(app)
                PaletteUI.query(app, "graph")
                let palette = PaletteUI.palette(app)
                let items = palette.descendants(matching: .any).matching(identifier: "palette-item")
                XCTAssertTrue(items.firstMatch.waitForExistence(timeout: 5))
                Thread.sleep(forTimeInterval: 0.8)
                let window = app.windows.firstMatch.frame
                XCTAssertGreaterThanOrEqual(palette.frame.minX, window.minX, "\(name) \(appearance): the palette runs off the left")
                XCTAssertLessThanOrEqual(palette.frame.maxX, window.maxX, "\(name) \(appearance): the palette runs off the right")
                XCTAssertLessThanOrEqual(palette.frame.maxY, window.maxY, "\(name) \(appearance): the palette runs off the bottom")
                XCTAssertTrue(PaletteUI.field(app).isHittable)
                ChangesFixtureCopy.attach(self, app, name: "palette-\(name)-\(appearance)")
                app.typeKey(.escape, modifierFlags: [])
                app.typeKey(.escape, modifierFlags: [])
                app.terminate()
            }
        }
    }
}

enum PaletteUI {
    @MainActor
    static func palette(_ app: XCUIApplication) -> XCUIElement {
        let palette = app.descendants(matching: .any)["command-palette"]
        XCTAssertTrue(palette.waitForExistence(timeout: 5))
        return palette
    }

    @MainActor
    static func field(_ app: XCUIApplication) -> XCUIElement {
        app.textFields["palette-field"]
    }

    @MainActor
    static func open(_ app: XCUIApplication) {
        let palette = app.descendants(matching: .any)["command-palette"]
        for _ in 0..<3 where !palette.exists {
            app.activate()
            app.typeKey("k", modifierFlags: .command)
            if palette.waitForExistence(timeout: 3) { break }
        }
        XCTAssertTrue(palette.exists)
    }

    @MainActor
    static func query(_ app: XCUIApplication, _ text: String) {
        let field = field(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        if !((field.value as? String) ?? "").isEmpty {
            field.typeKey("a", modifierFlags: .command)
            field.typeKey(.delete, modifierFlags: [])
        }
        field.typeText(text)
    }

    @MainActor
    static func item(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "palette-item").matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label + ", ")).firstMatch
    }
}
