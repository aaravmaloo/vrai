import XCTest

final class A11yKeyboardTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCommitLoopWithTheKeyboardOnly() throws {
        let fixture = try RewriteFixture.copy("everyday")
        defer { fixture.remove() }
        let before = try fixture.git(["rev-parse", "HEAD"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = fixture.launch()
        XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1)
        AuditLab.attach(self, app, "keyboard-1-history")

        app.typeKey("2", modifierFlags: .command)
        let list = app.descendants(matching: .any)["changes-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10), "Command-2 did not show Changes")
        Thread.sleep(forTimeInterval: 0.8)
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.upArrow, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.6)
        let picked = list.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'change-row-' AND selected == true")).firstMatch
        XCTAssertTrue(picked.waitForExistence(timeout: 5), "the arrow keys did not select a change")
        let path = String(picked.identifier.split(separator: "-", maxSplits: 3).last ?? "")
        AuditLab.attach(self, app, "keyboard-2-changes-selected")

        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(eventually { ((try? fixture.git(["diff", "--cached", "--name-only"]).output) ?? "").contains(path) }, "Space did not stage \(path)")
        Thread.sleep(forTimeInterval: 0.6)
        AuditLab.attach(self, app, "keyboard-3-staged")

        app.typeKey(.return, modifierFlags: .command)
        let summary = app.textFields["commit-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.6)
        app.typeText("Commit from the keyboard")
        XCTAssertTrue(eventually(5) { (summary.value as? String) == "Commit from the keyboard" }, "Command-Return did not move focus to the commit summary")
        AuditLab.attach(self, app, "keyboard-4-message")

        app.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(eventually(15) { ((try? fixture.git(["log", "-1", "--format=%s"]).output) ?? "").hasPrefix("Commit from the keyboard") }, "Command-Return did not commit")
        let after = try fixture.git(["rev-parse", "HEAD"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertNotEqual(before, after)
        let files = try fixture.git(["show", "--name-only", "--format=", "HEAD"]).output
        XCTAssertTrue(files.contains(path), files)
        Thread.sleep(forTimeInterval: 0.8)
        AuditLab.attach(self, app, "keyboard-5-committed")
        app.terminate()
    }

    @MainActor
    func testStageALineWithTheKeyboard() throws {
        let fixture = try RewriteFixture.copy("everyday")
        defer { fixture.remove() }
        let app = fixture.launch()
        XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1)
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["changes-list"].waitForExistence(timeout: 10), "Command-2 did not show Changes")
        Thread.sleep(forTimeInterval: 0.8)
        let row = app.descendants(matching: .any)["change-row-unstaged-Sources/VraiGit/Graph/LaneLayout.swift"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        var steps = 0
        while !row.isSelected, steps < 12 {
            app.typeKey(.downArrow, modifierFlags: [])
            steps += 1
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(row.isSelected, "the arrow keys did not reach LaneLayout.swift")
        let before = try fixture.git(["diff", "--cached", "--", "Sources/VraiGit/Graph/LaneLayout.swift"]).output
        app.typeKey(.rightArrow, modifierFlags: [])
        let selected = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'gutter-' AND selected == true")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 5), "the right arrow did not move into the diff and pick a line")
        app.typeKey(.downArrow, modifierFlags: .shift)
        Thread.sleep(forTimeInterval: 0.4)
        AuditLab.attach(self, app, "keyboard-lines-selected")
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(eventually { ((try? fixture.git(["diff", "--cached", "--", "Sources/VraiGit/Graph/LaneLayout.swift"]).output) ?? before) != before }, "Space did not stage the selected lines")
        Thread.sleep(forTimeInterval: 0.6)
        AuditLab.attach(self, app, "keyboard-lines-staged")
        app.terminate()
    }

    private func eventually(_ timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }
}
