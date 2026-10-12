import XCTest

final class A11yAuditTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testHistoryChangesAndStashes() throws {
        for appearance in AuditLab.appearances {
            let lab = try AuditLab.make(["everyday"])
            defer { lab.remove() }
            let app = lab.launch(appearance: appearance)
            let commit = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Graph: keep the HEAD halo above merge rings,")).firstMatch
            XCTAssertTrue(commit.waitForExistence(timeout: 10))
            commit.click()
            Thread.sleep(forTimeInterval: 1)
            audit(app, "history-\(appearance)")

            app.typeKey("2", modifierFlags: .command)
            let change = app.descendants(matching: .any)["change-row-unstaged-Sources/VraiGit/Graph/LaneLayout.swift"]
            XCTAssertTrue(change.waitForExistence(timeout: 10))
            change.click()
            audit(app, "changes-\(appearance)")

            app.typeKey("3", modifierFlags: .command)
            XCTAssertTrue(app.buttons["stash-drop"].waitForExistence(timeout: 10))
            audit(app, "stashes-\(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testReflogAndRefs() throws {
        for appearance in AuditLab.appearances {
            let lab = try AuditLab.make(["everyday"], expert: true)
            defer { lab.remove() }
            let app = lab.launch(appearance: appearance)
            let reflog = AuditLab.sidebarItem(app, "Reflog")
            XCTAssertTrue(reflog.exists)
            reflog.click()
            XCTAssertTrue(app.descendants(matching: .any)["reflog-view"].waitForExistence(timeout: 10))
            let entry = app.buttons["HEAD@{1}"]
            if entry.waitForExistence(timeout: 5) { entry.click() }
            audit(app, "reflog-\(appearance)")

            let refs = AuditLab.sidebarItem(app, "Refs")
            XCTAssertTrue(refs.exists)
            refs.click()
            XCTAssertTrue(app.descendants(matching: .any)["refs-group-refs/heads"].waitForExistence(timeout: 10))
            audit(app, "refs-\(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testWorktreesAndSubmodules() throws {
        for appearance in AuditLab.appearances {
            let lab = try AuditLab.make(["everyday"])
            defer { lab.remove() }
            let app = lab.launch(appearance: appearance)
            AuditLab.expand(app, "worktrees")
            let release = AuditLab.sidebarItem(app, "vrai-release")
            XCTAssertTrue(release.exists)
            release.click()
            XCTAssertTrue(app.descendants(matching: .any)["worktree-detail"].waitForExistence(timeout: 10))
            audit(app, "worktrees-\(appearance)")

            AuditLab.expand(app, "submodules")
            let module = AuditLab.sidebarItem(app, "libgit2")
            XCTAssertTrue(module.exists)
            module.click()
            XCTAssertTrue(app.buttons["submodule-deinit"].waitForExistence(timeout: 10) || app.buttons["submodule-init"].waitForExistence(timeout: 5))
            audit(app, "submodules-\(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testBlameAndFileHistory() throws {
        for appearance in AuditLab.appearances {
            let lab = try AuditLab.make(["everyday"])
            defer { lab.remove() }
            let app = lab.launch(appearance: appearance)
            AuditLab.openFileMenu(app, "Blame")
            XCTAssertTrue(app.descendants(matching: .any)["blame-view"].waitForExistence(timeout: 10))
            let line = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Line 24,")).firstMatch
            XCTAssertTrue(line.waitForExistence(timeout: 10))
            line.click()
            audit(app, "blame-\(appearance)")

            AuditLab.openFileMenu(app, "File history")
            XCTAssertTrue(app.descendants(matching: .any)["file-history-view"].waitForExistence(timeout: 10))
            let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'file-history-' AND NOT (identifier IN {'file-history-view', 'file-history-back', 'file-history-show'})"))
            if rows.firstMatch.waitForExistence(timeout: 10) { rows.firstMatch.click() }
            audit(app, "file-history-\(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testConflictView() throws {
        for appearance in AuditLab.appearances {
            let lab = try AuditLab.make(["conflict"])
            defer { lab.remove() }
            let app = lab.launch(appearance: appearance, scenario: "conflict")
            let resolve = app.buttons["Resolve conflicts"]
            XCTAssertTrue(resolve.waitForExistence(timeout: 10))
            audit(app, "conflict-banner-\(appearance)")
            resolve.click()
            XCTAssertTrue(app.descendants(matching: .any)["conflicts-pane"].waitForExistence(timeout: 10))
            audit(app, "conflict-\(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testInteractiveRebaseSheet() throws {
        for appearance in AuditLab.appearances {
            let lab = try AuditLab.make(["everyday"])
            defer { lab.remove() }
            let app = lab.launch(appearance: appearance)
            AuditLab.focus(app)
            app.typeKey("r", modifierFlags: [.command, .shift, .option])
            XCTAssertTrue(app.descendants(matching: .any)["step-1"].waitForExistence(timeout: 10))
            audit(app, "interactive-rebase-\(appearance)", surface: app.sheets.firstMatch)
            app.typeKey(.escape, modifierFlags: [])
            app.terminate()
        }
    }

    @MainActor
    func testPaletteAndConsole() throws {
        for appearance in AuditLab.appearances {
            let lab = try AuditLab.make(["everyday"])
            defer { lab.remove() }
            let app = lab.launch(appearance: appearance)
            AuditLab.focus(app)
            app.typeKey("k", modifierFlags: .command)
            let field = app.textFields["palette-field"]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            audit(app, "palette-\(appearance)")
            field.typeText("graph")
            Thread.sleep(forTimeInterval: 0.6)
            audit(app, "palette-results-\(appearance)")
            app.typeKey(.escape, modifierFlags: [])
            app.typeKey(.escape, modifierFlags: [])

            AuditLab.focus(app)
            app.typeKey("j", modifierFlags: .command)
            XCTAssertTrue(app.descendants(matching: .any)["console"].waitForExistence(timeout: 10))
            audit(app, "console-\(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testWelcome() throws {
        for appearance in AuditLab.appearances {
            let lab = try AuditLab.make(["everyday"])
            defer { lab.remove() }
            let app = lab.launch(appearance: appearance, open: false)
            XCTAssertTrue(app.buttons["welcome-clone"].waitForExistence(timeout: 10))
            audit(app, "welcome-\(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testSettingsPanes() throws {
        let panes = [("general", "General"), ("git", "Git"), ("accounts", "Accounts"), ("appearance", "Appearance"), ("shortcuts", "Shortcuts"), ("repository", "Repository"), ("expert", "Expert")]
        for appearance in AuditLab.appearances {
            let lab = try AuditLab.make(["everyday"])
            defer { lab.remove() }
            let app = lab.launch(appearance: appearance, settings: "general")
            for (pane, title) in panes {
                AuditLab.settingsTab(app, title)
                XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "settings.pane." + pane).firstMatch.waitForExistence(timeout: 10), pane)
                audit(app, "settings-\(pane)-\(appearance)", surface: AuditLab.settingsWindow(app))
            }
            app.terminate()
        }
    }

    @MainActor
    func testSheetFamilies() throws {
        for appearance in AuditLab.appearances {
            let lab = try AuditLab.make(["everyday"])
            defer { lab.remove() }
            let app = lab.launch(appearance: appearance)

            AuditLab.menu(app, "Branch", "New branch\u{2026}")
            XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 10))
            audit(app, "sheet-branch-\(appearance)", surface: app.sheets.firstMatch)
            AuditLab.dismissSheet(app)

            AuditLab.menu(app, "Repository", "Fetch, pull and push with options\u{2026}")
            XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 10))
            audit(app, "sheet-sync-\(appearance)", surface: app.sheets.firstMatch)
            AuditLab.dismissSheet(app)

            let commit = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Graph: keep the HEAD halo above merge rings,")).firstMatch
            XCTAssertTrue(commit.waitForExistence(timeout: 10))
            commit.rightClick()
            let reset = app.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'Reset ' AND title ENDSWITH 'to here\u{2026}'")).firstMatch
            XCTAssertTrue(reset.waitForExistence(timeout: 5))
            reset.click()
            XCTAssertTrue(app.descendants(matching: .any)["Hard"].waitForExistence(timeout: 10))
            audit(app, "sheet-reset-\(appearance)", surface: app.sheets.firstMatch)
            AuditLab.dismissSheet(app)

            AuditLab.menu(app, "Repository", "Repository info\u{2026}")
            XCTAssertTrue(app.descendants(matching: .any)["repository-info"].waitForExistence(timeout: 15))
            audit(app, "sheet-info-\(appearance)", surface: app.sheets.firstMatch)
            AuditLab.dismissSheet(app)
            app.terminate()
        }
    }

    @MainActor
    private func audit(_ app: XCUIApplication, _ name: String, surface: XCUIElement? = nil) {
        Thread.sleep(forTimeInterval: 1)
        let window = app.windows.firstMatch
        let target = surface.flatMap { $0.exists ? $0 : nil } ?? window
        AuditLab.attach(self, app, "a11y-" + name, window: target.elementType == .sheet ? window : target)
        let area = target.frame
        let own = target.elementType == .sheet || target != window
        var found: [String] = []
        var ignored: [String] = []
        do {
            try app.performAccessibilityAudit(for: .all) { issue in
                let text = AuditLab.describe(issue)
                if let reason = AuditLab.allowed(issue, surface: own ? target : nil, area: area) {
                    ignored.append(text + " (" + reason + ")")
                } else {
                    found.append(text)
                    if issue.auditType == .contrast, let element = issue.element, element.exists {
                        let folder = URL(filePath: Sandbox.root + "/a11y-crops")
                        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        try? element.screenshot().pngRepresentation.write(to: folder.appending(path: "\(name)-\(found.count).png"))
                    }
                }
                return true
            }
        } catch {
            XCTFail("\(name): the audit did not run: \(error)")
        }
        AuditLab.log(name, found: found, ignored: ignored)
        for text in found { XCTFail("\(name): \(text)") }
    }
}

struct AuditLab {
    static let appearances = ["light", "dark"]

    let box: SettingsSandbox

    static func make(_ scenarios: [String], expert: Bool = false) throws -> AuditLab {
        let box = try SettingsSandbox.make(scenarios)
        let defaults = UserDefaults(suiteName: box.root + "/com.aaravmaloo.vrai.sandbox")
        defaults?.set(expert, forKey: "expert")
        defaults?.synchronize()
        return AuditLab(box: box)
    }

    func remove() {
        box.remove()
    }

    @MainActor
    func launch(appearance: String, scenario: String = "everyday", open: Bool = true, settings: String? = nil, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = [
            "-VraiSandbox", box.root,
            "-VraiAppearance", appearance,
            "-VraiNow", Sandbox.now,
            "-VraiCapture", "YES",
            "-ApplePersistenceIgnoreState", "YES"
        ]
        if open { arguments += ["-VraiOpen", box.repository(scenario), "-VraiWindowSize", "1280x800"] }
        if let settings { arguments += ["-VraiSettings", settings] }
        app.launchArguments = arguments + extra
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.activate()
        if open { XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 15) || app.buttons["Resolve conflicts"].waitForExistence(timeout: 5)) }
        Thread.sleep(forTimeInterval: 0.8)
        return app
    }

    @MainActor
    static func focus(_ app: XCUIApplication) {
        let commits = app.descendants(matching: .any)["commits"]
        if commits.exists, commits.isHittable { commits.click() }
    }

    @MainActor
    static func menu(_ app: XCUIApplication, _ bar: String, _ item: String) {
        app.menuBars.menuBarItems[bar].click()
        let entry = app.menuBars.menuItems[item].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5), item)
        entry.click()
    }

    @MainActor
    static func dismissSheet(_ app: XCUIApplication) {
        let sheet = app.sheets.firstMatch
        guard sheet.exists else { return }
        let cancel = sheet.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Cancel", "Done")).firstMatch
        if cancel.exists, cancel.isHittable { cancel.click() } else { app.typeKey(.escape, modifierFlags: []) }
        let deadline = Date().addingTimeInterval(5)
        while sheet.exists, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
    }

    @MainActor
    static func sidebar(_ app: XCUIApplication) -> XCUIElement {
        app.groups.matching(NSPredicate(format: "label == %@", "Repository")).firstMatch
    }

    @MainActor
    static func sidebarItem(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let item = sidebar(app).descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND elementType IN %@", label, [XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.cell.rawValue, XCUIElement.ElementType.outlineRow.rawValue])).firstMatch
        if item.waitForExistence(timeout: 10) { PlacesFixture.reveal(app, item) }
        return item
    }

    @MainActor
    static func expand(_ app: XCUIApplication, _ key: String) {
        PlacesFixture.expand(app, key)
    }

    @MainActor
    static func openFileMenu(_ app: XCUIApplication, _ item: String) {
        PlacesFixture.openFileMenu(app, item)
    }

    @MainActor
    static func settingsWindow(_ app: XCUIApplication) -> XCUIElement {
        app.windows.containing(NSPredicate(format: "identifier BEGINSWITH %@", "settings.pane.")).firstMatch
    }

    @MainActor
    static func settingsTab(_ app: XCUIApplication, _ title: String) {
        let button = settingsWindow(app).toolbars.buttons[title].firstMatch
        if button.waitForExistence(timeout: 3) {
            button.click()
        } else {
            app.buttons[title].firstMatch.click()
        }
    }

    @MainActor
    static func attach(_ test: XCTestCase, _ app: XCUIApplication, _ name: String, window: XCUIElement? = nil) {
        let target = window.flatMap { $0.exists ? $0 : nil } ?? app.windows.firstMatch
        guard target.exists, target.frame.width <= 1400, target.frame.height <= 900 else { return }
        let shot = XCTAttachment(screenshot: target.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        test.add(shot)
    }

    static func typeName(_ type: XCUIAccessibilityAuditType) -> String {
        let names: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "contrast"),
            (.elementDetection, "elementDetection"),
            (.hitRegion, "hitRegion"),
            (.sufficientElementDescription, "sufficientElementDescription"),
            (.action, "action"),
            (.parentChild, "parentChild")
        ]
        return names.filter { type.contains($0.0) }.map(\.1).joined(separator: "+")
    }

    @MainActor
    static func describe(_ issue: XCUIAccessibilityAuditIssue) -> String {
        var text = typeName(issue.auditType) + ": " + issue.compactDescription
        if let element = issue.element, element.exists {
            let value = (element.value as? String).map { ", value '\($0.prefix(40))'" } ?? ""
            text += " [type \(element.elementType.rawValue), id '\(element.identifier)', label '\(element.label)'\(value), frame \(element.frame.integral)]"
            if issue.compactDescription.contains("no description") {
                let children = element.children(matching: .any).allElementsBoundByIndex.prefix(4).map { "\($0.elementType.rawValue):'\($0.identifier)':'\($0.label.prefix(30))'" }
                text += " children [" + children.joined(separator: ", ") + "]"
            }
        } else {
            text += " [no element]"
        }
        return text + " | " + issue.detailedDescription.replacingOccurrences(of: "\n", with: " ")
    }

    @MainActor
    static func allowed(_ issue: XCUIAccessibilityAuditIssue, surface: XCUIElement?, area: CGRect) -> String? {
        guard let element = issue.element, element.exists else { return nil }
        let type = element.elementType
        let frame = element.frame
        if issue.auditType == .sufficientElementDescription, type == .touchBar {
            return "the Touch Bar element AppKit gives every app"
        }
        if type == .popUpButton, element.label == "emoji & symbols", frame.minY < 40, issue.auditType == .sufficientElementDescription || issue.auditType == .action {
            return "the system Emoji & Symbols input menu in the menu bar"
        }
        if issue.auditType == .sufficientElementDescription, type == .valueIndicator {
            return "the thumb AppKit draws inside a system slider"
        }
        guard issue.auditType == .contrast else { return nil }
        if type == .staticText, let surface, surface.elementType == .window, frame.minY < surface.frame.minY + 40, (element.value as? String) == surface.title {
            return "the window title AppKit draws in the Settings title bar"
        }
        if !area.insetBy(dx: -1, dy: -1).contains(frame) {
            return "not on the surface under test: covered by it, dimmed behind it, or scrolled out of view"
        }
        if let surface, !surface.descendants(matching: type).allElementsBoundByIndex.contains(where: { $0.frame == frame }) {
            return "behind the sheet or window under test, which covers or dims it"
        }
        if let ratio = renderedContrast(element), ratio >= 4.5 {
            return String(format: "its text pixels measure %.1f:1 against the background; the audit samples anti-aliased edges", ratio)
        }
        return nil
    }

    @MainActor
    static func renderedContrast(_ element: XCUIElement) -> Double? {
        guard let image = element.screenshot().image.cgImage(forProposedRect: nil, context: nil, hints: nil), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = image.width
        let height = image.height
        guard width > 2, height > 2 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var counts: [UInt32: Int] = [:]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            counts[UInt32(pixels[index]) << 16 | UInt32(pixels[index + 1]) << 8 | UInt32(pixels[index + 2]), default: 0] += 1
        }
        guard let background = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        let base = luminance(background)
        var foreground = 0
        var strong = 0
        var best = 1.0
        for (key, count) in counts where key != background {
            let other = luminance(key)
            let ratio = (max(other, base) + 0.05) / (min(other, base) + 0.05)
            guard ratio >= 1.5 else { continue }
            foreground += count
            if ratio >= 4.5 {
                strong += count
                best = max(best, ratio)
            }
        }
        guard foreground > 0, strong >= 12, Double(strong) >= Double(foreground) * 0.15 else { return nil }
        return best
    }

    static func luminance(_ rgb: UInt32) -> Double {
        func channel(_ value: UInt32) -> Double {
            let c = Double(value & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb >> 16) + 0.7152 * channel(rgb >> 8) + 0.0722 * channel(rgb)
    }

    static func log(_ name: String, found: [String], ignored: [String]) {
        let url = URL(filePath: Sandbox.root + "/a11y-audit.txt")
        var lines = ["== \(name): \(found.count) issues, \(ignored.count) ignored"]
        lines += found.map { "  " + $0 }
        lines += ignored.map { "  ignored " + $0 }
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
