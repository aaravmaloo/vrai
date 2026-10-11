import XCTest

final class SyncFlowTests: XCTestCase {
    struct Copy {
        let folder: String

        var repo: String { folder + "/vrai" }

        func remote(_ name: String) -> String { folder + "/remotes/" + name + ".git" }

        static func make(_ scenario: String) throws -> Copy {
            try FileManager.default.createDirectory(atPath: Sandbox.root + "/tests", withIntermediateDirectories: true)
            let copy = Copy(folder: Sandbox.root + "/tests/" + UUID().uuidString)
            try FileManager.default.copyItem(atPath: Sandbox.root + "/fixtures/" + scenario, toPath: copy.folder)
            FixtureHooks.useOriginals(copy: copy.folder, original: Sandbox.root + "/fixtures/" + scenario)
            for name in ["origin", "mira"] where FileManager.default.fileExists(atPath: copy.remote(name)) {
                let current = try Sandbox.git(["remote", "get-url", name], in: copy.repo)
                guard current.status == 0, current.output.contains("file://") else { continue }
                let outcome = try Sandbox.git(["remote", "set-url", name, "file://" + copy.remote(name)], in: copy.repo)
                XCTAssertEqual(outcome.status, 0, outcome.output)
            }
            return copy
        }

        func remove() {
            try? FileManager.default.removeItem(atPath: folder)
            Sandbox.forgetRecent(repo)
        }

        func git(_ arguments: [String], in directory: String? = nil) throws -> Sandbox.Outcome {
            try Sandbox.git(arguments, in: directory ?? repo)
        }

