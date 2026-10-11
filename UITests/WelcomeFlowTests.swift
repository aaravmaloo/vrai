import XCTest

final class WelcomeFlowTests: XCTestCase {
    struct Lab {
        let folder: String

        static func make() throws -> Lab {
            let folder = Sandbox.root + "/tests/" + UUID().uuidString
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(atPath: Sandbox.root + "/fixtures/everyday/remotes", toPath: folder + "/remotes")
            return Lab(folder: folder)
        }

        var origin: String { "file://" + folder + "/remotes/origin.git" }

        func remove(_ opened: [String]) {
            try? FileManager.default.removeItem(atPath: folder)
            for path in opened {
                Sandbox.forgetRecent(path)
                Sandbox.forgetRecent("/private" + path)
            }
        }
    }

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(appearance: String = "light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-VraiSandbox", Sandbox.root, "-VraiAppearance", appearance, "-VraiNow", Sandbox.now, "-VraiCapture", "YES", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.activate()
        XCTAssertTrue(app.buttons["welcome-clone"].waitForExistence(timeout: 10))
        return app
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
    private func replace(_ field: XCUIElement, with text: String) {
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
    }

    @MainActor
    func testWelcomeWindowLight() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["Open a repository\u{2026}"].exists)
        XCTAssertTrue(app.buttons["New repository\u{2026}"].exists)
        XCTAssertTrue(app.staticTexts["Recent"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Show this window when no repository is open"].exists)
        attach(app, "j-welcome-light")
        app.terminate()
    }

    @MainActor
    func testWelcomeWindowDark() throws {
        let app = launch(appearance: "dark")
        attach(app, "j-welcome-dark")
        app.terminate()
    }

    @MainActor
    func testCloneFromWelcomeShowsProgressAndOpensTheRepository() throws {
        let lab = try Lab.make()
        let target = lab.folder + "/clones/vrai"
        defer { lab.remove([target]) }
        let app = launch()
        app.buttons["welcome-clone"].click()
        let url = app.textFields["URL"]
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        url.click()
        url.typeText(lab.origin)
        replace(app.textFields["Where"], with: target)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "(default)", "(default)")).firstMatch.waitForExistence(timeout: 10))
        attach(app, "j-clone-sheet-light")
        app.buttons["clone-run"].click()
        let progress = app.descendants(matching: .any)["clone-progress"]
        if progress.waitForExistence(timeout: 5) {
            attach(app, "j-clone-progress-light")
        } else {
            XCTContext.runActivity(named: "The local clone finished before the progress view could be captured") { _ in }
        }
        XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 60))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target + "/.git"))
        let submodules = try Sandbox.git(["submodule", "status", "--recursive"], in: target)
        XCTAssertEqual(submodules.status, 0, submodules.output)
        XCTAssertFalse(submodules.output.contains("\n-"), submodules.output)
        XCTAssertTrue(eventually(10) { !app.buttons["welcome-clone"].exists })
        attach(app, "j-clone-opened-light")
        app.terminate()
    }

    @MainActor
    func testCloneSheetDark() throws {
        let app = launch(appearance: "dark")
        app.buttons["welcome-clone"].click()
        XCTAssertTrue(app.textFields["URL"].waitForExistence(timeout: 5))
        attach(app, "j-clone-sheet-dark")
        app.typeKey(.escape, modifierFlags: [])
        app.terminate()
    }

    @MainActor
    func testNewRepositoryFromWelcome() throws {
        let lab = try Lab.make()
        let name = "pocket-" + String(UUID().uuidString.prefix(6)).lowercased()
        let target = lab.folder + "/" + name
        defer { lab.remove([target]) }
        let app = launch()
        app.buttons["welcome-new"].click()
        let field = app.textFields["Name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText(name)
        replace(app.textFields["In"], with: lab.folder)
        attach(app, "j-init-sheet-light")
        app.buttons["init-run"].click()
        XCTAssertTrue(eventually(15) { FileManager.default.fileExists(atPath: target + "/.git/HEAD") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: target + "/.gitignore"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target + "/README.md"))
        XCTAssertTrue(eventually(15) { !app.buttons["welcome-clone"].exists })
        attach(app, "j-init-opened-light")
        app.terminate()
    }

    @MainActor
    func testOpenSheetFromWelcome() throws {
        let fixture = try RewriteFixture.copy("everyday")
        defer { fixture.remove() }
        let app = launch()
        app.buttons["welcome-open"].click()
        let field = app.textFields["Folder"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText(fixture.root + "/Sources")
        attach(app, "j-open-sheet-light")
        app.buttons["open-run"].click()
        XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 20))
        app.terminate()
    }

    @MainActor
    func testReportAGitProblemFromTheHelpMenu() throws {
        let app = launch()
        app.menuBars.menuBarItems["Help"].click()
        let item = app.menuItems["Report a git problem\u{2026}"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
        XCTAssertTrue(app.buttons["bugreport-run"].waitForExistence(timeout: 5))
        attach(app, "j-bugreport-light")
        app.typeKey(.escape, modifierFlags: [])
        app.terminate()
    }

    @MainActor
    func testGitReferenceOpensTheManualPage() throws {
        let app = launch()
        app.menuBars.menuBarItems["Help"].click()
        app.menuItems["Git reference"].hover()
        let item = app.menuItems["git rebase"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
        XCTAssertTrue(app.descendants(matching: .any)["git-reference"].waitForExistence(timeout: 15))
        attach(app, "j-reference-light")
        app.typeKey(.return, modifierFlags: [])
        app.terminate()
    }
}
