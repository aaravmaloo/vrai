import XCTest

final class SettingsFlowTests: XCTestCase {
    var sandbox: SettingsSandbox?

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        sandbox?.remove()
        sandbox = nil
    }

    @MainActor
    private func launch(pane: String?, appearance: String = "light", scenario: String = "everyday") throws -> (XCUIApplication, SettingsSandbox) {
        let box = try SettingsSandbox.make([scenario])
        sandbox = box
        let app = XCUIApplication()
        var arguments = [
            "-VraiSandbox", box.root,
            "-VraiOpen", box.repository(scenario),
            "-VraiAppearance", appearance,
            "-VraiNow", Sandbox.now,
            "-VraiWindowSize", "1280x800",
            "-VraiCapture", "YES",
            "-ApplePersistenceIgnoreState", "YES"
        ]
        if let pane { arguments += ["-VraiSettings", pane] }
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 15))
        if let pane { XCTAssertTrue(element(app, "settings.pane." + pane).waitForExistence(timeout: 10), "the Settings window did not open on \(pane)") }
        Thread.sleep(forTimeInterval: 0.8)
        return (app, box)
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func settingsWindow(_ app: XCUIApplication) -> XCUIElement {
        app.windows.containing(NSPredicate(format: "identifier BEGINSWITH %@", "settings.pane.")).firstMatch
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let window = settingsWindow(app)
        let shot = XCTAttachment(screenshot: window.exists ? window.screenshot() : app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func eventually(_ timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }

    @MainActor
    private func clickWhenEnabled(_ app: XCUIApplication, _ identifier: String) {
        let target = element(app, identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 5), identifier)
        XCTAssertTrue(eventually { target.isEnabled }, identifier + " stayed disabled")
        target.click()
    }

    @MainActor
    private func replaceText(_ app: XCUIApplication, _ identifier: String, with text: String) {
        let field = element(app, identifier)
        XCTAssertTrue(field.waitForExistence(timeout: 5), identifier)
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text + "\r")
    }

    @MainActor
    private func choose(_ app: XCUIApplication, _ identifier: String, _ item: String) {
        let popup = element(app, identifier)
        XCTAssertTrue(popup.waitForExistence(timeout: 5), identifier)
        popup.click()
        let menuItem = app.menuItems[item].firstMatch
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5), item)
        menuItem.click()
    }

    @MainActor
    private func tab(_ app: XCUIApplication, _ title: String, pane: String) {
        let button = settingsWindow(app).toolbars.buttons[title].firstMatch
        if button.waitForExistence(timeout: 3) {
            button.click()
        } else {
            app.buttons[title].firstMatch.click()
        }
        XCTAssertTrue(element(app, "settings.pane." + pane).waitForExistence(timeout: 5), pane)
        Thread.sleep(forTimeInterval: 0.6)
    }

    @MainActor
    func testGitPaneWritesEveryKeyToTheGlobalConfig() throws {
        let (app, box) = try launch(pane: "git")
        XCTAssertEqual(box.global("init.defaultBranch"), "main")
        attach(app, "settings-git-light")

        replaceText(app, "settings.defaultBranch", with: "trunk")
        XCTAssertTrue(eventually { box.global("init.defaultBranch") == "trunk" }, "init.defaultBranch")

        choose(app, "settings.pullMode", "Rebase")
        XCTAssertTrue(eventually { box.global("pull.rebase") == "true" && box.global("pull.ff") == nil }, "pull.rebase")
        choose(app, "settings.pullMode", "Fast-forward only")
        XCTAssertTrue(eventually { box.global("pull.rebase") == "false" && box.global("pull.ff") == "only" }, "pull.ff")

        element(app, "settings.autostash").click()
        XCTAssertTrue(eventually { box.global("rebase.autoStash") == "true" && box.global("merge.autoStash") == "true" }, "autostash")

        element(app, "settings.rerere").click()
        XCTAssertTrue(eventually { box.global("rerere.enabled") == "false" }, "rerere.enabled")

        choose(app, "settings.diffAlgorithm", "Histogram")
        XCTAssertTrue(eventually { box.global("diff.algorithm") == "histogram" }, "diff.algorithm")

        XCTAssertTrue(element(app, "settings.renameThreshold").exists)
        XCTAssertTrue(element(app, "settings.gitBinary").exists)
        attach(app, "settings-git-changed-light")
        app.terminate()
    }

    @MainActor
    func testAccountsPaneWritesSigningAndIdentity() throws {
        let (app, box) = try launch(pane: "accounts")
        attach(app, "settings-accounts-light")

        replaceText(app, "settings.userName", with: "Avery Q. Chen")
        XCTAssertTrue(eventually { box.global("user.name") == "Avery Q. Chen" }, "user.name")
        replaceText(app, "settings.userEmail", with: "avery.chen@vrai.app")
        XCTAssertTrue(eventually { box.global("user.email") == "avery.chen@vrai.app" }, "user.email")

        element(app, "settings.signing").click()
        XCTAssertTrue(eventually { box.global("commit.gpgsign") == "false" && box.global("tag.gpgsign") == "false" }, "signing off")
        element(app, "settings.signing").click()
        XCTAssertTrue(eventually { box.global("commit.gpgsign") == "true" && box.global("tag.gpgsign") == "true" }, "signing on")

        app.buttons["GPG"].firstMatch.click()
        XCTAssertTrue(eventually { box.global("gpg.format") == "openpgp" }, "gpg.format openpgp")
        replaceText(app, "settings.signingKey", with: "4AEE18F83AFDEB23")
        XCTAssertTrue(eventually { box.global("user.signingkey") == "4AEE18F83AFDEB23" }, "user.signingkey gpg")
        app.buttons["SSH"].firstMatch.click()
        XCTAssertTrue(eventually { box.global("gpg.format") == "ssh" }, "gpg.format ssh")
        choose(app, "settings.signingKey", "id_ed25519.pub")
        XCTAssertTrue(eventually { box.global("user.signingkey") == box.home + "/.ssh/id_ed25519" }, "user.signingkey ssh")

        XCTAssertTrue(element(app, "settings.copyKey.id_ed25519").exists)
        attach(app, "settings-accounts-changed-light")
        app.terminate()
    }

    @MainActor
    func testAccountsSignInStoresTheTokenInTheSandboxStore() throws {
        let (app, box) = try launch(pane: "accounts", scenario: "auth")
        let url = try box.git(["remote", "get-url", "origin"], in: box.repository("auth")).output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = URL(string: url).flatMap({ components in components.host.map { $0 + (components.port.map { ":\($0)" } ?? "") } }) else { return XCTFail(url) }
        let signIn = element(app, "settings.signIn." + host)
        XCTAssertTrue(signIn.waitForExistence(timeout: 5), "no Sign in button for \(host)")
        signIn.click()
        let username = app.textFields["Username"].firstMatch
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        username.click()
        username.typeKey("a", modifierFlags: .command)
        username.typeText("avery")
        let token = "vrai_settings_" + UUID().uuidString.prefix(8).lowercased()
        let field = app.secureTextFields["Token"].firstMatch
        field.click()
        field.typeText(token)
        attach(app, "settings-accounts-sign-in-light")
        app.buttons["Sign in"].firstMatch.click()
        XCTAssertTrue(eventually { (try? String(contentsOfFile: box.credentials, encoding: .utf8))?.contains("avery:" + token + "@") == true }, "the token is not in the sandbox credential store")
        let signOut = element(app, "settings.signOut." + host)
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        attach(app, "settings-accounts-signed-in-light")
        signOut.click()
        XCTAssertTrue(eventually { (try? String(contentsOfFile: box.credentials, encoding: .utf8))?.contains(token) == false }, "git credential reject did not remove the token")
        app.terminate()
    }

    @MainActor
    func testRepositoryPaneWritesTheLocalConfig() throws {
        let (app, box) = try launch(pane: "repository")
        attach(app, "settings-repository-light")

        clickWhenEnabled(app, "settings.repository.localIdentity")
        XCTAssertTrue(eventually { box.local("user.name") == "Avery Chen" && box.local("user.email") == "avery@vrai.app" }, "local identity")
        replaceText(app, "settings.repository.name", with: "Avery at Work")
        XCTAssertTrue(eventually { box.local("user.name") == "Avery at Work" }, "local user.name")
        XCTAssertEqual(box.global("user.name"), "Avery Chen")
        clickWhenEnabled(app, "settings.repository.localIdentity")
        XCTAssertTrue(eventually { box.local("user.name") == nil && box.local("user.email") == nil }, "local identity removed")

        let hook = box.repository() + "/.git/hooks/pre-push"
        XCTAssertFalse(FileManager.default.isExecutableFile(atPath: hook))
        clickWhenEnabled(app, "settings.hook.pre-push")
        XCTAssertTrue(eventually { FileManager.default.isExecutableFile(atPath: hook) }, "pre-push is not executable")
        element(app, "settings.hook.run.pre-commit").click()
        XCTAssertTrue(app.staticTexts["pre-commit passed"].firstMatch.waitForExistence(timeout: 10))

        clickWhenEnabled(app, "settings.maintenance")
        XCTAssertTrue(eventually { box.globalAll("maintenance.repo").contains { $0.hasSuffix("/fixtures/everyday/vrai") } }, "maintenance.repo")
        XCTAssertTrue(eventually { box.local("maintenance.strategy") == "incremental" }, "maintenance.strategy")
        clickWhenEnabled(app, "settings.maintenance")
        XCTAssertTrue(eventually { box.globalAll("maintenance.repo").isEmpty }, "unregister")

        XCTAssertTrue(element(app, box.lfsInstalled ? "settings.lfs.installed" : "settings.lfs.missing").waitForExistence(timeout: 10))
        attach(app, "settings-repository-changed-light")
        app.terminate()
    }

    @MainActor
    func testExpertPaneAddsEditsAndRemovesConfig() throws {
        let (app, box) = try launch(pane: "expert")
        attach(app, "settings-expert-off-light")
        let turnOn = element(app, "settings.expert.turnOn")
        if turnOn.waitForExistence(timeout: 3) { turnOn.click() }
        XCTAssertTrue(element(app, "settings.config.add.key").waitForExistence(timeout: 5))
        attach(app, "settings-expert-on-light")

        replaceText(app, "settings.config.add.key", with: "merge.conflictStyle")
        let value = element(app, "settings.config.add.value")
        value.click()
        value.typeText("zdiff3")
        element(app, "settings.config.add").click()
        XCTAssertTrue(eventually { box.local("merge.conflictStyle") == "zdiff3" }, "add local")

        replaceText(app, "settings.config.local.merge.conflictstyle", with: "diff3")
        XCTAssertTrue(eventually { box.local("merge.conflictStyle") == "diff3" }, "edit local")

        let remove = element(app, "settings.config.remove.local.merge.conflictstyle")
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.click()
        XCTAssertTrue(eventually { box.local("merge.conflictStyle") == nil }, "remove local")

        replaceText(app, "settings.config.global.rerere.enabled", with: "false")
        XCTAssertTrue(eventually { box.global("rerere.enabled") == "false" }, "edit global")
        app.terminate()
    }

    @MainActor
    func testKeyboardShortcutsInTheHelpMenuOpensTheShortcutsPane() throws {
        let (app, _) = try launch(pane: nil)
        app.menuBars.menuBarItems["Help"].click()
        let item = app.menuBars.menuItems["Keyboard shortcuts"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
        XCTAssertTrue(element(app, "settings.pane.shortcuts").waitForExistence(timeout: 5))
        let search = element(app, "settings.shortcuts.search")
        XCTAssertTrue(search.exists)
        attach(app, "settings-shortcuts-light")
        search.click()
        search.typeText("force push")
        XCTAssertTrue(app.staticTexts["Force push with lease"].firstMatch.waitForExistence(timeout: 5))
        attach(app, "settings-shortcuts-search-light")
        app.typeKey("w", modifierFlags: .command)
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(element(app, "settings.pane.shortcuts").waitForExistence(timeout: 5))
        app.terminate()
    }

    @MainActor
    func testCaptureEveryPaneLight() throws {
        try captureEveryPane("light")
    }

    @MainActor
    func testCaptureEveryPaneDark() throws {
        try captureEveryPane("dark")
    }

    @MainActor
    private func captureEveryPane(_ appearance: String) throws {
        let (app, _) = try launch(pane: "general", appearance: appearance)
        let panes = [("general", "General"), ("git", "Git"), ("accounts", "Accounts"), ("appearance", "Appearance"), ("shortcuts", "Shortcuts"), ("repository", "Repository"), ("expert", "Expert")]
        for (pane, title) in panes {
            tab(app, title, pane: pane)
            attach(app, "settings-" + pane + (pane == "expert" ? "-off" : "") + "-" + appearance)
        }
        let turnOn = element(app, "settings.expert.turnOn")
        if turnOn.exists {
            turnOn.click()
            Thread.sleep(forTimeInterval: 0.6)
            attach(app, "settings-expert-on-" + appearance)
        }
        tab(app, "Appearance", pane: "appearance")
        app.buttons["Split"].firstMatch.click()
        element(app, "settings.whitespace").click()
        Thread.sleep(forTimeInterval: 0.5)
        attach(app, "settings-appearance-split-" + appearance)
        app.terminate()
    }
}
