import XCTest

final class StatesFlowTests: XCTestCase {
    var boxes: [SettingsSandbox] = []

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        for box in boxes { box.remove() }
        boxes = []
    }

    static let appearances = ["light", "dark"]

    @MainActor
    func testNewRepositoryWithFiles() throws {
        let box = try make(["empty"])
        for appearance in Self.appearances {
            let app = StateLab.launch(box, open: box.repository("empty"), appearance: appearance)
            XCTAssertTrue(StateLab.text(app, "Uncommitted changes").waitForExistence(timeout: 15))
            Thread.sleep(forTimeInterval: 1)
            StateLab.attach(self, app, "states-history-first-files-\(appearance)")
            StateLab.menu(app, "View", "Changes")
            XCTAssertTrue(app.textFields["commit-summary"].waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 0.8)
            StateLab.attach(self, app, "states-changes-first-commit-\(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testNewRepositoryStates() throws {
        let box = try make([])
        let blank = box.root + "/fixtures/blank/notes"
        try FileManager.default.createDirectory(atPath: blank, withIntermediateDirectories: true)
        XCTAssertEqual(try box.git(["init", "--quiet", "--initial-branch=main", blank]).status, 0)
        for appearance in Self.appearances {
            let app = StateLab.launch(box, open: blank, appearance: appearance, expert: true)
            XCTAssertTrue(StateLab.text(app, "No commits yet").waitForExistence(timeout: 15))
            StateLab.attach(self, app, "states-history-empty-\(appearance)")

            StateLab.menu(app, "View", "Changes")
            XCTAssertTrue(StateLab.text(app, "No changes to commit").waitForExistence(timeout: 10))
            StateLab.attach(self, app, "states-changes-empty-new-\(appearance)")

            StateLab.menu(app, "View", "Stashes")
            XCTAssertTrue(StateLab.text(app, "No stashes").waitForExistence(timeout: 10))
            StateLab.attach(self, app, "states-stashes-empty-\(appearance)")

            StateLab.palette(app, "Submodules")
            XCTAssertTrue(StateLab.text(app, "No submodules").waitForExistence(timeout: 10))
            StateLab.attach(self, app, "states-submodules-empty-\(appearance)")

            StateLab.palette(app, "Worktrees")
            Thread.sleep(forTimeInterval: 1)
            StateLab.attach(self, app, "states-worktrees-main-only-\(appearance)")

            StateLab.menu(app, "View", "Reflog")
            XCTAssertTrue(app.descendants(matching: .any)["reflog-view"].waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 1)
            StateLab.attach(self, app, "states-reflog-empty-\(appearance)")

            StateLab.palette(app, "Refs")
            XCTAssertTrue(app.descendants(matching: .any)["refs-view"].waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 1)
            StateLab.attach(self, app, "states-refs-empty-\(appearance)")

            StateLab.menu(app, "View", "History")
            StateLab.menu(app, "Window", "Console")
            let console = app.descendants(matching: .any)["console"]
            XCTAssertTrue(console.waitForExistence(timeout: 10))
            console.buttons["Clear"].firstMatch.click()
            XCTAssertTrue(StateLab.text(app, "No commands yet. Every git command Vrai runs shows up here, with its output.").waitForExistence(timeout: 10))
            StateLab.attach(self, app, "states-console-empty-\(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testCleanRepositoryStates() throws {
        let box = try make(["welcome"])
        let repo = box.root + "/fixtures/welcome/swift-collections"
        XCTAssertEqual(try box.git(["status", "--porcelain"], in: repo).output, "")
        for appearance in Self.appearances {
            let app = StateLab.launch(box, open: repo, appearance: appearance)
            XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 15))
            Thread.sleep(forTimeInterval: 1)
            StateLab.attach(self, app, "states-history-clean-\(appearance)")

            StateLab.menu(app, "View", "Changes")
            XCTAssertTrue(StateLab.text(app, "No changes to commit").waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["Show history"].exists)
            XCTAssertTrue(app.buttons["Amend last commit"].exists)
            StateLab.attach(self, app, "states-changes-empty-\(appearance)")

            StateLab.menu(app, "View", "Stashes")
            XCTAssertTrue(StateLab.text(app, "No stashes").waitForExistence(timeout: 10))
            StateLab.attach(self, app, "states-stashes-clean-\(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testInspectorAndDetailWithNothingSelected() throws {
        let box = try make(["everyday"])
        for appearance in Self.appearances {
            let app = StateLab.launch(box, open: box.repository("everyday"), appearance: appearance)
            let wip = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Uncommitted changes, ")).firstMatch
            XCTAssertTrue(wip.waitForExistence(timeout: 15))
            wip.click()
            Thread.sleep(forTimeInterval: 1)
            StateLab.attach(self, app, "states-inspector-wip-\(appearance)")

            StateLab.menu(app, "View", "Changes")
            XCTAssertTrue(app.textFields["commit-summary"].waitForExistence(timeout: 10))
            StateLab.attach(self, app, "states-changes-selected-\(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testLoadingALargeRepository() throws {
        let path = Sandbox.root + "/fixtures/large/monorepo"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path), "build the large fixture with Scripts/make-fixtures.sh large")
        defer { Sandbox.forgetRecent(path) }
        for appearance in Self.appearances {
            let app = XCUIApplication()
            app.launchArguments = ["-VraiSandbox", Sandbox.root, "-VraiOpen", path, "-VraiAppearance", appearance, "-VraiNow", Sandbox.now, "-VraiWindowSize", "1280x800", "-VraiCapture", "YES", "-VraiOpenDelay", "6000", "-ApplePersistenceIgnoreState", "YES"]
            app.launch()
            let loading = app.descendants(matching: .any)["loading-view"]
            XCTAssertTrue(loading.waitForExistence(timeout: 10))
            XCTAssertTrue(PlacesFixture.eventually(10) { loading.label.contains("branches") })
            StateLab.attach(self, app, "states-loading-\(appearance)")
            XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 60))
            Thread.sleep(forTimeInterval: 1)
            StateLab.attach(self, app, "states-loaded-large-\(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testPaletteWithNoResults() throws {
        let box = try make(["everyday"])
        for appearance in Self.appearances {
            let app = StateLab.launch(box, open: box.repository("everyday"), appearance: appearance)
            XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 15))
            StateLab.menu(app, "Edit", "Command palette")
            let field = app.descendants(matching: .any)["palette-field"]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            field.typeText("zqxjv")
            let empty = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", "No actions match", "No actions match")).firstMatch
            XCTAssertTrue(empty.waitForExistence(timeout: 10))
            StateLab.attach(self, app, "states-palette-no-results-\(appearance)")
            app.typeKey(.escape, modifierFlags: [])
            app.typeKey(.escape, modifierFlags: [])
            app.terminate()
        }
    }

    @MainActor
    func testWelcomeWithNoRecents() throws {
        let box = try make([])
        for appearance in Self.appearances {
            let app = StateLab.launch(box, open: nil, appearance: appearance)
            XCTAssertTrue(StateLab.text(app, "No recent repositories").waitForExistence(timeout: 15))
            StateLab.attach(self, app, "states-welcome-no-recents-\(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testAccountsWithNoAccounts() throws {
        let box = try make(["everyday"])
        for appearance in Self.appearances {
            let app = StateLab.launch(box, open: box.repository("everyday"), appearance: appearance, extra: ["-VraiSettings", "accounts"])
            XCTAssertTrue(StateLab.text(app, "No accounts yet").waitForExistence(timeout: 15))
            let settings = app.windows.containing(NSPredicate(format: "identifier BEGINSWITH %@", "settings.pane.")).firstMatch
            StateLab.attach(self, settings.exists ? settings : app.windows.firstMatch, "states-accounts-empty-\(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testRepositoryThatDisappeared() throws {
        let box = try make(["everyday"])
        let repo = box.repository("everyday")
        let moved = repo + "-moved"
        for appearance in Self.appearances {
            let app = StateLab.launch(box, open: repo, appearance: appearance)
            XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 15))
            try FileManager.default.moveItem(atPath: repo, toPath: moved)
            let gone = app.descendants(matching: .any)["repository-gone"]
            XCTAssertTrue(gone.waitForExistence(timeout: 15))
            XCTAssertTrue(StateLab.text(app, "vrai isn't where it used to be").exists)
            StateLab.attach(self, app, "states-repository-gone-\(appearance)")
            try FileManager.default.moveItem(atPath: moved, toPath: repo)
            app.buttons["repository-gone-retry"].click()
            XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 15))
            app.terminate()

            let missing = StateLab.launch(box, open: box.root + "/fixtures/nowhere/vrai", appearance: appearance)
            XCTAssertTrue(missing.descendants(matching: .any)["repository-gone"].waitForExistence(timeout: 15))
            StateLab.attach(self, missing, "states-repository-missing-at-open-\(appearance)")
            missing.terminate()
        }
    }

    @MainActor
    func testWelcomeWithAMissingRecent() throws {
        let box = try make(["empty"])
        let gone = box.root + "/fixtures/gone/notes"
        let recents = """
        {"repositories":[{"lastOpened":1791718800,"name":"notes","path":"\(gone)"},{"lastOpened":1791626400,"name":"pocket-notes","path":"\(box.repository("empty"))"}],"version":1}
        """
        try recents.write(toFile: box.root + "/recents.json", atomically: true, encoding: .utf8)
        for appearance in Self.appearances {
            let app = StateLab.launch(box, open: nil, appearance: appearance)
            let row = app.descendants(matching: .any)["recent-notes"]
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            Thread.sleep(forTimeInterval: 1.5)
            StateLab.attach(self, app, "states-welcome-missing-recent-\(appearance)")
            row.doubleClick()
            let locate = app.buttons["Locate\u{2026}"]
            XCTAssertTrue(locate.waitForExistence(timeout: 10))
            StateLab.attach(self, app, "states-welcome-missing-alert-\(appearance)")
            app.typeKey(.escape, modifierFlags: [])
            app.terminate()
        }
    }

    @MainActor
    func testGitMissingOrTooOld() throws {
        let box = try make([])
        for (problem, title) in [("missing", "Vrai needs git"), ("old", "Git 2.39.5 is too old for Vrai")] {
            for appearance in Self.appearances {
                let app = StateLab.launch(box, open: nil, appearance: appearance, extra: ["-VraiGitProblem", problem])
                XCTAssertTrue(StateLab.text(app, title).waitForExistence(timeout: 15))
                XCTAssertTrue(app.buttons["onboarding-check"].exists)
                StateLab.attach(self, app, "states-git-\(problem)-\(appearance)")
                app.terminate()
            }
        }
    }

    @MainActor
    func testBinaryAndLargeDiffs() throws {
        let box = try make(["edge", "everyday"])
        let large = box.repository("everyday") + "/Generated.txt"
        try (1...25_000).map { "generated line \($0)" }.joined(separator: "\n").appending("\n").write(toFile: large, atomically: true, encoding: .utf8)
        for appearance in Self.appearances {
            let edge = StateLab.launch(box, open: box.root + "/fixtures/edge/edge", appearance: appearance)
            StateLab.menu(edge, "View", "Changes")
            let image = edge.descendants(matching: .any)["change-row-unstaged-image.png"]
            XCTAssertTrue(image.waitForExistence(timeout: 15))
            image.click()
            XCTAssertTrue(StateLab.text(edge, "Binary file, not shown.").waitForExistence(timeout: 10))
            StateLab.attach(self, edge, "states-diff-binary-\(appearance)")
            edge.terminate()

            let app = StateLab.launch(box, open: box.repository("everyday"), appearance: appearance)
            StateLab.menu(app, "View", "Changes")
            let row = app.descendants(matching: .any)["change-row-unstaged-Generated.txt"]
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            row.click()
            let note = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "so Vrai shows it as plain text", "so Vrai shows it as plain text")).firstMatch
            let shown = note.waitForExistence(timeout: 15)
            Thread.sleep(forTimeInterval: 1)
            StateLab.attach(self, app, "states-diff-large-\(appearance)")
            XCTAssertTrue(shown)
            app.terminate()
        }
    }

    @MainActor
    func testBlameAndFileHistoryForANewFile() throws {
        let box = try make(["edge"])
        for appearance in Self.appearances {
            let app = StateLab.launch(box, open: box.root + "/fixtures/edge/edge", appearance: appearance)
            StateLab.menu(app, "View", "Changes")
            let row = app.descendants(matching: .any)["change-row-staged-staged new.txt"]
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            row.rightClick()
            app.menuItems["File history"].click()
            XCTAssertTrue(app.descendants(matching: .any)["file-history-view"].waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 1.5)
            StateLab.attach(self, app, "states-file-history-new-file-\(appearance)")

            StateLab.menu(app, "View", "Changes")
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.rightClick()
            app.menuItems["Blame"].click()
            XCTAssertTrue(app.descendants(matching: .any)["blame-view"].waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 1.5)
            StateLab.attach(self, app, "states-blame-new-file-\(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testConflictedRepository() throws {
        let box = try make(["edge"])
        for appearance in Self.appearances {
            let app = StateLab.launch(box, open: box.root + "/fixtures/edge/edge", appearance: appearance)
            StateLab.menu(app, "View", "Changes")
            let row = app.descendants(matching: .any)["change-row-conflicts-conflict.txt"]
            if row.waitForExistence(timeout: 15) { row.click() }
            Thread.sleep(forTimeInterval: 1.5)
            StateLab.attach(self, app, "states-conflicts-\(appearance)")
            app.terminate()
        }
    }

    func make(_ scenarios: [String]) throws -> SettingsSandbox {
        let box = try SettingsSandbox.make(scenarios)
        boxes.append(box)
        return box
    }
}

enum StateLab {
    @MainActor
    static func launch(_ box: SettingsSandbox, open: String?, appearance: String, size: String = "1280x800", expert: Bool = false, extra: [String] = []) -> XCUIApplication {
        let defaults = UserDefaults(suiteName: box.root + "/com.aaravmaloo.vrai.sandbox")
        defaults?.set(expert, forKey: "expert")
        defaults?.set(false, forKey: "backgroundFetch")
        defaults?.synchronize()
        let app = XCUIApplication()
        var arguments = ["-VraiSandbox", box.root, "-VraiAppearance", appearance, "-VraiNow", Sandbox.now, "-VraiWindowSize", size, "-VraiCapture", "YES", "-ApplePersistenceIgnoreState", "YES"]
        if let open { arguments += ["-VraiOpen", open] }
        app.launchArguments = arguments + extra
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        app.activate()
        return app
    }

    @MainActor
    static func menu(_ app: XCUIApplication, _ title: String, _ item: String) {
        let bar = app.menuBars.menuBarItems[title]
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        bar.click()
        let entry = bar.menuItems[item]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "\(title) has no \(item)")
        entry.click()
        Thread.sleep(forTimeInterval: 0.5)
    }

    @MainActor
    static func palette(_ app: XCUIApplication, _ action: String) {
        menu(app, "Edit", "Command palette")
        let field = app.descendants(matching: .any)["palette-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText(action)
        Thread.sleep(forTimeInterval: 0.6)
        app.typeKey(.return, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.8)
    }

    @MainActor
    static func text(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR value == %@", label, label)).firstMatch
    }

    @MainActor
    static func attach(_ test: XCTestCase, _ app: XCUIApplication, _ name: String) {
        attach(test, app.windows.firstMatch, name)
    }

    @MainActor
    static func attach(_ test: XCTestCase, _ window: XCUIElement, _ name: String) {
        let shot = XCTAttachment(screenshot: window.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        test.add(shot)
    }
}
