import XCTest

final class RewriteFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testConflictResolvesBlockByBlockAndCommitsTheMerge() throws {
        let fixture = try RewriteFixture.copy("conflict")
        defer { fixture.remove() }
        let app = fixture.launch()
        let resolve = app.buttons["Resolve conflicts"]
        XCTAssertTrue(resolve.waitForExistence(timeout: 10))
        resolve.click()
        let pane = app.descendants(matching: .any)["conflicts-pane"]
        XCTAssertTrue(pane.waitForExistence(timeout: 10))
        var files = 0
        while pane.exists, files < 6 {
            var picks = 0
            var scrolls = 0
            let accept = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'accept-'"))
            XCTAssertTrue(accept.firstMatch.waitForExistence(timeout: 10))
            let mark = app.buttons["mark-resolved"]
            while picks < 20 {
                if accept.count == 0 {
                    if mark.exists, mark.isEnabled { break }
                    guard scrolls < 12 else { break }
                    pane.scroll(byDeltaX: 0, deltaY: -300)
                    Thread.sleep(forTimeInterval: 0.3)
                    scrolls += 1
                    continue
                }
                let choices = ["accept-current", "accept-incoming", "accept-both"]
                let prefix = choices[picks % choices.count]
                let button = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix + "-")).firstMatch
                let target = button.exists ? button : accept.firstMatch
                let id = target.identifier
                let number = id.split(separator: "-").last.map(String.init) ?? ""
                target.click()
                XCTAssertTrue(app.descendants(matching: .any)["resolved-" + number].waitForExistence(timeout: 10), "block \(id) did not resolve")
                picks += 1
            }
            XCTAssertTrue(mark.waitForExistence(timeout: 5))
            XCTAssertTrue(wait { mark.isEnabled })
            mark.click()
            files += 1
            let advanced = wait(timeout: 10) { (try? fixture.unmerged())?.isEmpty == true || app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'accept-'")).count > 0 }
            if !advanced {
                let texts = app.staticTexts.allElementsBoundByIndex.prefix(60).map(\.label).joined(separator: " | ")
                XCTContext.runActivity(named: "texts: \(texts) state \(app.state.rawValue)") { _ in }
                attach(app, "rewrite-conflict-stuck-\(files)")
            }
            XCTAssertTrue(advanced, (try? fixture.unmerged().joined(separator: ", ")) ?? "")
            if try fixture.unmerged().isEmpty { break }
        }
        XCTAssertEqual(files, 2)
        XCTAssertTrue(try fixture.unmerged().isEmpty)
        let markers = try fixture.git(["grep", "-l", "-e", "^<<<<<<<", "--", "Sources"])
        XCTAssertEqual(markers.output.trimmingCharacters(in: .whitespacesAndNewlines), "")
        let commit = app.buttons["Commit merge"]
        XCTAssertTrue(commit.waitForExistence(timeout: 10))
        commit.click()
        XCTAssertTrue(wait(timeout: 15) { !fixture.exists(".git/MERGE_HEAD") })
        let parents = try fixture.git(["rev-list", "--parents", "-n", "1", "HEAD"]).output.split(separator: " ")
        XCTAssertEqual(parents.count, 3)
        let second = try fixture.git(["rev-parse", "HEAD^2"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let mira = try fixture.git(["rev-parse", "refs/heads/mira/spike/metal-graph"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(second, mira)
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5))
        attach(app, "rewrite-conflict-committed")
        app.terminate()
    }

    @MainActor
    func testConflictViewStaysBelowTheToolbarAtEverySize() throws {
        for (size, name) in [("1280x800", "default"), ("700x800", "w700"), ("1280x500", "h500")] {
            for appearance in ["light", "dark"] {
                let fixture = try RewriteFixture.copy("conflict")
                let app = fixture.launch(appearance: appearance, size: size)
                let resolve = app.buttons["Resolve conflicts"]
                XCTAssertTrue(resolve.waitForExistence(timeout: 10))
                resolve.click()
                let summary = app.descendants(matching: .any)["conflict-summary"]
                XCTAssertTrue(summary.waitForExistence(timeout: 10))
                let window = app.windows.firstMatch
                let incoming = app.buttons["accept-incoming-1"]
                XCTAssertTrue(incoming.waitForExistence(timeout: 10))
                let pane = app.descendants(matching: .any)["conflicts-pane"]
                for _ in 0..<12 where !incoming.isHittable {
                    pane.scroll(byDeltaX: 0, deltaY: -80)
                    Thread.sleep(forTimeInterval: 0.3)
                }
                XCTAssertTrue(incoming.isHittable, "\(name) \(appearance): the first conflict can't be reached by scrolling")
                incoming.click()
                XCTAssertTrue(app.descendants(matching: .any)["resolved-1"].waitForExistence(timeout: 10))
                pane.scroll(byDeltaX: 0, deltaY: -600)
                Thread.sleep(forTimeInterval: 0.8)
                let top = window.frame.minY
                attach(app, "rewrite-conflict-\(name)-\(appearance)-scrolled")
                XCTAssertGreaterThan(summary.frame.minY, top + 40, "\(name) \(appearance): the conflict header slid under the toolbar")
                XCTAssertLessThanOrEqual(window.frame.height, 801)
                let mark = app.buttons["mark-resolved"]
                XCTAssertTrue(mark.isHittable, "\(name) \(appearance): Mark as resolved can't be clicked")
                attach(app, "rewrite-conflict-\(name)-\(appearance)")
                app.terminate()
                fixture.remove()
            }
        }
    }

    @MainActor
    func testInteractiveRebaseReordersRewordsSquashesAndDrops() throws {
        let fixture = try RewriteFixture.copy("everyday")
        defer { fixture.remove() }
        try fixture.clean()
        let base = try fixture.git(["log", "-1", "--format=%s"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        for (index, word) in ["one", "two", "three", "four"].enumerated() {
            try fixture.write("Notes/rebase-\(word).txt", "\(word)\n")
            try fixture.mustGit(["add", "--", "Notes/rebase-\(word).txt"])
            try fixture.mustGit(["-c", "core.hooksPath=/dev/null", "commit", "-q", "-m", "Test \(word)", "--date", "@\(1791700000 + index)"])
        }
        let app = fixture.launch()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", base + ",")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.rightClick()
        let item = app.menuItems["Interactive rebase from here\u{2026}"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
        let fourth = app.descendants(matching: .any)["step-4"]
        XCTAssertTrue(fourth.waitForExistence(timeout: 10))
        attach(app, "rewrite-interactive-start")

        fourth.click()
        app.typeKey(.upArrow, modifierFlags: .option)
        app.descendants(matching: .any)["step-2"].click()
        app.typeText("r")
        let reword = app.textFields["reword-2"]
        XCTAssertTrue(reword.waitForExistence(timeout: 5))
        reword.click()
        reword.typeKey("a", modifierFlags: .command)
        reword.typeText("Test two, reworded")
        app.descendants(matching: .any)["step-4"].click()
        app.typeText("s")
        let squash = app.textFields["squash-4"]
        XCTAssertTrue(squash.waitForExistence(timeout: 5))
        squash.click()
        squash.typeText("Test four with three")
        app.descendants(matching: .any)["step-1"].click()
        app.typeText("d")
        let summary = app.staticTexts["rebase-summary"]
        XCTAssertTrue(wait { (summary.value as? String ?? summary.label).contains("dropped") })
        attach(app, "rewrite-interactive-plan")
        app.buttons["interactive-run"].click()

        let rebased = wait(timeout: 20) { (try? fixture.subjects(3)) == ["Test four with three", "Test two, reworded", base] }
        attach(app, "rewrite-interactive-after")
        XCTAssertTrue(rebased, (try? fixture.subjects(3).joined(separator: " | ")) ?? "")
        XCTAssertFalse(fixture.exists(".git/rebase-merge"))
        let files = try fixture.git(["show", "--name-only", "--format=", "HEAD"]).output.split(separator: "\n").map(String.init).sorted()
        XCTAssertEqual(files, ["Notes/rebase-four.txt", "Notes/rebase-three.txt"])
        XCTAssertFalse(fixture.exists("Notes/rebase-one.txt"))
        XCTAssertTrue(fixture.exists("Notes/rebase-two.txt"))
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5))
        app.terminate()
    }

    @MainActor
    func testRebaseContinuesAndSkipsFromTheBanner() throws {
        let fixture = try RewriteFixture.copy("rebase")
        defer { fixture.remove() }
        let todo = fixture.root + "/.git/rebase-merge/git-rebase-todo"
        let text = try String(contentsOfFile: todo, encoding: .utf8)
        let edited = text.replacing(#/(?m)^pick /#, with: "edit ", maxReplacements: 1)
        XCTAssertNotEqual(text, edited)
        try edited.write(toFile: todo, atomically: true, encoding: .utf8)
        let onto = try fixture.git(["rev-parse", "origin/main"]).output.trimmingCharacters(in: .whitespacesAndNewlines)

        let app = fixture.launch()
        let proceed = app.buttons["Continue"]
        XCTAssertTrue(proceed.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["2 of 3"].exists || app.descendants(matching: .any)["Step 2 of 3"].exists)
        attach(app, "rewrite-rebase-banner")
        proceed.click()
        XCTAssertTrue(wait(timeout: 15) { app.descendants(matching: .any)["Step 3 of 3"].exists })
        XCTAssertTrue(fixture.exists(".git/rebase-merge"))
        let skip = app.buttons["Skip"]
        XCTAssertTrue(wait { skip.isEnabled })
        skip.click()
        XCTAssertTrue(wait(timeout: 15) { !fixture.exists(".git/rebase-merge") })
        let count = try fixture.git(["rev-list", "--count", onto + "..HEAD"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(count, "3")
        let branch = try fixture.git(["symbolic-ref", "--short", "HEAD"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(branch, "feature/graph-renderer")
        XCTAssertTrue(app.staticTexts["Rebase finished"].waitForExistence(timeout: 5))
        app.terminate()
    }

    @MainActor
    func testHardResetIsUndoneFromTheToast() throws {
        let fixture = try RewriteFixture.copy("everyday")
        defer { fixture.remove() }
        let refsBefore = try fixture.refs()
        let statusBefore = try fixture.status()
        let target = try fixture.git(["log", "-1", "--skip=1", "--format=%s"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = fixture.launch()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", target + ",")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.rightClick()
        let item = app.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'Reset ' AND title ENDSWITH 'to here\u{2026}'")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
        let hard = app.descendants(matching: .any)["Hard"]
        XCTAssertTrue(hard.waitForExistence(timeout: 10))
        attach(app, "rewrite-reset-sheet")
        hard.click()
        app.buttons["reset-run"].click()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Reset and discard", "reset-run")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(wait(timeout: 15) { (try? fixture.refs()) != refsBefore })
        XCTAssertTrue(wait(timeout: 10) { (try? fixture.tracked())?.isEmpty == true })
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.click()
        XCTAssertTrue(wait(timeout: 15) { (try? fixture.refs()) == refsBefore })
        XCTAssertTrue(wait(timeout: 10) { (try? fixture.status()) == statusBefore })
        XCTAssertEqual(try fixture.refs(), refsBefore)
        app.terminate()
    }

    @MainActor
    func testMergeIsUndoneFromTheToast() throws {
        let fixture = try RewriteFixture.copy("everyday")
        defer { fixture.remove() }
        try fixture.clean()
        let refsBefore = try fixture.refs()
        let app = fixture.launch()
        let commits = app.descendants(matching: .any)["commits"]
        XCTAssertTrue(commits.waitForExistence(timeout: 10))
        commits.click()
        app.typeKey("m", modifierFlags: [.command, .shift])
        let run = app.buttons["merge-run"]
        if !run.waitForExistence(timeout: 5) {
            attach(app, "rewrite-merge-shortcut-missed")
            app.menuBars.menuBarItems["Branch"].click()
            app.menuBars.menuItems.matching(NSPredicate(format: "title BEGINSWITH %@", "Merge into")).firstMatch.click()
        }
        XCTAssertTrue(run.waitForExistence(timeout: 10))
        let enabled = wait(timeout: 20) { run.isEnabled }
        attach(app, "rewrite-merge-sheet")
        XCTAssertTrue(enabled)
        attach(app, "rewrite-merge-sheet")
        run.click()
        XCTAssertTrue(wait(timeout: 15) { (try? fixture.refs()) != refsBefore })
        let parents = try fixture.git(["rev-list", "--parents", "-n", "1", "HEAD"]).output.split(separator: " ")
        XCTAssertEqual(parents.count, 3)
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.click()
        XCTAssertTrue(wait(timeout: 15) { (try? fixture.refs()) == refsBefore })
        XCTAssertEqual(try fixture.refs(), refsBefore)
        XCTAssertEqual(try fixture.status(), "")
        app.terminate()
    }

    @MainActor
    func testRewritesAreUndoneFromUndoHistory() throws {
        let fixture = try RewriteFixture.copy("everyday")
        defer { fixture.remove() }
        try fixture.clean()
        let refsBefore = try fixture.refs()
        let app = fixture.launch()
        let commits = app.descendants(matching: .any)["commits"]
        XCTAssertTrue(commits.waitForExistence(timeout: 10))

        app.menuBars.menuBarItems["Branch"].click()
        app.menuBars.menuItems.matching(NSPredicate(format: "title BEGINSWITH %@", "Merge into")).firstMatch.click()
        let run = app.buttons["merge-run"]
        XCTAssertTrue(run.waitForExistence(timeout: 10))
        XCTAssertTrue(wait(timeout: 20) { run.isEnabled })
        run.click()
        XCTAssertTrue(wait(timeout: 15) { (try? fixture.refs()) != refsBefore })
        restoreLatestFromUndoHistory(app, "rewrite-undo-history-merge")
        XCTAssertTrue(wait(timeout: 15) { (try? fixture.refs()) == refsBefore })

        let target = try fixture.git(["log", "-1", "--skip=1", "--format=%s"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", target + ",")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.rightClick()
        let item = app.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'Reset ' AND title ENDSWITH 'to here\u{2026}'")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
        let soft = app.descendants(matching: .any)["Soft"]
        XCTAssertTrue(soft.waitForExistence(timeout: 10))
        soft.click()
        app.buttons["reset-run"].click()
        XCTAssertTrue(wait(timeout: 15) { (try? fixture.refs()) != refsBefore })
        restoreLatestFromUndoHistory(app, "rewrite-undo-history-reset")
        XCTAssertTrue(wait(timeout: 15) { (try? fixture.refs()) == refsBefore })
        XCTAssertEqual(try fixture.refs(), refsBefore)
        app.terminate()
    }

    @MainActor
    private func restoreLatestFromUndoHistory(_ app: XCUIApplication, _ name: String) {
        app.menuBars.menuBarItems["Edit"].click()
        app.menuBars.menuItems["Undo history\u{2026}"].click()
        let entry = app.descendants(matching: .any)["undo-row-0"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        attach(app, name)
        entry.buttons["undo-restore"].click()
        let done = app.buttons["undo-history-done"]
        if done.waitForExistence(timeout: 3) { done.click() }
    }

    @MainActor
    func testShortcutsWorkRightAfterLaunch() throws {
        let fixture = try RewriteFixture.copy("everyday")
        defer { fixture.remove() }
        let app = fixture.launch()
        XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 10))
        app.typeKey("j", modifierFlags: .command)
        let console = app.descendants(matching: .any)["console"]
        let opened = console.waitForExistence(timeout: 5)
        attach(app, "shortcut-console")
        XCTAssertTrue(opened, "Cmd-J did not open the console")
        app.typeKey("j", modifierFlags: .command)
        app.typeKey("b", modifierFlags: [.command, .shift])
        let title = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR value == %@", "New branch", "New branch")).firstMatch
        let sheet = title.waitForExistence(timeout: 5)
        attach(app, "shortcut-new-branch")
        XCTAssertTrue(sheet, "Cmd-Shift-B did not open New branch")
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("k", modifierFlags: .command)
        let palette = app.descendants(matching: .any)["command-palette"]
        XCTAssertTrue(palette.waitForExistence(timeout: 5), "Cmd-K did not open the palette")
        app.terminate()
    }

    @MainActor
    func testDropStashThenUndo() throws {
        let fixture = try RewriteFixture.copy("everyday")
        defer { fixture.remove() }
        let stashesBefore = try fixture.stashes()
        XCTAssertEqual(stashesBefore.count, 3)
        let app = fixture.launch()
        XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 10))
        app.typeKey("3", modifierFlags: .command)
        let drop = app.buttons["stash-drop"]
        XCTAssertTrue(drop.waitForExistence(timeout: 10))
        attach(app, "rewrite-stashes")
        drop.click()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Drop stash", "stash-drop")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(wait(timeout: 10) { (try? fixture.stashes())?.count == 2 })
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.click()
        XCTAssertTrue(wait(timeout: 10) { (try? fixture.stashes())?.count == 3 })
        XCTAssertEqual(try fixture.stashes().first, stashesBefore.first)
        app.terminate()
    }

    @MainActor
    func testCaptureViewsForParity() throws {
        for appearance in ["light", "dark"] {
            let conflict = try RewriteFixture.copy("conflict")
            var app = conflict.launch(appearance: appearance)
            let resolve = app.buttons["Resolve conflicts"]
            XCTAssertTrue(resolve.waitForExistence(timeout: 10))
            resolve.click()
            XCTAssertTrue(app.descendants(matching: .any)["conflicts-pane"].waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 1)
            attach(app, "rewrite-conflict-\(appearance)")
            app.terminate()
            conflict.remove()

            let rebase = try RewriteFixture.copy("rebase")
            app = rebase.launch(appearance: appearance)
            XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 1.5)
            attach(app, "rewrite-rebase-\(appearance)")
            app.terminate()
            rebase.remove()

            let everyday = try RewriteFixture.copy("everyday")
            app = everyday.launch(appearance: appearance)
            XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 1)
            app.typeKey("r", modifierFlags: [.command, .shift, .option])
            XCTAssertTrue(app.descendants(matching: .any)["step-1"].waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 0.8)
            attach(app, "rewrite-interactive-\(appearance)")
            app.typeKey(.escape, modifierFlags: [])
            Thread.sleep(forTimeInterval: 0.8)
            let second = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Graph: keep the HEAD halo above merge rings,")).firstMatch
            XCTAssertTrue(second.waitForExistence(timeout: 5))
            second.rightClick()
            let reset = app.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'Reset ' AND title ENDSWITH 'to here\u{2026}'")).firstMatch
            XCTAssertTrue(reset.waitForExistence(timeout: 5))
            reset.click()
            XCTAssertTrue(app.descendants(matching: .any)["Hard"].waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 0.8)
            attach(app, "rewrite-reset-\(appearance)")
            app.typeKey(.escape, modifierFlags: [])
            Thread.sleep(forTimeInterval: 0.8)
            app.typeKey("3", modifierFlags: .command)
            XCTAssertTrue(app.buttons["stash-drop"].waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 1)
            attach(app, "rewrite-stashes-\(appearance)")
            app.terminate()
            everyday.remove()
        }
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let window = app.windows.firstMatch
        guard app.state == .runningForeground, window.exists, window.frame.width <= 1400, window.frame.height <= 900 else {
            XCTContext.runActivity(named: "skipped screenshot \(name): no app window") { _ in }
            return
        }
        let shot = XCTAttachment(screenshot: window.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func wait(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }
}

struct RewriteFixture {
    let folder: String
    let root: String

    static func copy(_ scenario: String) throws -> RewriteFixture {
        let folder = Sandbox.root + "/tests/" + UUID().uuidString
        let source = Sandbox.root + "/fixtures/" + scenario
        let target = folder + "/" + scenario
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: source, toPath: target)
        FixtureHooks.useOriginals(copy: target, original: source)
        let fixture = RewriteFixture(folder: folder, root: target + "/vrai")
        let remotes = try fixture.git(["remote"]).output.split(separator: "\n").map(String.init)
        for name in remotes {
            let url = try fixture.git(["remote", "get-url", name]).output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard url.contains(source) else { continue }
            try fixture.mustGit(["remote", "set-url", name, url.replacingOccurrences(of: source, with: target)])
        }
        let worktrees = ["vrai-release", "vrai-review"].map { target + "/" + $0 }.filter { FileManager.default.fileExists(atPath: $0) }
        if !worktrees.isEmpty { _ = try fixture.git(["worktree", "repair"] + worktrees) }
        return fixture
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: folder)
        Sandbox.forgetRecent(root)
    }

    @MainActor
    func launch(appearance: String = "light", size: String = "1280x800") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-VraiSandbox", Sandbox.root,
            "-VraiOpen", root,
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

    @discardableResult
    func git(_ arguments: [String]) throws -> Sandbox.Outcome {
        let outcome = try Sandbox.git(arguments, in: root)
        let prefix = outcome.output.range(of: ": ").map { String(outcome.output[$0.upperBound...]) } ?? outcome.output
        return Sandbox.Outcome(status: outcome.status, output: prefix)
    }

    func mustGit(_ arguments: [String]) throws {
        let outcome = try git(arguments)
        if outcome.status != 0 { throw NSError(domain: "RewriteFixture", code: Int(outcome.status), userInfo: [NSLocalizedDescriptionKey: arguments.joined(separator: " ") + ": " + outcome.output]) }
    }

    func clean() throws {
        try mustGit(["stash", "push", "--include-untracked", "-q", "-m", "test setup"])
    }

    func write(_ path: String, _ text: String) throws {
        let url = URL(filePath: root + "/" + path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: root + "/" + path)
    }

    func refs() throws -> String {
        let heads = try git(["for-each-ref", "--format=%(refname) %(objectname)", "refs/heads"]).output
        let head = try git(["rev-parse", "HEAD"]).output
        let symbolic = try git(["symbolic-ref", "-q", "HEAD"]).output
        return heads + head + symbolic
    }

    func status() throws -> String {
        try git(["status", "--porcelain=v1", "--untracked-files=all", "--ignore-submodules=all"]).output
    }

    func tracked() throws -> String {
        try git(["status", "--porcelain=v1", "--untracked-files=no", "--ignore-submodules=all"]).output
    }

    func unmerged() throws -> [String] {
        try git(["diff", "--name-only", "--diff-filter=U"]).output.split(separator: "\n").map(String.init)
    }

    func stashes() throws -> [String] {
        try git(["stash", "list", "--format=%H %gs"]).output.split(separator: "\n").map(String.init)
    }

    func subjects(_ count: Int) throws -> [String] {
        try git(["log", "-\(count)", "--format=%s"]).output.split(separator: "\n").map(String.init)
    }
}
