import XCTest

final class LongTailFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func open(_ fixture: RewriteFixture, appearance: String = "light", expert: Bool = false) -> XCUIApplication {
        let app = fixture.launch(appearance: appearance)
        let commits = app.descendants(matching: .any)["commits"]
        XCTAssertTrue(commits.waitForExistence(timeout: 15))
        setExpert(app, expert)
        return app
    }

    @MainActor
    private func setExpert(_ app: XCUIApplication, _ on: Bool) {
        let toggle = app.switches["sidebar-expert"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let wanted = on ? "1" : "0"
        if String(describing: toggle.value ?? "") != wanted { toggle.click() }
        XCTAssertTrue(eventually(5) { String(describing: toggle.value ?? "") == wanted }, on ? "Expert mode didn't turn on" : "Expert mode didn't turn off")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func menu(_ app: XCUIApplication, _ bar: String, _ path: String...) {
        app.menuBars.menuBarItems[bar].click()
        for (index, title) in path.enumerated() {
            let item = app.menuItems[title]
            XCTAssertTrue(item.waitForExistence(timeout: 5), title)
            if index < path.count - 1 { item.hover() } else { item.click() }
        }
    }

    @MainActor
    private func row(_ app: XCUIApplication, _ subject: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", subject + ",")).firstMatch
    }

    @MainActor
    private func replace(_ field: XCUIElement, with text: String) {
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
    }

    @MainActor
    private func openOptions(_ app: XCUIApplication) {
        let options = app.sheets.firstMatch.buttons.matching(NSPredicate(format: "label == %@", "Options")).firstMatch
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.click()
    }

    @MainActor
    private func textContaining(_ app: XCUIApplication, _ value: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", value, value)).firstMatch
    }

    private func eventually(_ timeout: TimeInterval = 10, _ condition: () throws -> Bool) rethrows -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if try condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return try condition()
    }

    @MainActor
    func testRepositoryInfoLightAndDark() throws {
        let fixture = try RewriteFixture.copy("everyday")
        defer { fixture.remove() }
        for appearance in ["light", "dark"] {
            let app = open(fixture, appearance: appearance)
            menu(app, "Repository", "Repository info\u{2026}")
            XCTAssertTrue(app.descendants(matching: .any)["repository-info"].waitForExistence(timeout: 15))
            XCTAssertTrue(textContaining(app, "on ").exists)
            attach(app, "j-info-" + appearance)
            app.typeKey(.return, modifierFlags: [])
            app.terminate()
        }
    }

    @MainActor
    func testEditGitignoreSavesTheFile() throws {
        let fixture = try RewriteFixture.copy("everyday")
        defer { fixture.remove() }
        let app = open(fixture)
        menu(app, "Repository", "Edit .gitignore")
        let editor = app.textViews["longtail-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        attach(app, "j-textfile-light")
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("\n*.vrailog")
        app.buttons["textfile-save"].click()
        XCTAssertTrue(eventually(10) { (try? String(contentsOfFile: fixture.root + "/.gitignore", encoding: .utf8))?.contains("*.vrailog") == true })
        XCTAssertTrue(textContaining(app, "Saved .gitignore").waitForExistence(timeout: 5))
        app.terminate()
    }

    @MainActor
    func testCompareBranches() throws {
        let fixture = try RewriteFixture.copy("everyday")
        defer { fixture.remove() }
        let app = open(fixture)
        menu(app, "Branch", "Compare branches\u{2026}")
        XCTAssertTrue(textContaining(app, "doesn't have").waitForExistence(timeout: 15))
        attach(app, "j-compare-light")
        app.buttons["compare-show"].click()
        app.terminate()
    }

    @MainActor
    func testExportArchiveFromTheCommitMenu() throws {
        let fixture = try RewriteFixture.copy("everyday")
        defer { fixture.remove() }
        let output = fixture.folder + "/export.zip"
        let app = open(fixture)
        let commit = row(app, "Graph: keep the HEAD halo above merge rings")
        XCTAssertTrue(commit.waitForExistence(timeout: 10))
        commit.rightClick()
        let item = app.menuItems["Export archive\u{2026}"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
        XCTAssertTrue(app.buttons["archive-run"].waitForExistence(timeout: 5))
        attach(app, "j-archive-light")
        openOptions(app)
        let field = app.textFields["Save as"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replace(field, with: output)
        app.buttons["archive-run"].click()
        XCTAssertTrue(eventually(15) { FileManager.default.fileExists(atPath: output) })
        XCTAssertTrue(textContaining(app, "Exported export.zip").waitForExistence(timeout: 5))
        app.terminate()
    }

    @MainActor
    func testCreateBundle() throws {
        let fixture = try RewriteFixture.copy("everyday")
        defer { fixture.remove() }
        let output = fixture.folder + "/vrai.bundle"
        let app = open(fixture)
        menu(app, "Repository", "Create bundle\u{2026}")
        XCTAssertTrue(app.buttons["bundle-run"].waitForExistence(timeout: 5))
        attach(app, "j-bundle-light")
        openOptions(app)
        let field = app.textFields["Save as"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replace(field, with: output)
        app.buttons["bundle-run"].click()
        XCTAssertTrue(eventually(20) { FileManager.default.fileExists(atPath: output) })
        let verified = try Sandbox.git(["bundle", "verify", output], in: fixture.root)
        XCTAssertEqual(verified.status, 0, verified.output)
        app.terminate()
    }

    @MainActor
    func testRewordInPlaceThenUndo() throws {
        let fixture = try RewriteFixture.copy("everyday")
        defer { fixture.remove() }
        try fixture.clean()
        let app = open(fixture, expert: true)
        let commit = row(app, "Graph: keep the HEAD halo above merge rings")
        XCTAssertTrue(commit.waitForExistence(timeout: 10))
        commit.rightClick()
        let item = app.menuItems["Reword in place\u{2026}"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
        let summary = app.textFields["Summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        attach(app, "j-reword-light")
        replace(summary, with: "Graph: keep the halo on top")
        app.buttons["reword-run"].click()
        XCTAssertTrue(try eventually(20) { try fixture.git(["log", "-1", "--format=%s", "HEAD~1"]).output.trimmingCharacters(in: .whitespacesAndNewlines) == "Graph: keep the halo on top" })
        XCTAssertEqual(try fixture.git(["log", "-1", "--format=%s", "HEAD"]).output.trimmingCharacters(in: .whitespacesAndNewlines), "Graph: draw merge curves with cubic béziers")
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.click()
        XCTAssertTrue(try eventually(20) { try fixture.git(["log", "-1", "--format=%s", "HEAD~1"]).output.trimmingCharacters(in: .whitespacesAndNewlines) == "Graph: keep the HEAD halo above merge rings" })
        setExpert(app, false)
        app.terminate()
    }

    @MainActor
    func testSplitCommitMovesFilesIntoASecondCommit() throws {
        let fixture = try RewriteFixture.copy("everyday")
        defer { fixture.remove() }
        try fixture.clean()
        let app = open(fixture, expert: true)
        let commit = row(app, "Graph: assign lane colors from branch tips")
        XCTAssertTrue(commit.waitForExistence(timeout: 10))
        commit.rightClick()
        let item = app.menuItems["Split commit\u{2026}"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
        XCTAssertTrue(app.buttons["split-run"].waitForExistence(timeout: 10))
        attach(app, "j-split-light")
        app.buttons["split-run"].click()
        XCTAssertTrue(try eventually(20) { try fixture.git(["log", "-1", "--format=%s", "HEAD~2"]).output.trimmingCharacters(in: .whitespacesAndNewlines) == "Graph: assign lane colors from branch tips (part 2)" })
        XCTAssertEqual(try fixture.git(["log", "-1", "--format=%s", "HEAD~3"]).output.trimmingCharacters(in: .whitespacesAndNewlines), "Graph: assign lane colors from branch tips")
        setExpert(app, false)
        app.terminate()
    }

    @MainActor
    func testSparseCheckoutHidesAFolder() throws {
        let fixture = try RewriteFixture.copy("everyday")
        defer { fixture.remove() }
        try fixture.clean()
        let app = open(fixture, expert: true)
        menu(app, "Repository", "Sparse checkout\u{2026}")
        let docs = app.descendants(matching: .any)["sparse-Docs"]
        XCTAssertTrue(docs.waitForExistence(timeout: 10))
        attach(app, "j-sparse-light")
        docs.click()
        app.buttons["sparse-run"].click()
        XCTAssertTrue(eventually(20) { !FileManager.default.fileExists(atPath: fixture.root + "/Docs") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.root + "/Sources"))
        setExpert(app, false)
        app.terminate()
    }

    @MainActor
    func testCleanUpShowsAResult() throws {
        let fixture = try RewriteFixture.copy("everyday")
        defer { fixture.remove() }
        let app = open(fixture)
        menu(app, "Repository", "Maintenance", "Clean up")
        XCTAssertTrue(textContaining(app, "Cleaned up the repository").waitForExistence(timeout: 60))
        attach(app, "j-maintenance-light")
        app.terminate()
    }

    @MainActor
    func testFixupWithNothingStagedPrefillsChanges() throws {
        let fixture = try RewriteFixture.copy("everyday")
        defer { fixture.remove() }
        try fixture.clean()
        let app = open(fixture, expert: true)
        let commit = row(app, "Graph: keep the HEAD halo above merge rings")
        XCTAssertTrue(commit.waitForExistence(timeout: 10))
        commit.rightClick()
        let item = app.menuItems["Create fixup commit for this"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
        XCTAssertTrue(textContaining(app, "Fixup message ready in Changes").waitForExistence(timeout: 10))
        attach(app, "j-fixup-light")
        setExpert(app, false)
        app.terminate()
    }
}
