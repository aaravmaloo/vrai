import XCTest

final class CoverageFlowTests: XCTestCase {
    static let lane = "Sources/VraiGit/Graph/LaneLayout.swift"
    static let cell = "Sources/VraiUI/History/GraphCell.swift"

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
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
    private func openConflicts(_ app: XCUIApplication) -> XCUIElement {
        let resolve = app.buttons["Resolve conflicts"]
        XCTAssertTrue(resolve.waitForExistence(timeout: 10))
        resolve.click()
        let pane = app.descendants(matching: .any)["conflicts-pane"]
        XCTAssertTrue(pane.waitForExistence(timeout: 10))
        return pane
    }

    @MainActor
    func testStartOverPutsTheConflictBack() throws {
        let fixture = try RewriteFixture.copy("conflict")
        defer { fixture.remove() }
        let app = fixture.launch()
        _ = openConflicts(app)
        let current = app.buttons["accept-current-1"]
        XCTAssertTrue(current.waitForExistence(timeout: 10))
        current.click()
        XCTAssertTrue(app.descendants(matching: .any)["resolved-1"].waitForExistence(timeout: 10))
        attach(app, "l-start-over-before")
        let actions = app.descendants(matching: .any)["File actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.click()
        let item = app.menuItems["Start over"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
        let confirm = app.windows.firstMatch.sheets.buttons.matching(NSPredicate(format: "label == %@", "Start over")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(app.buttons["accept-current-1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["resolved-1"].exists)
        XCTAssertTrue(try eventually { try fixture.git(["ls-files", "-u", "--", Self.lane]).output.split(separator: "\n").count == 3 })
        attach(app, "l-start-over-after")
        app.terminate()
    }

    @MainActor
    func testReplayedResolutionShowsANote() throws {
        for appearance in ["light", "dark"] {
            let fixture = try RewriteFixture.copy("conflict")
            try fixture.mustGit(["checkout", "--ours", "--", Self.lane, Self.cell])
            try fixture.mustGit(["add", "--", Self.lane, Self.cell])
            try fixture.mustGit(["-c", "core.hooksPath=/dev/null", "commit", "-q", "--no-edit"])
            try fixture.mustGit(["reset", "-q", "--hard", "HEAD~1"])
            _ = try fixture.git(["merge", "--no-edit", "refs/heads/mira/spike/metal-graph"])
            for (size, name) in [("1280x800", "default"), ("700x500", "small")] {
                let app = fixture.launch(appearance: appearance, size: size)
                _ = openConflicts(app)
                let note = app.descendants(matching: .any)["conflict-replayed"]
                XCTAssertTrue(note.waitForExistence(timeout: 10))
                XCTAssertTrue(app.buttons["mark-resolved"].isHittable)
                attach(app, "l-rerere-\(name)-\(appearance)")
                app.terminate()
            }
            fixture.remove()
        }
    }

    @MainActor
    func testPackLooseObjectsFromTheMaintenanceMenu() throws {
        let fixture = try RewriteFixture.copy("everyday")
        defer { fixture.remove() }
        let app = fixture.launch()
        XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 15))
        app.typeKey("e", modifierFlags: [.command, .option])
        app.menuBars.menuBarItems["Repository"].click()
        let maintenance = app.menuItems["Maintenance"]
        XCTAssertTrue(maintenance.waitForExistence(timeout: 5))
        maintenance.hover()
        let pack = app.menuItems["Pack loose objects"]
        XCTAssertTrue(pack.waitForExistence(timeout: 5))
        pack.click()
        let done = app.staticTexts["Packed loose objects"]
        XCTAssertTrue(done.waitForExistence(timeout: 30))
        XCTAssertTrue(try fixture.git(["count-objects", "-v"]).output.contains("packs: 1"))
        attach(app, "l-pack-loose")
        app.terminate()
    }
}
