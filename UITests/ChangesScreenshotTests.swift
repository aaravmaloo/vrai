import XCTest

final class ChangesScreenshotTests: XCTestCase {
    enum Variant: String, CaseIterable {
        case light
        case dark
        case w700

        var appearance: String { self == .dark ? "dark" : "light" }
        var size: String { self == .w700 ? "700x800" : "1280x800" }
    }

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testEverydayChanges() throws {
        for variant in Variant.allCases {
            let app = ChangesFixtureCopy.launch(Sandbox.fixture("everyday"), appearance: variant.appearance, size: variant.size)
            ChangesFixtureCopy.openChanges(app)
            XCTAssertTrue(app.textFields["commit-summary"].waitForExistence(timeout: 10))
            if variant != .w700 {
                XCTAssertTrue(app.descendants(matching: .any)["changes-diff"].waitForExistence(timeout: 10))
            }
            Thread.sleep(forTimeInterval: 1.5)
            ChangesFixtureCopy.attach(self, app, name: "changes-everyday-\(variant.rawValue)")
            app.terminate()
        }
    }

    @MainActor
    func testEverydayChangesExpertSplitAndSelection() throws {
        let copy = try ChangesFixtureCopy.everyday()
        addTeardownBlock { copy.remove() }
        let app = ChangesFixtureCopy.launch(copy.repo, size: "1280x800")
        ChangesFixtureCopy.openChanges(app)
        let row = app.descendants(matching: .any)["change-row-unstaged-Sources/VraiGit/Graph/LaneLayout.swift"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        let gutter = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "gutter-", "Added line")).firstMatch
        XCTAssertTrue(gutter.waitForExistence(timeout: 10))
        gutter.click()
        Thread.sleep(forTimeInterval: 0.6)
        ChangesFixtureCopy.attach(self, app, name: "changes-everyday-partial")
        app.typeKey("e", modifierFlags: [.command, .option])
        Thread.sleep(forTimeInterval: 1.2)
        ChangesFixtureCopy.attach(self, app, name: "changes-everyday-expert")
        app.typeKey("e", modifierFlags: [.command, .option])
        app.terminate()
    }

    @MainActor
    func testChangesLayoutAtEverySize() throws {
        for appearance in ["light", "dark"] {
            let narrow = ChangesFixtureCopy.launch(Sandbox.fixture("everyday"), appearance: appearance, size: "700x800")
            ChangesFixtureCopy.openChanges(narrow)
            Thread.sleep(forTimeInterval: 1)
            ChangesFixtureCopy.attach(self, narrow, name: "changes-layout-w700-list-\(appearance)")
            let row = narrow.descendants(matching: .any)["change-row-staged-Sources/VraiUI/History/GraphCell.swift"]
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.click()
            let diff = narrow.descendants(matching: .any)["changes-diff"]
            ChangesFixtureCopy.expect(self, narrow, diff, "narrow-diff")
            diff.scroll(byDeltaX: 0, deltaY: -300)
            Thread.sleep(forTimeInterval: 1)
            ChangesFixtureCopy.attach(self, narrow, name: "changes-layout-w700-diff-\(appearance)")
            narrow.terminate()

            let short = ChangesFixtureCopy.launch(Sandbox.fixture("everyday"), appearance: appearance, size: "1280x500")
            ChangesFixtureCopy.openChanges(short)
            let shortDiff = short.descendants(matching: .any)["changes-diff"]
            XCTAssertTrue(shortDiff.waitForExistence(timeout: 10))
            shortDiff.scroll(byDeltaX: 0, deltaY: -300)
            Thread.sleep(forTimeInterval: 1)
            ChangesFixtureCopy.attach(self, short, name: "changes-layout-h500-\(appearance)")
            short.terminate()
        }
    }

    @MainActor
    func testHookFailureAtShortHeight() throws {
        let copy = try ChangesFixtureCopy.everyday()
        addTeardownBlock { copy.remove() }
        FileManager.default.createFile(atPath: copy.repo + "/.git/vrai-fail-pre-commit", contents: Data())
        let app = ChangesFixtureCopy.launch(copy.repo, size: "1280x500")
        ChangesFixtureCopy.openChanges(app)
        let summary = app.textFields["commit-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        ChangesFixtureCopy.type("Draw a halo behind HEAD", into: summary)
        app.buttons["commit-button"].click()
        ChangesFixtureCopy.expect(self, app, app.descendants(matching: .any)["commit-hook-failure"], timeout: 15, "short-hook-failure")
        Thread.sleep(forTimeInterval: 0.8)
        ChangesFixtureCopy.attach(self, app, name: "changes-layout-h500-hook")
        app.terminate()
    }

    @MainActor
    func testPathBarAtEveryWidth() throws {
        let copy = try ChangesFixtureCopy.everyday()
        addTeardownBlock { copy.remove() }
        let long = "Sources/VraiGit/Graph/LaneLayoutIncrementalPagingAcrossVeryLargeRepositories.swift"
        FileManager.default.createFile(atPath: copy.repo + "/" + long, contents: Data("struct Paging {}\n".utf8))
        let rows = [
            ("deep", "change-row-unstaged-Sources/VraiGit/Graph/LaneLayout.swift"),
            ("long", "change-row-untracked-" + long)
        ]
        for (width, size) in [("full", "1280x800"), ("w1000", "1000x800"), ("w700", "700x800")] {
            for appearance in ["light", "dark"] {
                let app = ChangesFixtureCopy.launch(copy.repo, appearance: appearance, size: size)
                ChangesFixtureCopy.openChanges(app)
                for (name, identifier) in rows {
                    let back = app.descendants(matching: .any)["changes-back"]
                    if width == "w700", back.exists, !app.descendants(matching: .any)[identifier].exists { back.click() }
                    let row = app.descendants(matching: .any)[identifier]
                    ChangesFixtureCopy.expect(self, app, row, "pathbar-row-\(name)")
                    row.click()
                    ChangesFixtureCopy.expect(self, app, app.descendants(matching: .any)["changes-diff"], "pathbar-diff-\(name)")
                    Thread.sleep(forTimeInterval: 0.8)
                    ChangesFixtureCopy.attach(self, app, name: "changes-pathbar-\(name)-\(width)-\(appearance)")
                }
                app.terminate()
            }
        }
    }
}
