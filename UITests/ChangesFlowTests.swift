import AppKit
import XCTest

final class ChangesFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testStageASingleLineFromTheGutter() throws {
        let copy = try ChangesFixtureCopy.everyday()
        addTeardownBlock { copy.remove() }
        try copy.append("README.md", lines: ["First added line", "Second added line"])

        let app = ChangesFixtureCopy.launch(copy.repo)
        ChangesFixtureCopy.openChanges(app)
        let row = app.descendants(matching: .any)["change-row-unstaged-README.md"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["change-row-staged-README.md"].exists)
        row.click()

        let gutter = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "gutter-", "First added line")).firstMatch
        XCTAssertTrue(gutter.waitForExistence(timeout: 10))
        gutter.click()
        let stageLine = app.buttons["Stage 1 line"]
        XCTAssertTrue(stageLine.waitForExistence(timeout: 5))
        ChangesFixtureCopy.attach(self, app, name: "changes-line-selected")
        stageLine.click()

        XCTAssertTrue(app.descendants(matching: .any)["change-row-staged-README.md"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["change-row-unstaged-README.md"].exists)
        let staged = try copy.git(["diff", "--cached", "--no-color", "-U0", "--", "README.md"])
        let changed = staged.split(separator: "\n").filter { ($0.hasPrefix("+") || $0.hasPrefix("-")) && !$0.hasPrefix("+++") && !$0.hasPrefix("---") }
        XCTAssertEqual(changed, ["+First added line"])
        ChangesFixtureCopy.attach(self, app, name: "changes-line-staged")
        app.terminate()
    }

    @MainActor
    func testDiscardAFileThenUndoBringsItBack() throws {
        let copy = try ChangesFixtureCopy.everyday()
        addTeardownBlock { copy.remove() }
        try copy.append("README.md", lines: ["Keep this line safe"])
        let edited = try copy.git(["hash-object", "--no-filters", "--", "README.md"])
        let original = try copy.git(["rev-parse", "HEAD:README.md"])

        let app = ChangesFixtureCopy.launch(copy.repo)
        ChangesFixtureCopy.openChanges(app)
        let row = app.descendants(matching: .any)["change-row-unstaged-README.md"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.rightClick()
        let discard = app.menuItems["Discard changes\u{2026}"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.click()
        let confirm = app.windows.firstMatch.sheets.buttons["Discard changes"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        ChangesFixtureCopy.attach(self, app, name: "changes-discard-alert")
        confirm.click()

        XCTAssertTrue(ChangesFixtureCopy.waitUntilGone(row, timeout: 10))
        XCTAssertEqual(try copy.git(["hash-object", "--no-filters", "--", "README.md"]), original)
        XCTAssertTrue(app.staticTexts["Discarded changes to README.md"].waitForExistence(timeout: 5))

        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["change-row-unstaged-README.md"].waitForExistence(timeout: 10))
        XCTAssertEqual(try copy.git(["hash-object", "--no-filters", "--", "README.md"]), edited)
        ChangesFixtureCopy.attach(self, app, name: "changes-discard-undone")
        app.terminate()
    }

    @MainActor
    func testCommitWithTheComposerShowsTheNewRowInHistory() throws {
        let copy = try ChangesFixtureCopy.everyday()
        addTeardownBlock { copy.remove() }
        let before = try copy.git(["rev-parse", "HEAD"])
        let subject = "Draw a halo behind HEAD"

        let app = ChangesFixtureCopy.launch(copy.repo)
        ChangesFixtureCopy.openChanges(app)
        let summary = app.textFields["commit-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        ChangesFixtureCopy.type(subject, into: summary)
        let button = app.buttons["commit-button"]
        XCTAssertTrue(button.isEnabled)
        ChangesFixtureCopy.attach(self, app, name: "changes-composer-ready")
        app.typeKey(.return, modifierFlags: .command)

        ChangesFixtureCopy.expect(self, app, app.staticTexts["Committed to feature/graph-renderer"], timeout: 15, "commit-toast")
        XCTAssertEqual(try copy.git(["log", "-1", "--format=%s"]), subject)
        XCTAssertEqual(try copy.git(["rev-parse", "HEAD^"]), before)
        XCTAssertEqual(summary.value as? String ?? "", "")

        app.typeKey("1", modifierFlags: .command)
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", subject + ", ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let first = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Uncommitted changes")).firstMatch
        if first.exists { XCTAssertLessThan(first.frame.minY, row.frame.minY) }
        ChangesFixtureCopy.attach(self, app, name: "changes-commit-in-history")
        app.terminate()
    }

    @MainActor
    func testFailingPreCommitHookShowsItsOutputAndKeepsTheMessage() throws {
        let copy = try ChangesFixtureCopy.everyday()
        addTeardownBlock { copy.remove() }
        FileManager.default.createFile(atPath: copy.repo + "/.git/vrai-fail-pre-commit", contents: Data())
        let before = try copy.git(["rev-parse", "HEAD"])
        let subject = "Draw a halo behind HEAD"

        let app = ChangesFixtureCopy.launch(copy.repo)
        ChangesFixtureCopy.openChanges(app)
        let summary = app.textFields["commit-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        ChangesFixtureCopy.type(subject, into: summary)
        app.buttons["commit-button"].click()

        let failure = app.descendants(matching: .any)["commit-hook-failure"]
        ChangesFixtureCopy.expect(self, app, failure, timeout: 15, "hook-failure")
        XCTAssertTrue(app.staticTexts["The pre-commit hook stopped the commit"].exists)
        let output = app.descendants(matching: .any).matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "swift-format lint --strict: 2 problems", "swift-format lint --strict: 2 problems")).firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.value as? String, subject)
        XCTAssertEqual(try copy.git(["rev-parse", "HEAD"]), before)
        ChangesFixtureCopy.attach(self, app, name: "changes-hook-failed")
        app.terminate()
    }

    @MainActor
    func testUndoHistoryRestoresAnEntry() throws {
        let copy = try ChangesFixtureCopy.everyday()
        addTeardownBlock { copy.remove() }
        let before = try copy.git(["rev-parse", "HEAD"])
        let subject = "Commit to undo from history"

        let app = ChangesFixtureCopy.launch(copy.repo)
        ChangesFixtureCopy.openChanges(app)
        let summary = app.textFields["commit-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        ChangesFixtureCopy.type(subject, into: summary)
        app.typeKey(.return, modifierFlags: .command)
        ChangesFixtureCopy.expect(self, app, app.staticTexts["Committed to feature/graph-renderer"], timeout: 15, "undo-commit-toast")
        XCTAssertNotEqual(try copy.git(["rev-parse", "HEAD"]), before)

        ChangesFixtureCopy.clickMenu(app, "Edit", "Undo history\u{2026}")
        let entry = app.descendants(matching: .any)["undo-row-0"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", "Committed \u{201C}", "Committed \u{201C}")).firstMatch.waitForExistence(timeout: 5))
        ChangesFixtureCopy.attach(self, app, name: "changes-undo-history")
        entry.buttons["undo-restore"].click()

        XCTAssertTrue(app.staticTexts["Undid: Committed \u{201C}\(subject)\u{201D}"].waitForExistence(timeout: 10))
        XCTAssertEqual(try copy.git(["rev-parse", "HEAD"]), before)
        XCTAssertTrue(try copy.git(["diff", "--cached", "--name-only"]).contains("Sources/VraiUI/History/GraphCell.swift"))
        app.terminate()
    }
}

struct ChangesFixtureCopy {
    let folder: String
    let repo: String

    static func everyday() throws -> ChangesFixtureCopy {
        let folder = Sandbox.root + "/tests/" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let source = Sandbox.root + "/fixtures/everyday"
        let target = folder + "/everyday"
        try FileManager.default.copyItem(atPath: source, toPath: target)
        FixtureHooks.useOriginals(copy: target, original: source)
        let copy = ChangesFixtureCopy(folder: folder, repo: target + "/vrai")
        for name in try copy.git(["remote"]).split(separator: "\n").map(String.init) {
            let url = try copy.git(["remote", "get-url", name])
            guard url.contains(source) else { continue }
            _ = try copy.git(["remote", "set-url", name, url.replacingOccurrences(of: source, with: target)])
        }
        _ = try copy.git(["config", "core.hooksPath", source + "/vrai/.git/hooks"])
        return copy
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: folder)
        Sandbox.forgetRecent(repo)
    }

    func append(_ path: String, lines: [String]) throws {
        let url = URL(filePath: repo + "/" + path)
        var text = try String(contentsOf: url, encoding: .utf8)
        if !text.hasSuffix("\n") { text += "\n" }
        text += lines.joined(separator: "\n") + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @discardableResult
    func git(_ arguments: [String]) throws -> String {
        let candidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/Applications/Xcode.app/Contents/Developer/usr/bin/git", "/Library/Developer/CommandLineTools/usr/bin/git", "/usr/bin/git"]
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/git")
        process.arguments = ["-C", repo] + arguments
        process.environment = Sandbox.environment
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    static func launch(_ path: String, appearance: String = "light", size: String = "1180x720") -> XCUIApplication {
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
        return app
    }

    @MainActor
    static func openChanges(_ app: XCUIApplication) {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 15))
        let list = app.descendants(matching: .any)["changes-list"]
        for _ in 0..<5 {
            app.activate()
            let item = app.menuBars.menuItems["Changes"]
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: item)
            _ = XCTWaiter().wait(for: [enabled], timeout: 3)
            app.typeKey("2", modifierFlags: .command)
            if list.waitForExistence(timeout: 3) { break }
        }
        XCTAssertTrue(list.waitForExistence(timeout: 5))
    }

    @MainActor
    static func clickMenu(_ app: XCUIApplication, _ menu: String, _ title: String) {
        for _ in 0..<5 {
            app.activate()
            let anchor = app.descendants(matching: .any)["changes-title"]
            if anchor.exists { anchor.click() }
            app.menuBars.menuBarItems[menu].click()
            let item = app.menuBars.menuItems[title]
            if item.waitForExistence(timeout: 3), item.isEnabled {
                item.click()
                return
            }
            app.typeKey(.escape, modifierFlags: [])
        }
        XCTFail("Menu item \(title) stayed disabled")
    }

    @MainActor
    static func type(_ text: String, into field: XCUIElement) {
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        for _ in 0..<4 {
            field.click()
            if XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: focused, object: field)], timeout: 2) == .completed { break }
        }
        field.typeText(text)
    }

    @MainActor
    static func expect(_ test: XCTestCase, _ app: XCUIApplication, _ element: XCUIElement, timeout: TimeInterval = 10, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        if element.waitForExistence(timeout: timeout) { return }
        attach(test, app, name: "failure-" + name)
        XCTFail("Missing " + name, file: file, line: line)
    }

    @MainActor
    static func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    @MainActor
    static func attach(_ test: XCTestCase, _ app: XCUIApplication, name: String) {
        let window = app.windows.firstMatch
        let frame = window.frame
        if let reason = obstruction(frame) {
            XCTContext.runActivity(named: "Skipped screenshot \(name): \(reason)") { _ in }
            return
        }
        let screenshot = window.screenshot()
        guard abs(screenshot.image.size.width - frame.width) < 1, abs(screenshot.image.size.height - frame.height) < 1 else {
            XCTContext.runActivity(named: "Skipped screenshot \(name): the capture does not match the window") { _ in }
            return
        }
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        test.add(shot)
    }

    static func obstruction(_ frame: CGRect) -> String? {
        guard frame.width > 0, frame.height > 0 else { return "no window" }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return "no window list" }
        func bounds(_ info: [String: Any]) -> CGRect? {
            guard let raw = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: raw)
        }
        func owner(_ info: [String: Any]) -> String { info[kCGWindowOwnerName as String] as? String ?? "?" }
        func layer(_ info: [String: Any]) -> Int { info[kCGWindowLayer as String] as? Int ?? 0 }
        let matches: (CGRect) -> Bool = { abs($0.minX - frame.minX) < 2 && abs($0.minY - frame.minY) < 2 && abs($0.width - frame.width) < 2 && abs($0.height - frame.height) < 2 }
        guard let index = list.firstIndex(where: { owner($0) == "Vrai" && (bounds($0).map(matches) ?? false) }) else {
            let mine = list.filter { owner($0) == "Vrai" }.compactMap { bounds($0).map { "\($0)" } }
            return "window \(frame) not on screen; Vrai windows: \(mine.joined(separator: " "))"
        }
        let ours = layer(list[index])
        for info in list[..<index] where owner(info) != "Vrai" && layer(info) >= 0 && layer(info) <= ours {
            guard let other = bounds(info), other.intersects(frame.insetBy(dx: 1, dy: 1)) else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha == 0 { continue }
            return "covered by \(owner(info)) at \(other) layer \(layer(info))"
        }
        return nil
    }
}
