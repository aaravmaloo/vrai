import XCTest

final class PlacesFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testWorktreesAddLockAndRemove() throws {
        let fixture = try PlacesFixture.copy()
        defer { fixture.remove() }
        let app = fixture.launch()
        PlacesFixture.expand(app, "worktrees")
        let release = app.buttons["vrai-release"]
        XCTAssertTrue(release.waitForExistence(timeout: 10))
        release.click()
        XCTAssertTrue(app.descendants(matching: .any)["worktree-detail"].waitForExistence(timeout: 10))
        PlacesFixture.attach(self, app, "places-worktrees-light")

        app.buttons["worktree-lock"].click()
        XCTAssertTrue(PlacesFixture.eventually { (try? fixture.lockedCount()) == 2 })

        app.menuBars.menuBarItems["Repository"].click()
        app.menuItems["Add worktree\u{2026}"].click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        let name = sheet.textFields["Branch name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeText("fix/ui-worktree")
        PlacesFixture.attach(self, app, "places-sheet-worktree-light")
        sheet.buttons["Add worktree"].firstMatch.click()
        let folder = fixture.folder + "/everyday/vrai-ui-worktree"
        XCTAssertTrue(PlacesFixture.eventually(15) { FileManager.default.fileExists(atPath: folder + "/README.md") })
        XCTAssertEqual(try fixture.git(["rev-parse", "--abbrev-ref", "fix/ui-worktree"]).output.trimmingCharacters(in: .whitespacesAndNewlines), "fix/ui-worktree")

        let row = app.descendants(matching: .any)["worktree-row-vrai-ui-worktree"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        let remove = app.buttons["worktree-remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.click()
        let confirm = app.buttons["Remove worktree"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(PlacesFixture.eventually(15) { !FileManager.default.fileExists(atPath: folder) })
        app.terminate()
    }

    @MainActor
    func testRemovingADirtyWorktreeCanBeUndone() throws {
        let fixture = try PlacesFixture.copy()
        defer { fixture.remove() }
        let worktree = fixture.folder + "/everyday/vrai-release"
        try Data("edited in a test\n".utf8).write(to: URL(filePath: worktree + "/README.md"))
        let app = fixture.launch()
        PlacesFixture.expand(app, "worktrees")
        let release = app.buttons["vrai-release"]
        XCTAssertTrue(release.waitForExistence(timeout: 10))
        release.click()
        app.buttons["worktree-remove"].click()
        let confirm = app.buttons["Remove worktree"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(PlacesFixture.eventually(15) { !FileManager.default.fileExists(atPath: worktree) })
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.click()
        XCTAssertTrue(PlacesFixture.eventually(10) { (try? fixture.git(["stash", "list", "--format=%gs"]).output.contains("changes from worktree vrai-release")) == true })
        app.terminate()
    }

    @MainActor
    func testSubmodulesInitializeAndDeinitialize() throws {
        let fixture = try PlacesFixture.copy()
        defer { fixture.remove() }
        let app = fixture.launch()
        PlacesFixture.expand(app, "submodules")
        let parser = app.buttons["swift-argument-parser"]
        XCTAssertTrue(parser.waitForExistence(timeout: 10))
        parser.click()
        let initialize = app.buttons["submodule-init"]
        XCTAssertTrue(initialize.waitForExistence(timeout: 10))
        PlacesFixture.attach(self, app, "places-submodules-light")
        initialize.click()
        XCTAssertTrue(PlacesFixture.eventually(20) { FileManager.default.fileExists(atPath: fixture.root + "/Vendor/swift-argument-parser/.git") })
        let deinitialize = app.buttons["submodule-deinit"]
        XCTAssertTrue(PlacesFixture.eventually { deinitialize.isEnabled })
        deinitialize.click()
        let confirm = app.buttons["Deinitialize"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(PlacesFixture.eventually(15) { ((try? FileManager.default.contentsOfDirectory(atPath: fixture.root + "/Vendor/swift-argument-parser")) ?? ["x"]).isEmpty })
        app.terminate()
    }

    @MainActor
    func testAddSubmoduleSheetAddsIt() throws {
        let fixture = try PlacesFixture.copy()
        defer { fixture.remove() }
        let app = fixture.launch()
        app.menuBars.menuBarItems["Repository"].click()
        app.menuItems["Add submodule\u{2026}"].click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        let url = sheet.textFields["URL"]
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        url.click()
        url.typeText("file://" + fixture.folder + "/everyday/remotes/cmark-gfm.git")
        let path = sheet.textFields["Path"]
        XCTAssertTrue(path.waitForExistence(timeout: 5))
        path.click()
        path.typeKey("a", modifierFlags: .command)
        path.typeText("Vendor/cmark-copy")
        PlacesFixture.attach(self, app, "places-sheet-submodule-light")
        sheet.buttons["Add submodule"].firstMatch.click()
        XCTAssertTrue(PlacesFixture.eventually(20) { ((try? String(contentsOfFile: fixture.root + "/.gitmodules", encoding: .utf8)) ?? "").contains("[submodule \"Vendor/cmark-copy\"]") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.root + "/Vendor/cmark-copy/.git"))
        app.terminate()
    }

    @MainActor
    func testReflogResetIsRecordedInUndo() throws {
        let fixture = try PlacesFixture.copy()
        defer { fixture.remove() }
        try fixture.mustGit(["stash", "push", "--include-untracked", "-q", "-m", "test setup"])
        try fixture.mustGit(["-c", "core.hooksPath=/dev/null", "commit", "--allow-empty", "--no-gpg-sign", "-q", "-m", "Reflog probe"])
        let moved = try fixture.value(["rev-parse", "HEAD"])
        let before = try fixture.value(["rev-parse", "HEAD@{1}"])
        let app = fixture.launch()
        let toggled = PlacesFixture.expert(app)
        let reflog = app.buttons["Reflog"]
        XCTAssertTrue(reflog.waitForExistence(timeout: 10))
        reflog.click()
        let entry = app.descendants(matching: .any)["HEAD@{1}"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.click()
        XCTAssertTrue(app.descendants(matching: .any)["reflog-detail"].waitForExistence(timeout: 10))
        PlacesFixture.attach(self, app, "places-reflog-light")
        app.buttons["reflog-reset"].click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        let keep = sheet.buttons["Keep"]
        XCTAssertTrue(keep.waitForExistence(timeout: 10))
        keep.click()
        sheet.buttons["reset-run"].click()
        XCTAssertTrue(PlacesFixture.eventually(10) { (try? fixture.value(["rev-parse", "HEAD"])) == before })
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(PlacesFixture.eventually(10) { (try? fixture.value(["rev-parse", "HEAD"])) == moved })
        if toggled { app.typeKey("e", modifierFlags: [.command, .option]) }
        app.terminate()
    }

    @MainActor
    func testRefsListEveryNamespace() throws {
        let fixture = try PlacesFixture.copy()
        defer { fixture.remove() }
        let main = try fixture.value(["rev-parse", "main"])
        let release = try fixture.value(["rev-parse", "release/0.9"])
        try fixture.mustGit(["replace", main, release])
        let app = fixture.launch()
        let toggled = PlacesFixture.expert(app)
        let refs = app.buttons["Refs"]
        XCTAssertTrue(refs.waitForExistence(timeout: 10))
        refs.click()
        XCTAssertTrue(app.descendants(matching: .any)["refs-group-refs/heads"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["refs-group-refs/replace"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["ref-refs/heads/main"].exists)
        PlacesFixture.attach(self, app, "places-refs-light")
        if toggled { app.typeKey("e", modifierFlags: [.command, .option]) }
        app.terminate()
    }

    @MainActor
    func testBlameShowsAgeShading() throws {
        let app = PlacesFixture.launch(Sandbox.fixture("everyday"))
        PlacesFixture.openFileMenu(app, "Blame")
        XCTAssertTrue(app.descendants(matching: .any)["blame-view"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["blame-revision"].waitForExistence(timeout: 10))
        let line = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Line 12,")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        PlacesFixture.attach(self, app, "places-blame-light")
        line.click()
        let before = app.buttons["blame-before"]
        XCTAssertTrue(PlacesFixture.eventually { before.isEnabled })
        before.click()
        XCTAssertTrue(PlacesFixture.eventually { (app.descendants(matching: .any)["blame-revision"].label).hasPrefix("Blame at ") && !(app.descendants(matching: .any)["blame-revision"].label).hasSuffix("HEAD") })
        PlacesFixture.attach(self, app, "places-blame-before-light")
        app.terminate()
    }

    @MainActor
    func testFileHistoryShowsTheFilesDiffPerCommit() throws {
        let app = PlacesFixture.launch(Sandbox.fixture("everyday"))
        PlacesFixture.openFileMenu(app, "File history")
        XCTAssertTrue(app.descendants(matching: .any)["file-history-view"].waitForExistence(timeout: 10))
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'file-history-' AND NOT (identifier IN {'file-history-view', 'file-history-back', 'file-history-show'})"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(rows.count, 2)
        rows.element(boundBy: 1).click()
        XCTAssertTrue(app.buttons["file-history-show"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1)
        PlacesFixture.attach(self, app, "places-file-history-light")
        app.terminate()
    }

    @MainActor
    func testPlacesStayBelowTheToolbarAtEverySize() throws {
        for (size, name) in [("1280x800", "wide"), ("1000x700", "w1000"), ("700x800", "w700"), ("460x700", "w460"), ("1280x460", "h460")] {
            for appearance in ["light", "dark"] {
                let app = PlacesFixture.launch(Sandbox.fixture("everyday"), appearance: appearance, size: size)
                let window = app.windows.firstMatch
                PlacesFixture.revealSidebar(app)
                PlacesFixture.expand(app, "worktrees")
                let release = app.buttons["vrai-release"]
                if release.waitForExistence(timeout: 10) {
                    release.click()
                    let detail = app.descendants(matching: .any)["worktree-detail"]
                    let list = app.descendants(matching: .any)["worktree-row-vrai-release"]
                    XCTAssertTrue(detail.waitForExistence(timeout: 5) || list.waitForExistence(timeout: 5), "\(name) \(appearance): worktrees didn't show")
                    let header = detail.exists ? detail : list
                    XCTAssertGreaterThan(header.frame.minY, window.frame.minY + 40, "\(name) \(appearance): the worktree view slid under the toolbar")
                    PlacesFixture.attach(self, app, "places-worktrees-\(name)-\(appearance)")
                }
                PlacesFixture.revealSidebar(app)
                PlacesFixture.expand(app, "submodules")
                let module = app.buttons["libgit2"]
                if module.waitForExistence(timeout: 10) {
                    module.click()
                    Thread.sleep(forTimeInterval: 0.8)
                    PlacesFixture.attach(self, app, "places-submodules-\(name)-\(appearance)")
                }
                PlacesFixture.openFileMenu(app, "Blame")
                let blame = app.descendants(matching: .any)["blame-back"]
                if blame.waitForExistence(timeout: 10) {
                    XCTAssertGreaterThan(blame.frame.minY, window.frame.minY + 40, "\(name) \(appearance): the blame bar slid under the toolbar")
                    Thread.sleep(forTimeInterval: 0.8)
                    PlacesFixture.attach(self, app, "places-blame-\(name)-\(appearance)")
                }
                PlacesFixture.openFileMenu(app, "File history")
                if app.descendants(matching: .any)["file-history-view"].waitForExistence(timeout: 10) {
                    Thread.sleep(forTimeInterval: 0.8)
                    PlacesFixture.attach(self, app, "places-file-history-\(name)-\(appearance)")
                }
                app.terminate()
            }
        }
    }

    @MainActor
    func testExpertPlacesAtEverySize() throws {
        for (size, name) in [("1280x800", "wide"), ("700x800", "w700"), ("460x700", "w460"), ("1280x460", "h460")] {
            for appearance in ["light", "dark"] {
                let app = PlacesFixture.launch(Sandbox.fixture("everyday"), appearance: appearance, size: size)
                PlacesFixture.revealSidebar(app)
                let toggled = PlacesFixture.expert(app)
                let reflog = app.buttons["Reflog"]
                if reflog.waitForExistence(timeout: 10) {
                    reflog.click()
                    XCTAssertTrue(app.descendants(matching: .any)["reflog-view"].waitForExistence(timeout: 10))
                    Thread.sleep(forTimeInterval: 0.8)
                    PlacesFixture.attach(self, app, "places-reflog-\(name)-\(appearance)")
                }
                PlacesFixture.revealSidebar(app)
                let refs = app.buttons["Refs"]
                if refs.waitForExistence(timeout: 10) {
                    refs.click()
                    let console = app.buttons["refs-console"]
                    XCTAssertTrue(console.waitForExistence(timeout: 10))
                    XCTAssertGreaterThan(console.frame.minY, app.windows.firstMatch.frame.minY + 40, "\(name) \(appearance): the refs header slid under the toolbar")
                    Thread.sleep(forTimeInterval: 0.8)
                    PlacesFixture.attach(self, app, "places-refs-\(name)-\(appearance)")
                }
                if toggled { app.typeKey("e", modifierFlags: [.command, .option]) }
                app.terminate()
            }
        }
    }
}

struct PlacesFixture {
    let folder: String
    let root: String

    static func copy() throws -> PlacesFixture {
        let folder = Sandbox.root + "/tests/" + UUID().uuidString
        let source = Sandbox.root + "/fixtures/everyday"
        let target = folder + "/everyday"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: source, toPath: target)
        FixtureHooks.useOriginals(copy: target, original: source)
        let fixture = PlacesFixture(folder: folder, root: target + "/vrai")
        for name in try fixture.git(["remote"]).output.split(separator: "\n").map(String.init) {
            let url = try fixture.value(["remote", "get-url", name])
            guard url.contains(source) else { continue }
            try fixture.mustGit(["remote", "set-url", name, url.replacingOccurrences(of: source, with: target)])
        }
        let worktrees = ["vrai-release", "vrai-review"].map { target + "/" + $0 }.filter { FileManager.default.fileExists(atPath: $0) }
        if !worktrees.isEmpty { try fixture.mustGit(["worktree", "repair"] + worktrees) }
        try fixture.mustGit(["submodule", "sync", "--recursive"])
        return fixture
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: folder)
        Sandbox.forgetRecent(root)
    }

    @MainActor
    func launch(appearance: String = "light", size: String = "1280x800") -> XCUIApplication {
        Self.launch(root, appearance: appearance, size: size)
    }

    @MainActor
    static func launch(_ path: String, appearance: String = "light", size: String = "1280x800") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-VraiSandbox", Sandbox.root,
            "-VraiOpen", path,
            "-VraiAppearance", appearance,
            "-VraiNow", Sandbox.now,
            "-VraiWindowSize", size,
            "-VraiCapture", "YES",
            "-ApplePersistenceIgnoreState", "YES"
        ]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.activate()
        return app
    }

    func git(_ arguments: [String]) throws -> Sandbox.Outcome {
        let outcome = try Sandbox.git(arguments, in: root)
        let output = outcome.output.range(of: ": ").map { String(outcome.output[$0.upperBound...]) } ?? outcome.output
        return Sandbox.Outcome(status: outcome.status, output: output)
    }

    func value(_ arguments: [String]) throws -> String {
        try git(arguments).output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func mustGit(_ arguments: [String]) throws {
        let outcome = try git(arguments)
        if outcome.status != 0 { throw NSError(domain: "PlacesFixture", code: Int(outcome.status), userInfo: [NSLocalizedDescriptionKey: arguments.joined(separator: " ") + ": " + outcome.output]) }
    }

    func lockedCount() throws -> Int {
        try git(["worktree", "list", "--porcelain"]).output.split(separator: "\n").filter { $0.hasPrefix("locked") }.count
    }

    @MainActor
    static func expand(_ app: XCUIApplication, _ key: String) {
        let header = app.buttons["sidebar-section-" + key]
        guard header.waitForExistence(timeout: 10) else { return }
        if header.value as? String == "Collapsed" { header.click() }
    }

    @MainActor
    static func revealSidebar(_ app: XCUIApplication) {
        guard !app.buttons["sidebar-section-worktrees"].exists else { return }
        app.typeKey("s", modifierFlags: [.command, .control])
        Thread.sleep(forTimeInterval: 0.6)
    }

    @MainActor @discardableResult
    static func expert(_ app: XCUIApplication) -> Bool {
        if app.buttons["Reflog"].waitForExistence(timeout: 2) { return false }
        app.typeKey("e", modifierFlags: [.command, .option])
        Thread.sleep(forTimeInterval: 0.8)
        return true
    }

    @MainActor
    static func openFileMenu(_ app: XCUIApplication, _ item: String) {
        app.typeKey("2", modifierFlags: .command)
        let row = app.descendants(matching: .any)["change-row-unstaged-Sources/VraiGit/Graph/LaneLayout.swift"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.rightClick()
        let menu = app.menuItems[item]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.click()
    }

    static func eventually(_ timeout: TimeInterval = 10, _ condition: () throws -> Bool) rethrows -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return try condition()
    }

    @MainActor
    static func attach(_ test: XCTestCase, _ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        test.add(shot)
    }
}
