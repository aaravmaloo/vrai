import XCTest

final class ExpertFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSheetCommandIsEditableAndRunsAsTyped() throws {
        let fixture = try RewriteFixture.copy("everyday")
        addTeardownBlock { fixture.remove() }
        let app = fixture.launch()
        ConsoleUI.waitForHistory(app)
        ConsoleUI.setExpert(app, true)
        app.typeKey("j", modifierFlags: .command)
        app.typeKey("b", modifierFlags: [.command, .shift])
        let preview = app.textFields["command-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        let built = preview.value as? String ?? ""
        XCTAssertTrue(built.hasPrefix("git "), built)
        ChangesFixtureCopy.attach(self, app, name: "expert-sheet-preview-light")
        preview.click()
        preview.typeKey("a", modifierFlags: .command)
        preview.typeText("git branch expert-edited main")
        XCTAssertTrue(app.staticTexts["Runs as you typed it, and the output shows in the console."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Use the command Vrai built"].exists)
        ChangesFixtureCopy.attach(self, app, name: "expert-sheet-edited-light")
        let create = app.buttons["Create and switch"].exists ? app.buttons["Create and switch"] : app.buttons["Create branch"]
        XCTAssertTrue(create.isEnabled)
        create.click()
        XCTAssertTrue(ConsoleUI.wait(timeout: 15) { (try? fixture.git(["rev-parse", "--verify", "--quiet", "refs/heads/expert-edited"]).status) == 0 })
        XCTAssertEqual(try fixture.git(["rev-parse", "expert-edited"]).output, try fixture.git(["rev-parse", "main"]).output)
        XCTAssertNotEqual(try fixture.git(["symbolic-ref", "--short", "HEAD"]).output.trimmingCharacters(in: .whitespacesAndNewlines), "expert-edited")
        XCTAssertTrue(ConsoleUI.entry(app, "git branch expert-edited main").waitForExistence(timeout: 10))
        ConsoleUI.setExpert(app, false)
        app.terminate()
    }

    @MainActor
    func testRevertingAnEditGoesBackToTheBuiltCommand() throws {
        let app = ChangesFixtureCopy.launch(Sandbox.fixture("everyday"), size: "1280x800")
        ConsoleUI.waitForHistory(app)
        ConsoleUI.setExpert(app, true)
        app.typeKey("j", modifierFlags: .command)
        app.typeKey("b", modifierFlags: [.command, .shift])
        let preview = app.textFields["command-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        let built = preview.value as? String ?? ""
        preview.click()
        preview.typeKey("a", modifierFlags: .command)
        preview.typeText("git -c core.editor=vim branch x")
        let revert = app.buttons["Use the command Vrai built"]
        XCTAssertTrue(revert.waitForExistence(timeout: 5))
        let create = app.buttons["Create and switch"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.click()
        XCTAssertTrue(app.staticTexts["Put the git command first, like git status. Options before it, such as -C or -c, don't run here."].waitForExistence(timeout: 5))
        revert.click()
        XCTAssertTrue(ConsoleUI.wait { (preview.value as? String) == built })
        XCTAssertFalse(create.isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        ConsoleUI.setExpert(app, false)
        app.terminate()
    }

    @MainActor
    func testPreviewIsReadOnlyOutsideExpertMode() throws {
        let app = ChangesFixtureCopy.launch(Sandbox.fixture("everyday"), size: "1280x800")
        ConsoleUI.waitForHistory(app)
        ConsoleUI.setExpert(app, false)
        app.typeKey("j", modifierFlags: .command)
        app.typeKey("b", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["New branch"].waitForExistence(timeout: 5))
        let options = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Options")).firstMatch
        if options.exists { options.click() }
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "git branch")).firstMatch.waitForExistence(timeout: 5) || app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "git switch")).firstMatch.exists)
        XCTAssertFalse(app.textFields["command-preview"].exists)
        ChangesFixtureCopy.attach(self, app, name: "expert-sheet-off-light")
        app.typeKey(.escape, modifierFlags: [])
        app.terminate()
    }

    @MainActor
    func testNotesAreAddedEditedAndRemovedFromTheInspector() throws {
        let fixture = try RewriteFixture.copy("everyday")
        addTeardownBlock { fixture.remove() }
        let subject = try fixture.git(["log", "-1", "--format=%s"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = try fixture.git(["rev-parse", "HEAD"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = fixture.launch()
        ConsoleUI.waitForHistory(app)
        ConsoleUI.setExpert(app, true)
        app.typeKey("j", modifierFlags: .command)
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", subject + ",")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        let editor = app.textViews["Note"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeText("Reviewed in the flow test")
        app.buttons["Add note"].click()
        XCTAssertTrue(ConsoleUI.wait(timeout: 10) { (try? fixture.git(["notes", "show", id]).output.trimmingCharacters(in: .whitespacesAndNewlines)) == "Reviewed in the flow test" })
        XCTAssertTrue(app.staticTexts["Reviewed in the flow test"].waitForExistence(timeout: 5))
        ChangesFixtureCopy.attach(self, app, name: "expert-note-light")

        app.buttons["Edit note"].click()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("Reviewed twice")
        app.buttons["Save note"].click()
        XCTAssertTrue(ConsoleUI.wait(timeout: 10) { (try? fixture.git(["notes", "show", id]).output.trimmingCharacters(in: .whitespacesAndNewlines)) == "Reviewed twice" })

        app.buttons["Remove note"].click()
        XCTAssertTrue(ConsoleUI.wait(timeout: 10) { (try? fixture.git(["notes", "show", id]).status) != 0 })
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        ConsoleUI.setExpert(app, false)
        app.terminate()
    }

    @MainActor
    func testShowObjectRunsCatFileInTheConsole() throws {
        let fixture = try RewriteFixture.copy("everyday")
        addTeardownBlock { fixture.remove() }
        let subject = try fixture.git(["log", "-1", "--format=%s"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = try fixture.git(["rev-parse", "HEAD"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = fixture.launch()
        ConsoleUI.waitForHistory(app)
        ConsoleUI.setExpert(app, true)
        app.typeKey("j", modifierFlags: .command)
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", subject + ",")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.rightClick()
        let item = app.menuItems["Show object"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
        let entry = ConsoleUI.entry(app, "git cat-file -p " + id)
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        XCTAssertTrue(entry.label.contains("succeeded"), entry.label)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "tree ", "tree ")).firstMatch.waitForExistence(timeout: 5))
        ChangesFixtureCopy.attach(self, app, name: "expert-show-object-light")
        ConsoleUI.setExpert(app, false)
        app.terminate()
    }

    @MainActor
    func testExpertItemsInTheMenuBar() throws {
        let app = ChangesFixtureCopy.launch(Sandbox.fixture("everyday"), size: "1280x800")
        ConsoleUI.waitForHistory(app)
        ConsoleUI.setExpert(app, true)
        app.menuBars.menuBarItems["Window"].click()
        XCTAssertTrue(app.menuBars.menuItems["Console"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        app.menuBars.menuBarItems["Branch"].click()
        XCTAssertTrue(app.menuBars.menuItems["Switch to\u{2026}"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        app.menuBars.menuBarItems["View"].click()
        XCTAssertTrue(app.menuBars.menuItems.matching(NSPredicate(format: "title IN %@", ["Show console", "Hide console"])).firstMatch.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        app.menuBars.menuBarItems["Help"].click()
        XCTAssertTrue(app.menuBars.menuItems["Git reference"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        ConsoleUI.setExpert(app, false)
        app.terminate()
    }
}
