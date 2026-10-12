import XCTest

final class A11yMotionContrastTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testIncreaseContrastStrengthensHairlinesAndFocus() throws {
        for appearance in AuditLab.appearances {
            for contrast in [false, true] {
                let lab = try AuditLab.make(["everyday"])
                defer { lab.remove() }
                let suffix = (contrast ? "increased-" : "standard-") + appearance
                let app = lab.launch(appearance: appearance, extra: contrast ? ["-VraiIncreaseContrast", "YES"] : [])
                let commit = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Graph: keep the HEAD halo above merge rings,")).firstMatch
                XCTAssertTrue(commit.waitForExistence(timeout: 10))
                commit.click()
                Thread.sleep(forTimeInterval: 1)
                AuditLab.attach(self, app, "contrast-history-" + suffix)

                app.typeKey("2", modifierFlags: .command)
                let change = app.descendants(matching: .any)["change-row-unstaged-Sources/VraiGit/Graph/LaneLayout.swift"]
                XCTAssertTrue(change.waitForExistence(timeout: 10))
                change.click()
                let summary = app.textFields["commit-summary"]
                XCTAssertTrue(summary.waitForExistence(timeout: 5))
                summary.click()
                Thread.sleep(forTimeInterval: 0.8)
                AuditLab.attach(self, app, "contrast-changes-" + suffix)

                app.menuBars.menuBarItems["Branch"].click()
                app.menuBars.menuItems["New branch\u{2026}"].firstMatch.click()
                XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 10))
                Thread.sleep(forTimeInterval: 0.8)
                AuditLab.attach(self, app, "contrast-sheet-" + suffix)
                AuditLab.dismissSheet(app)
                app.terminate()
            }
        }
    }

    @MainActor
    func testReduceMotionFadesInsteadOfSliding() throws {
        for reduce in [false, true] {
            let lab = try AuditLab.make(["everyday"])
            defer { lab.remove() }
            let suffix = reduce ? "reduced" : "standard"
            let app = lab.launch(appearance: "light", extra: reduce ? ["-VraiReduceMotion", "YES"] : [])
            AuditLab.focus(app)
            let window = app.windows.firstMatch
            app.typeKey("j", modifierFlags: .command)
            for frame in 1...3 {
                let shot = XCTAttachment(screenshot: window.screenshot())
                shot.name = "motion-console-\(suffix)-\(frame)"
                shot.lifetime = .keepAlways
                add(shot)
            }
            XCTAssertTrue(app.descendants(matching: .any)["console"].waitForExistence(timeout: 5))
            app.typeKey("j", modifierFlags: .command)
            app.typeKey("k", modifierFlags: .command)
            for frame in 1...3 {
                let shot = XCTAttachment(screenshot: window.screenshot())
                shot.name = "motion-palette-\(suffix)-\(frame)"
                shot.lifetime = .keepAlways
                add(shot)
            }
            XCTAssertTrue(app.textFields["palette-field"].waitForExistence(timeout: 5))
            app.typeKey(.escape, modifierFlags: [])
            app.terminate()
        }
    }
}
