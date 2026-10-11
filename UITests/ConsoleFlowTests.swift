import XCTest

final class ConsoleFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testConsoleListsWhatVraiRunsAndFilters() throws {
        let fixture = try RewriteFixture.copy("everyday")
        addTeardownBlock { fixture.remove() }
        let app = fixture.launch()
        ConsoleUI.waitForHistory(app)
        ConsoleUI.setExpert(app, false)
        let console = ConsoleUI.console(app)
        let entries = console.descendants(matching: .any).matching(identifier: "console-entry")
        XCTAssertTrue(entries.firstMatch.waitForExistence(timeout: 10) || console.buttons.matching(NSPredicate(format: "label CONTAINS %@", "background command")).firstMatch.exists)
        XCTAssertTrue(console.buttons["Turn on Expert mode"].exists)
        ConsoleUI.menu(app, "Repository", "Fetch")
        let fetch = entries.matching(NSPredicate(format: "label CONTAINS %@", "git fetch")).firstMatch
        XCTAssertTrue(fetch.waitForExistence(timeout: 20))
        ChangesFixtureCopy.attach(self, app, name: "console-all-light")
        console.buttons["Background"].click()
        XCTAssertTrue(entries.matching(NSPredicate(format: "label BEGINSWITH %@", "Vrai, ")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(entries.matching(NSPredicate(format: "label CONTAINS %@", "git fetch")).firstMatch.exists)
        console.buttons["Failed"].click()
        XCTAssertTrue(console.staticTexts["No failed commands."].waitForExistence(timeout: 5))
        console.buttons["All"].click()
        let field = console.textFields["Filter commands and output"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        ChangesFixtureCopy.type("git fetch", into: field)
        XCTAssertTrue(fetch.waitForExistence(timeout: 5))
        XCTAssertTrue(ConsoleUI.wait { entries.count == 1 })
        app.typeKey("j", modifierFlags: .command)
        XCTAssertTrue(ChangesFixtureCopy.waitUntilGone(console, timeout: 5))
        let button = app.buttons["Show console"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.click()
        XCTAssertTrue(console.waitForExistence(timeout: 5))
        app.terminate()
    }

    @MainActor
    func testTypedCommandRunsAsArgumentsNotThroughAShell() throws {
        let fixture = try RewriteFixture.copy("everyday")
        addTeardownBlock { fixture.remove() }
        let app = fixture.launch()
        ConsoleUI.waitForHistory(app)
        ConsoleUI.setExpert(app, true)
        let marker = fixture.root + "/Sources"
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker))
        let typed = "git log --oneline -3; rm -rf Sources"
        ConsoleUI.run(app, typed)
        let entry = ConsoleUI.entry(app, typed)
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        XCTAssertTrue(entry.label.contains("failed"), entry.label)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: marker).isEmpty)

        ConsoleUI.run(app, "status --short")
        let status = ConsoleUI.entry(app, "git status --short")
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        XCTAssertTrue(status.label.contains("succeeded"), status.label)
        XCTAssertTrue(status.label.hasPrefix("You, "), status.label)

        let prompt = app.textFields["console-prompt"]
        prompt.click()
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(ConsoleUI.wait { (prompt.value as? String) == "git status --short" })
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(ConsoleUI.wait { (prompt.value as? String) == typed })
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(ConsoleUI.wait { (prompt.value as? String) == "git status --short" })
        ChangesFixtureCopy.attach(self, app, name: "console-expert-prompt-light")
        prompt.typeKey("a", modifierFlags: .command)
        prompt.typeKey(.delete, modifierFlags: [])