        func value(_ arguments: [String], in directory: String? = nil) throws -> String {
            let outcome = try git(arguments, in: directory)
            guard outcome.status == 0, let colon = outcome.output.range(of: ": ") else { return "" }
            return String(outcome.output[colon.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func exists(_ ref: String, in directory: String? = nil) throws -> Bool {
            try git(["rev-parse", "--verify", "--quiet", ref], in: directory).status == 0
        }
    }

    static let credentials = Sandbox.root + "/git-credentials"
    static let authPort = ProcessInfo.processInfo.environment["VRAI_AUTH_PORT"] ?? "47816"
    static let expiredLine = "http://avery:vrai_expired_token@127.0.0.1%3a" + authPort

    var savedCredentials: Data?

    override func setUp() {
        continueAfterFailure = false
        savedCredentials = FileManager.default.contents(atPath: Self.credentials)
    }

    override func tearDown() {
        if let savedCredentials { try? savedCredentials.write(to: URL(filePath: Self.credentials)) }
    }

    @MainActor
    private func launch(_ path: String, appearance: String = "light", size: String = "1280x800") -> XCUIApplication {
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
        XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1)
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
    private func button(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    private func text(_ app: XCUIApplication, _ value: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", value, value)).firstMatch
    }

    @MainActor
    private func textContaining(_ app: XCUIApplication, _ value: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", value, value)).firstMatch
    }

    @MainActor
    func testPushRejectedShowsCopyAndForcePushWithLeaseSucceeds() throws {
        let copy = try Copy.make("push-rejected")
        defer { copy.remove() }
        let app = launch(copy.repo)
        let push = button(app, "Push 2 commits")
        XCTAssertTrue(push.waitForExistence(timeout: 5))
        push.click()

        XCTAssertTrue(text(app, "Push rejected").waitForExistence(timeout: 15))
        XCTAssertTrue(text(app, "origin has 2 commits you don't have. Pull them first, or force push with lease to replace them.").exists)
        XCTAssertTrue(button(app, "Pull").exists)
        let force = button(app, "Force push with lease")
        XCTAssertTrue(force.exists)
        attach(app, "sync-push-rejected-light")

        let local = try copy.value(["rev-parse", "refs/heads/feature/graph-renderer"])
        XCTAssertNotEqual(try copy.value(["rev-parse", "refs/heads/feature/graph-renderer"], in: copy.remote("origin")), local)
        force.click()
        XCTAssertTrue(try eventually(15) { try copy.value(["rev-parse", "refs/heads/feature/graph-renderer"], in: copy.remote("origin")) == local })
        XCTAssertTrue(textContaining(app, "Force pushed").waitForExistence(timeout: 5))
        attach(app, "sync-force-pushed-light")
        app.terminate()
    }

    @MainActor
    func testAuthSignInAgainStoresTokenInTheSandboxStore() throws {
        let copy = try Copy.make("auth")
        defer { copy.remove() }
        try ensureExpiredCredential()
        let url = try copy.value(["remote", "get-url", "origin"])
        XCTAssertTrue(url.hasPrefix("http://127.0.0.1:" + Self.authPort), url)
        let app = launch(copy.repo)

        button(app, "Fetch").click()
        let title = text(app, "127.0.0.1 didn't accept your credentials for vrai.")
        let shown = title.waitForExistence(timeout: 20)
        if !shown { attach(app, "sync-auth-missing") }
        XCTAssertTrue(shown, "the auth alert did not appear; is Scripts/auth-server.py running on port \(Self.authPort)?")
        let again = button(app, "Sign in again\u{2026}")
        XCTAssertTrue(again.exists)
        attach(app, "sync-auth-alert-light")
        again.click()

        let username = app.textFields["Username"].firstMatch
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        XCTAssertTrue(text(app, "Sign in to 127.0.0.1").exists)
        username.click()
        username.typeKey("a", modifierFlags: .command)
        username.typeText("avery")
        let token = "vrai_ui_" + UUID().uuidString.prefix(8).lowercased()
        let field = app.secureTextFields["Token"].firstMatch
        XCTAssertTrue(field.exists)
        field.click()
        field.typeText(token)
        attach(app, "sync-sign-in-sheet-light")

        let closed = try copy.git(["remote", "set-url", "origin", "http://127.0.0.1:9/vrai.git"])
        XCTAssertEqual(closed.status, 0, closed.output)
        button(app, "Sign in").click()

        let expected = "http://avery:" + token + "@127.0.0.1%3a" + Self.authPort
        XCTAssertTrue(eventually(10) { (try? String(contentsOfFile: Self.credentials, encoding: .utf8))?.contains(expected) == true })
        XCTAssertTrue(textContaining(app, "Signed in to 127.0.0.1 as avery").waitForExistence(timeout: 5))
        attach(app, "sync-signed-in-light")
        app.terminate()
    }

    @MainActor
    func testAskpassPromptShowsTheSignInSheet() throws {
        let copy = try Copy.make("auth")
        defer { copy.remove() }
        try removeCredential(for: "127.0.0.1%3a" + Self.authPort)
        let app = launch(copy.repo)

        button(app, "Fetch").click()
        let username = app.textFields["Username"].firstMatch
        XCTAssertTrue(username.waitForExistence(timeout: 20), "git did not ask through vrai-askpass")
        XCTAssertTrue(textContaining(app, "git needs a username and token to reach").exists)
        attach(app, "sync-askpass-sheet-light")
        username.click()
        username.typeText("avery")
        app.secureTextFields["Token"].firstMatch.click()
        app.secureTextFields["Token"].firstMatch.typeText("wrong-token")
        button(app, "Sign in").click()
        XCTAssertTrue(text(app, "127.0.0.1 didn't accept your credentials for vrai.").waitForExistence(timeout: 20))
        app.terminate()
    }

    @MainActor
    func testOfflineShowsItsCopy() throws {
        let copy = try Copy.make("offline")
        defer { copy.remove() }
        let app = launch(copy.repo)
        button(app, "Fetch").click()
        XCTAssertTrue(text(app, "Couldn't reach 127.0.0.1").waitForExistence(timeout: 20))
        XCTAssertTrue(text(app, "Check your connection. Vrai retries fetch when you're back online.").exists)
        XCTAssertTrue(button(app, "Retry").exists)
        XCTAssertTrue(text(app, "Offline").waitForExistence(timeout: 5))
        XCTAssertTrue(text(app, "Fetch, pull and push wait until 127.0.0.1 is reachable. Everything else works.").exists)
        attach(app, "sync-offline-light")
        app.terminate()
    }

    @MainActor
    func testCreateSwitchDeleteAndUndoABranch() throws {
        let copy = try Copy.make("everyday")
        defer { copy.remove() }
        let app = launch(copy.repo)

        button(app, "New branch").click()
        let name = app.textFields["Name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeText("feature/ui-test")
        attach(app, "sync-branch-sheet-filled-light")
        button(app, "Create and switch").click()
        let created = try eventually { try copy.value(["symbolic-ref", "--short", "HEAD"]) == "feature/ui-test" }
        if !created { attach(app, "debug-create") }
        XCTAssertTrue(created)
        XCTAssertTrue(textContaining(app, "Created and switched to feature/ui-test").waitForExistence(timeout: 5))

        let back = app.buttons.matching(NSPredicate(format: "label == %@", "graph-renderer")).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.doubleClick()
        XCTAssertTrue(try eventually { try copy.value(["symbolic-ref", "--short", "HEAD"]) == "feature/graph-renderer" })

        let row = app.buttons.matching(NSPredicate(format: "label == %@", "ui-test")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.rightClick()
        let delete = app.menuItems["Delete feature/ui-test\u{2026}"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.click()
        XCTAssertTrue(text(app, "Delete feature/ui-test?").waitForExistence(timeout: 5))
        attach(app, "sync-delete-branch-light")
        button(app, "Delete branch").click()
        XCTAssertTrue(try eventually { try !copy.exists("refs/heads/feature/ui-test") })

        let undo = button(app, "Undo")
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.click()
        XCTAssertTrue(try eventually { try copy.exists("refs/heads/feature/ui-test") })
        XCTAssertTrue(textContaining(app, "Undid: Deleted branch feature/ui-test").waitForExistence(timeout: 5))
        app.terminate()
    }

    @MainActor
    func testSwitchAsksToBringOrStashChanges() throws {
        let copy = try Copy.make("everyday")
        defer { copy.remove() }
        let main = try copy.value(["rev-parse", "refs/heads/main"])
        XCTAssertFalse(main.isEmpty)
        let app = launch(copy.repo)
        let row = app.buttons.matching(NSPredicate(format: "label == %@", "main")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.doubleClick()
        XCTAssertTrue(text(app, "Bring your changes to main?").waitForExistence(timeout: 10))
        XCTAssertTrue(button(app, "Bring changes").exists)
        let stash = button(app, "Stash and switch")
        XCTAssertTrue(stash.exists)
        attach(app, "sync-switch-dirty-light")
        stash.click()
        XCTAssertTrue(try eventually { try copy.value(["symbolic-ref", "--short", "HEAD"]) == "main" })
        XCTAssertTrue(try copy.exists("refs/stash"))
        app.terminate()
    }

    @MainActor
    func testFetchUpdatesTheCounts() throws {
        let copy = try Copy.make("everyday")
        defer { copy.remove() }
        let clone = copy.folder + "/second"
        XCTAssertEqual(try copy.git(["clone", "-q", "--branch", "feature/graph-renderer", "file://" + copy.remote("origin"), clone], in: copy.folder).status, 0)
        XCTAssertEqual(try copy.git(["-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false", "commit", "--allow-empty", "-q", "-m", "Graph: one more from the second clone"], in: clone).status, 0)
        XCTAssertEqual(try copy.git(["push", "-q", "origin", "feature/graph-renderer"], in: clone).status, 0)

        let app = launch(copy.repo)
        XCTAssertTrue(button(app, "Pull 1 commit").waitForExistence(timeout: 5))
        attach(app, "sync-toolbar-before-fetch-light")
        button(app, "Fetch").click()
        let updated = button(app, "Pull 2 commits").waitForExistence(timeout: 15)
        if !updated { attach(app, "debug-fetch") }
        XCTAssertTrue(updated)
        XCTAssertTrue(textContaining(app, "new commit").waitForExistence(timeout: 5))
        attach(app, "sync-toolbar-after-fetch-light")
        app.terminate()
    }

    @MainActor
    func testCaptureSurfacesLight() throws {
        try captureSurfaces("light")
    }

    @MainActor
    func testCaptureSurfacesDark() throws {
        try captureSurfaces("dark")
    }

    @MainActor
    func testCaptureCompactSizes() throws {
        for appearance in ["light", "dark"] {
            for size in ["1280x500", "700x800", "700x500"] {
                try captureCompact(appearance, size: size)
            }
        }
    }

    @MainActor
    func testToolbarGroupsSitAtTheTrailingEdge() throws {
        let copy = try Copy.make("everyday")
        defer { copy.remove() }
        for appearance in ["light", "dark"] {
            for size in ["1440x800", "1000x700", "700x700", "460x700"] {
                let app = launch(copy.repo, appearance: appearance, size: size)
                let suffix = appearance + "-" + size
                attach(app, "toolbar-" + suffix)
                checkToolbar(app, suffix: suffix, narrow: size.hasPrefix("700") || size.hasPrefix("460"))
                if size == "1440x800" {
                    button(app, "Hide inspector").click()
                    Thread.sleep(forTimeInterval: 0.6)
                    attach(app, "toolbar-" + suffix + "-inspector-off")
                    checkToolbar(app, suffix: suffix + "-inspector-off", narrow: false)
                    button(app, "Show inspector").click()
                    Thread.sleep(forTimeInterval: 0.3)
                }
                app.terminate()
            }
        }
    }

    @MainActor
    private func checkToolbar(_ app: XCUIApplication, suffix: String, narrow: Bool) {
        let window = app.windows.firstMatch.frame
        let names = narrow ? ["Actions"] : ["Sync", "Branch", "Stash", "Panels"]
        var frames: [(String, CGRect)] = names.compactMap { name in
            let group = app.toolbars.firstMatch.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
            return group.exists ? (name, group.frame) : nil
        }
        let field = app.toolbars.firstMatch.descendants(matching: .any).matching(identifier: "toolbar-palette-field").firstMatch
        if !narrow, field.exists { frames.append(("Field", field.frame)) }
        frames.sort { $0.1.minX < $1.1.minX }
        var report = ["window " + String(describing: window)]
        report += frames.map { $0.0 + " " + String(describing: $0.1) }
        let inspector = app.toolbars.firstMatch.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Hide inspector", "Show inspector")).firstMatch
        let console = app.toolbars.firstMatch.buttons.matching(NSPredicate(format: "label == %@", "Show console")).firstMatch
        if !narrow, inspector.exists, console.exists {
            report.append("Console " + String(describing: console.frame))
            report.append("Inspector " + String(describing: inspector.frame))
        }
        let note = XCTAttachment(string: report.joined(separator: "\n"))
        note.name = "toolbar-metrics-" + suffix
        note.lifetime = .keepAlways
        add(note)

        XCTAssertEqual(frames.count, narrow ? 1 : 5, report.joined(separator: "; "))
        guard let last = frames.last else { return }
        XCTAssertEqual(window.maxX - last.1.maxX, 12, accuracy: 1.5, "trailing edge " + suffix)
        for (left, right) in zip(frames, frames.dropFirst()) {
            XCTAssertEqual(right.1.minX - left.1.maxX, 12, accuracy: 1.5, "gap " + left.0 + " to " + right.0 + " " + suffix)
        }
        for frame in frames {
            XCTAssertEqual(frame.1.height, 32, accuracy: 0.5, frame.0 + " height " + suffix)
            XCTAssertEqual(frame.1.midY, last.1.midY, accuracy: 0.5, frame.0 + " centre " + suffix)
        }
        if !narrow, inspector.exists, console.exists, let panels = frames.first(where: { $0.0 == "Panels" })?.1 {
            for button in [console.frame, inspector.frame] {
                XCTAssertEqual(button.width, 36, accuracy: 0.5, "panel button width " + suffix)
                XCTAssertEqual(button.height, 28, accuracy: 0.5, "panel button height " + suffix)
                XCTAssertEqual(button.midY, panels.midY, accuracy: 0.5, "panel button centre " + suffix)
            }
            XCTAssertEqual(console.frame.minX - panels.minX, 2, accuracy: 0.5, "console inset " + suffix)
            XCTAssertEqual(panels.maxX - inspector.frame.maxX, 2, accuracy: 0.5, "inspector inset " + suffix)
        }
    }

    @MainActor
    private func captureCompact(_ appearance: String, size: String) throws {
        let suffix = appearance + "-" + size
        let copy = try Copy.make("offline")
        defer { copy.remove() }
        let app = launch(copy.repo, appearance: appearance, size: size)
        attach(app, "compact-toolbar-" + suffix)

        app.menuBars.menuBarItems["Repository"].click()
        app.menuItems["Fetch, pull and push with options\u{2026}"].click()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.sheets.firstMatch.descendants(matching: .any).matching(NSPredicate(format: "value == %@ OR label == %@", "Sync with remotes", "Sync with remotes")).firstMatch.waitForExistence(timeout: 10))
        let sheet = app.sheets.firstMatch
        sheet.buttons.matching(NSPredicate(format: "label == %@", "Options")).firstMatch.click()
        Thread.sleep(forTimeInterval: 0.8)
        attach(app, "compact-sync-sheet-" + suffix)
        XCTAssertLessThanOrEqual(sheet.frame.maxY, app.windows.firstMatch.frame.maxY + 1, "sync sheet overflows " + suffix)
        sheet.buttons.matching(NSPredicate(format: "label == %@", "Cancel")).firstMatch.click()
        Thread.sleep(forTimeInterval: 0.6)

        app.menuBars.menuBarItems["Branch"].click()
        app.menuItems["New branch\u{2026}"].click()
        XCTAssertTrue(app.textFields["Name"].firstMatch.waitForExistence(timeout: 5))
        app.sheets.firstMatch.buttons.matching(NSPredicate(format: "label == %@", "Options")).firstMatch.click()
        Thread.sleep(forTimeInterval: 0.8)
        attach(app, "compact-branch-sheet-" + suffix)
        XCTAssertLessThanOrEqual(app.sheets.firstMatch.frame.maxY, app.windows.firstMatch.frame.maxY + 1, "branch sheet overflows " + suffix)
        app.sheets.firstMatch.buttons.matching(NSPredicate(format: "label == %@", "Cancel")).firstMatch.click()
        Thread.sleep(forTimeInterval: 0.6)

        app.menuBars.menuBarItems["Repository"].click()
        app.menuItems["Fetch"].click()
        XCTAssertTrue(text(app, "Couldn't reach 127.0.0.1").waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 0.6)
        attach(app, "compact-offline-" + suffix)
        app.terminate()
    }

    @MainActor
    private func captureSurfaces(_ appearance: String) throws {
        let copy = try Copy.make("everyday")
        defer { copy.remove() }
        var app = launch(copy.repo, appearance: appearance)
        attach(app, "sync-toolbar-" + appearance)

        app.menuBars.menuBarItems["Repository"].click()
        app.menuItems["Fetch, pull and push with options\u{2026}"].click()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.sheets.firstMatch.descendants(matching: .any).matching(NSPredicate(format: "value == %@ OR label == %@", "Sync with remotes", "Sync with remotes")).firstMatch.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.8)
        attach(app, "sync-sheet-push-" + appearance)
        let sheet = app.sheets.firstMatch
        sheet.buttons.matching(NSPredicate(format: "label == %@", "Pull")).firstMatch.click()
        Thread.sleep(forTimeInterval: 0.6)
        attach(app, "sync-sheet-pull-" + appearance)
        sheet.buttons.matching(NSPredicate(format: "label == %@", "Fetch")).firstMatch.click()
        Thread.sleep(forTimeInterval: 0.6)
        attach(app, "sync-sheet-fetch-" + appearance)
        sheet.buttons.matching(NSPredicate(format: "label == %@", "Cancel")).firstMatch.click()
        Thread.sleep(forTimeInterval: 0.6)

        button(app, "New branch").click()
        XCTAssertTrue(app.textFields["Name"].firstMatch.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.8)
        attach(app, "sync-branch-sheet-" + appearance)
        button(app, "Cancel").click()
        app.terminate()

        let rejected = try Copy.make("push-rejected")
        defer { rejected.remove() }
        app = launch(rejected.repo, appearance: appearance)
        button(app, "Push 2 commits").click()
        XCTAssertTrue(text(app, "Push rejected").waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 0.6)
        attach(app, "sync-push-rejected-" + appearance)
        button(app, "Cancel").click()
        app.terminate()

        let auth = try Copy.make("auth")
        defer { auth.remove() }
        try ensureExpiredCredential()
        app = launch(auth.repo, appearance: appearance)
        button(app, "Fetch").click()
        if text(app, "127.0.0.1 didn't accept your credentials for vrai.").waitForExistence(timeout: 20) {
            Thread.sleep(forTimeInterval: 0.6)
            attach(app, "sync-auth-alert-" + appearance)
            button(app, "Cancel").click()
            Thread.sleep(forTimeInterval: 0.8)
            attach(app, "sync-auth-banner-" + appearance)
        }
        app.terminate()
    }

    private func ensureExpiredCredential() throws {
        let current = (try? String(contentsOfFile: Self.credentials, encoding: .utf8)) ?? ""
        let lines = current.split(separator: "\n").map(String.init).filter { !$0.contains("127.0.0.1%3a" + Self.authPort) }
        try (lines + [Self.expiredLine]).joined(separator: "\n").appending("\n").write(toFile: Self.credentials, atomically: true, encoding: .utf8)
    }

    private func removeCredential(for host: String) throws {
        let current = (try? String(contentsOfFile: Self.credentials, encoding: .utf8)) ?? ""
        let lines = current.split(separator: "\n").map(String.init).filter { !$0.contains(host) }
        try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: Self.credentials, atomically: true, encoding: .utf8)
    }
}
