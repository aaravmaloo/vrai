import XCTest

final class NarrowFlowTests: XCTestCase {
    var boxes: [SettingsSandbox] = []

    static let sizes: [(name: String, size: String)] = [
        ("w460", "460x800"),
        ("w700", "700x800"),
        ("w1000", "1000x700"),
        ("w1280", "1280x800"),
        ("h456", "1280x456"),
        ("w700h456", "700x456")
    ]

    static let sheetSizes: [(name: String, size: String)] = [
        ("w460", "460x800"),
        ("w700", "700x800"),
        ("w1000", "1000x700"),
        ("h456", "1280x456")
    ]

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        for box in boxes { box.remove() }
        boxes = []
    }

    @MainActor
    func testHistoryAndChangesAtEverySize() throws {
        let box = try make(["everyday"])
        for (name, size) in Self.sizes {
            for appearance in StatesFlowTests.appearances {
                let tag = "\(name)-\(appearance)"
                let app = StateLab.launch(box, open: box.repository("everyday"), appearance: appearance, size: size)
                XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 15), tag)
                let commit = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Graph: keep the HEAD halo")).firstMatch
                XCTAssertTrue(commit.waitForExistence(timeout: 10), tag)
                Thread.sleep(forTimeInterval: 0.8)
                NarrowCheck.belowToolbar(app, app.descendants(matching: .any)["commits"], tag + " commits")
                StateLab.attach(self, app, "narrow-history-list-\(tag)")
                commit.click()
                Thread.sleep(forTimeInterval: 1.2)
                StateLab.attach(self, app, "narrow-history-detail-\(tag)")
                if name == "w1280" {
                    let inspectorTag = app.buttons["inspector-tag"]
                    XCTAssertTrue(inspectorTag.waitForExistence(timeout: 5), tag + " inspector tag")
                    inspectorTag.click()
                    XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 10), tag + " inspector tag")
                    app.typeKey(.escape, modifierFlags: [])
                    _ = PlacesFixture.eventually(5) { !app.sheets.firstMatch.exists }
                }

                StateLab.menu(app, "View", "Changes")
                let row = app.descendants(matching: .any)["change-row-unstaged-Sources/VraiGit/Graph/LaneLayout.swift"]
                XCTAssertTrue(row.waitForExistence(timeout: 10), tag)
                NarrowCheck.belowToolbar(app, app.descendants(matching: .any)["changes-title"], tag + " changes title")
                StateLab.attach(self, app, "narrow-changes-list-\(tag)")
                row.click()
                XCTAssertTrue(app.descendants(matching: .any)["changes-diff"].waitForExistence(timeout: 10), tag)
                Thread.sleep(forTimeInterval: 1)
                StateLab.attach(self, app, "narrow-changes-diff-\(tag)")
                app.terminate()
            }
        }
    }

    @MainActor
    func testPlacesAtEverySize() throws {
        let box = try make(["everyday"])
        for (name, size) in Self.sizes {
            for appearance in StatesFlowTests.appearances {
                let tag = "\(name)-\(appearance)"
                let app = StateLab.launch(box, open: box.repository("everyday"), appearance: appearance, size: size, expert: true)
                XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 15), tag)

                StateLab.menu(app, "View", "Stashes")
                XCTAssertTrue(StateLab.text(app, "3 stashes").waitForExistence(timeout: 10), tag)
                Thread.sleep(forTimeInterval: 1)
                StateLab.attach(self, app, "narrow-stashes-\(tag)")

                StateLab.menu(app, "View", "Reflog")
                XCTAssertTrue(app.descendants(matching: .any)["reflog-view"].waitForExistence(timeout: 10), tag)
                Thread.sleep(forTimeInterval: 1)
                StateLab.attach(self, app, "narrow-reflog-\(tag)")

                StateLab.palette(app, "Refs")
                XCTAssertTrue(app.descendants(matching: .any)["refs-view"].waitForExistence(timeout: 10), tag)
                NarrowCheck.belowToolbar(app, app.buttons["refs-console"], tag + " refs header")
                Thread.sleep(forTimeInterval: 1)
                StateLab.attach(self, app, "narrow-refs-\(tag)")

                StateLab.palette(app, "Worktrees")
                XCTAssertTrue(app.descendants(matching: .any)["worktrees-view"].waitForExistence(timeout: 10), tag)
                Thread.sleep(forTimeInterval: 1)
                StateLab.attach(self, app, "narrow-worktrees-\(tag)")

                StateLab.palette(app, "Submodules")
                XCTAssertTrue(app.descendants(matching: .any)["submodules-view"].waitForExistence(timeout: 10), tag)
                Thread.sleep(forTimeInterval: 1)
                StateLab.attach(self, app, "narrow-submodules-\(tag)")

                NarrowCheck.fileMenu(app, "Blame")
                XCTAssertTrue(app.descendants(matching: .any)["blame-view"].waitForExistence(timeout: 10), tag)
                NarrowCheck.belowToolbar(app, app.descendants(matching: .any)["blame-back"], tag + " blame bar")
                Thread.sleep(forTimeInterval: 1.2)
                StateLab.attach(self, app, "narrow-blame-\(tag)")

                NarrowCheck.fileMenu(app, "File history")
                XCTAssertTrue(app.descendants(matching: .any)["file-history-view"].waitForExistence(timeout: 10), tag)
                Thread.sleep(forTimeInterval: 1.2)
                StateLab.attach(self, app, "narrow-file-history-\(tag)")
                app.terminate()
            }
        }
    }

    @MainActor
    func testOverlaysAndConflictsAtEverySize() throws {
        let box = try make(["everyday", "conflict"])
        for (name, size) in Self.sizes {
            for appearance in StatesFlowTests.appearances {
                let tag = "\(name)-\(appearance)"
                let app = StateLab.launch(box, open: box.repository("everyday"), appearance: appearance, size: size)
                XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 15), tag)
                StateLab.menu(app, "Window", "Console")
                XCTAssertTrue(app.descendants(matching: .any)["console"].waitForExistence(timeout: 10), tag)
                Thread.sleep(forTimeInterval: 1)
                StateLab.attach(self, app, "narrow-console-\(tag)")
                StateLab.menu(app, "Window", "Console")

                StateLab.menu(app, "Edit", "Command palette")
                let field = app.descendants(matching: .any)["palette-field"]
                XCTAssertTrue(field.waitForExistence(timeout: 10), tag)
                field.typeText("rebase")
                Thread.sleep(forTimeInterval: 1)
                StateLab.attach(self, app, "narrow-palette-\(tag)")
                app.typeKey(.escape, modifierFlags: [])
                app.typeKey(.escape, modifierFlags: [])
                app.terminate()

                let conflict = StateLab.launch(box, open: box.repository("conflict"), appearance: appearance, size: size)
                XCTAssertTrue(conflict.descendants(matching: .any)["commits"].waitForExistence(timeout: 15), tag)
                Thread.sleep(forTimeInterval: 1)
                StateLab.attach(self, conflict, "narrow-conflict-banner-\(tag)")
                StateLab.menu(conflict, "View", "Changes")
                let row = conflict.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "change-row-conflicts-")).firstMatch
                XCTAssertTrue(row.waitForExistence(timeout: 10), tag)
                StateLab.attach(self, conflict, "narrow-conflict-list-\(tag)")
                row.click()
                Thread.sleep(forTimeInterval: 1.5)
                StateLab.attach(self, conflict, "narrow-conflict-view-\(tag)")
                conflict.terminate()
            }
        }
    }

    @MainActor
    func testSheetsAtEverySize() throws {
        let box = try make(["everyday"])
        let sheets: [(menu: String, item: String, name: String)] = [
            ("Branch", "New branch\u{2026}", "branch"),
            ("Repository", "Fetch, pull and push with options\u{2026}", "sync"),
            ("Repository", "Stash changes\u{2026}", "stash"),
            ("Branch", "Interactive rebase\u{2026}", "interactive"),
            ("Commit", "Tag selected\u{2026}", "tag"),
            ("Repository", "Repository info\u{2026}", "info"),
            ("File", "Clone\u{2026}", "clone")
        ]
        for (name, size) in Self.sheetSizes {
            for appearance in StatesFlowTests.appearances {
                let tag = "\(name)-\(appearance)"
                let app = StateLab.launch(box, open: box.repository("everyday"), appearance: appearance, size: size)
                XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 15), tag)
                let commit = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Graph: keep the HEAD halo")).firstMatch
                if commit.waitForExistence(timeout: 10) { commit.click() }
                if app.buttons["history-back"].exists { app.buttons["history-back"].click() }
                for sheet in sheets {
                    let bar = app.menuBars.menuBarItems[sheet.menu]
                    bar.click()
                    let entry = bar.menuItems[sheet.item]
                    guard entry.waitForExistence(timeout: 5), entry.isEnabled else {
                        app.typeKey(.escape, modifierFlags: [])
                        XCTFail("\(tag): \(sheet.item) is missing or disabled")
                        continue
                    }
                    entry.click()
                    let shown = app.sheets.firstMatch
                    XCTAssertTrue(shown.waitForExistence(timeout: 10), "\(tag): \(sheet.name) didn't open")
                    Thread.sleep(forTimeInterval: 1)
                    NarrowCheck.sheetFits(app, shown, "\(tag) \(sheet.name)")
                    StateLab.attach(self, shown, "narrow-sheet-\(sheet.name)-\(tag)")
                    let cancel = shown.buttons["Cancel"].firstMatch
                    if cancel.exists, cancel.isHittable { cancel.click() } else { app.typeKey(.escape, modifierFlags: []) }
                    _ = PlacesFixture.eventually(5) { !app.sheets.firstMatch.exists }
                    if app.sheets.firstMatch.exists { app.typeKey(.escape, modifierFlags: []) }
                }
                app.terminate()
            }
        }
    }

    func make(_ scenarios: [String]) throws -> SettingsSandbox {
        let box = try SettingsSandbox.make(scenarios)
        boxes.append(box)
        return box
    }
}

enum NarrowCheck {
    @MainActor
    static func belowToolbar(_ app: XCUIApplication, _ element: XCUIElement, _ what: String) {
        guard element.exists else { return }
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(element.frame.minY, window.minY + 40, "\(what) slid under the toolbar")
    }

    @MainActor
    static func sheetFits(_ app: XCUIApplication, _ sheet: XCUIElement, _ what: String) {
        let screen = app.windows.firstMatch.frame.union(sheet.frame)
        XCTAssertLessThanOrEqual(sheet.frame.maxY, screen.maxY + 1, "\(what) runs past the window")
        let buttons = sheet.buttons.matching(NSPredicate(format: "label == %@", "Cancel"))
        if buttons.count > 0 {
            XCTAssertTrue(buttons.firstMatch.isHittable, "\(what): Cancel can't be reached")
        }
    }

    @MainActor
    static func fileMenu(_ app: XCUIApplication, _ item: String) {
        StateLab.menu(app, "View", "Changes")
        let row = app.descendants(matching: .any)["change-row-unstaged-Sources/VraiGit/Graph/LaneLayout.swift"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.rightClick()
        let menu = app.menuItems[item]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.click()
    }
}