        ConsoleUI.run(app, "-c core.editor=vim commit")
        XCTAssertTrue(app.staticTexts["Put the git command first, like git status. Options before it, such as -C or -c, don't run here."].waitForExistence(timeout: 5))
        ConsoleUI.setExpert(app, false)
        app.terminate()
    }

    @MainActor
    func testFailedCommandOpensTheConsoleWithItsOutput() throws {
        let fixture = try RewriteFixture.copy("everyday")
        addTeardownBlock { fixture.remove() }
        let app = fixture.launch()
        ConsoleUI.waitForHistory(app)
        ConsoleUI.setExpert(app, true)
        let console = ConsoleUI.console(app)
        app.typeKey("j", modifierFlags: .command)
        XCTAssertTrue(ChangesFixtureCopy.waitUntilGone(console, timeout: 5))
        PaletteUI.open(app)
        PaletteUI.query(app, "git checkout no-such-branch")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(console.waitForExistence(timeout: 15))
        let entry = ConsoleUI.entry(app, "git checkout no-such-branch")
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        XCTAssertTrue(entry.label.contains("failed"), entry.label)
        XCTAssertTrue(console.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "no-such-branch", "no-such-branch")).count > 1)
        console.buttons["Failed"].click()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        ChangesFixtureCopy.attach(self, app, name: "console-failed-light")
        entry.rightClick()
        XCTAssertTrue(app.menuItems["Copy command"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.menuItems["Run again"].exists)
        app.typeKey(.escape, modifierFlags: [])
        ConsoleUI.setExpert(app, false)
        app.terminate()
    }

    @MainActor
    func testConsoleLeavesTheContentItsHeightAtEverySize() throws {
        for (size, name) in [("1280x800", "default"), ("1000x700", "w1000"), ("700x800", "w700"), ("460x800", "w460"), ("1280x500", "h500")] {
            for appearance in ["light", "dark"] {
                let app = ChangesFixtureCopy.launch(Sandbox.fixture("everyday"), appearance: appearance, size: size)
                ConsoleUI.waitForHistory(app)
                ConsoleUI.setExpert(app, true)
                let console = ConsoleUI.console(app)
                let window = app.windows.firstMatch
                let commits = app.descendants(matching: .any)["commits"]
                Thread.sleep(forTimeInterval: 1)
                XCTAssertGreaterThan(commits.frame.height, 100, "\(name) \(appearance): the history list collapsed under the console")
                XCTAssertLessThanOrEqual(commits.frame.maxY, console.frame.minY + 1, "\(name) \(appearance): the console covers the history list")
                XCTAssertLessThanOrEqual(console.frame.maxY, window.frame.maxY + 1, "\(name) \(appearance): the console runs past the window")
                XCTAssertTrue(app.textFields["console-prompt"].isHittable, "\(name) \(appearance): the prompt can't be reached")
                ChangesFixtureCopy.attach(self, app, name: "console-\(name)-\(appearance)")
                ConsoleUI.setExpert(app, false)
                ChangesFixtureCopy.attach(self, app, name: "console-\(name)-\(appearance)-off")
                app.terminate()
            }
        }
    }
}

enum ConsoleUI {
    @MainActor
    static func waitForHistory(_ app: XCUIApplication) {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 15))
        app.activate()
    }

    @MainActor
    static func console(_ app: XCUIApplication) -> XCUIElement {
        let console = app.descendants(matching: .any)["console"]
        if !console.exists {
            app.activate()
            app.typeKey("j", modifierFlags: .command)
        }
        XCTAssertTrue(console.waitForExistence(timeout: 5))
        return console
    }

    @MainActor
    static func setExpert(_ app: XCUIApplication, _ on: Bool) {
        let console = console(app)
        let prompt = app.textFields["console-prompt"]
        let turnOn = console.buttons["Turn on Expert mode"]
        for _ in 0..<3 {
            if on ? prompt.waitForExistence(timeout: 2) : turnOn.waitForExistence(timeout: 2) { return }
            app.typeKey("e", modifierFlags: [.command, .option])
        }
        XCTFail(on ? "Expert mode didn't turn on" : "Expert mode didn't turn off")
    }

    @MainActor
    static func run(_ app: XCUIApplication, _ text: String) {
        let prompt = app.textFields["console-prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        ChangesFixtureCopy.type(text, into: prompt)
        app.typeKey(.return, modifierFlags: [])
    }

    @MainActor
    static func entry(_ app: XCUIApplication, _ command: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "console-entry").matching(NSPredicate(format: "label CONTAINS %@", ", " + command + ", ")).firstMatch
    }

    @MainActor
    static func menu(_ app: XCUIApplication, _ menu: String, _ title: String) {
        for _ in 0..<5 {
            app.activate()
            app.menuBars.menuBarItems[menu].click()
            let item = app.menuBars.menuItems[title]
            if item.waitForExistence(timeout: 3), item.isEnabled {
                item.click()
                return
            }
            app.typeKey(.escape, modifierFlags: [])
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTFail("Menu item \(title) stayed disabled")
    }

    @MainActor
    static func wait(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }
}
