import XCTest

final class PerfFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchToWelcomeWindow() throws {
        let log = PerfLogFile("launch")
        var samples: [Double] = []
        for _ in 0..<6 {
            log.reset()
            let app = PerfRun.launch(log: log)
            XCTAssertTrue(app.buttons["Open a repository\u{2026}"].waitForExistence(timeout: 10))
            samples += log.wait(for: "launch", count: 1)
            let steps = ["launch.model.start", "launch.model.end", "launch.will", "launch.did", "launch.appear", "launch"].map { name in name + " " + PerfReport.format(log.entries(name).first?.value ?? 0) }
            print("PERF launch steps: " + steps.joined(separator: ", "))
            app.terminate()
        }
        let warm = Array(samples.dropFirst())
        PerfReport.add("Launch to Welcome window", warm, budget: 400, unit: "ms", note: "process start to first Welcome frame, median of \(warm.count) warm launches, first launch \(PerfReport.format(samples.first ?? 0)) ms")
        XCTAssertLessThan(PerfReport.median(warm), 400)
    }

    @MainActor
    func testHistoryListHasNoAuditIssues() throws {
        let log = PerfLogFile("audit")
        log.reset()
        let app = PerfRun.launch(log: log, open: Sandbox.fixture("everyday"))
        let commits = app.descendants(matching: .any)["commits"]
        XCTAssertTrue(commits.waitForExistence(timeout: 20))
        _ = log.wait(for: "open", count: 1)
        let area = commits.frame.insetBy(dx: -1, dy: -1)
        var issues: [String] = []
        try app.performAccessibilityAudit(for: .all) { issue in
            if let element = issue.element, area.contains(element.frame) {
                issues.append(issue.compactDescription + ": " + element.label)
            }
            return true
        }
        PerfRun.attach(self, app, "perf-audit")
        app.terminate()
        XCTAssertEqual(issues, [])
    }

    @MainActor
    func testOpenLargeToFirstRows() throws {
        let log = PerfLogFile("open")
        var direct: [Double] = []
        for _ in 0..<3 {
            log.reset()
            let app = PerfRun.launch(log: log, open: PerfRun.large)
            XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 20))
            direct += log.wait(for: "open", count: 1)
            app.terminate()
        }
        var clicked: [Double] = []
        for _ in 0..<3 {
            log.reset()
            let app = PerfRun.launch(log: log)
            let recent = app.descendants(matching: .any)["recent-monorepo"]
            XCTAssertTrue(recent.waitForExistence(timeout: 10))
            recent.click()
            XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 20))
            clicked += log.wait(for: "open", count: 1)
            app.terminate()
        }
        Sandbox.forgetRecent(PerfRun.large)
        PerfReport.add("Open large to first history rows and status", clicked, budget: 500, unit: "ms", note: "click on the recent row to rows drawn, median of \(clicked.count); with -VraiOpen at launch \(PerfReport.format(PerfReport.median(direct))) ms")
        XCTAssertLessThan(PerfReport.median(clicked), 500)
    }

    @MainActor
    func testScrollTenThousandRowsOfLarge() throws {
        let run = scrollLarge(log: PerfLogFile("scroll"))
        PerfReport.add("History scrolling, 10,000 rows of large", [run.slow], budget: 0, unit: "frames over 8.3 ms", inclusive: true, note: run.note)
        PerfReport.add("Memory with large open", [run.memory], budget: 400, unit: "MB", note: "phys_footprint after opening and scrolling 10,000 rows")
        XCTAssertGreaterThanOrEqual(run.rows, 10_000)
        XCTAssertEqual(run.slow, 0)
        XCTAssertEqual(run.dropped, 0)
        XCTAssertLessThan(run.memory, 400)
    }

    struct ScrollRun {
        var slow: Double
        var dropped: Double
        var frames: Double
        var rows: Double
        var memory: Double
        var note: String
    }

    @MainActor
    func scrollLarge(log: PerfLogFile) -> ScrollRun {
        log.reset()
        let app = PerfRun.launch(log: log, open: PerfRun.large)
        let commits = app.descendants(matching: .any)["commits"]
        XCTAssertTrue(commits.waitForExistence(timeout: 20))
        _ = log.wait(for: "open", count: 1)
        Thread.sleep(forTimeInterval: 1)
        let target = Double(10_000) * PerfRun.rowHeight
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        var direction: CGFloat = -1
        var calls = 0
        let started = Date()
        measure(metrics: [XCTHitchMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            let start = log.total("scroll", key: "points")
            let deadline = Date().addingTimeInterval(300)
            while log.total("scroll", key: "points") - start < target, Date() < deadline {
                commits.scroll(byDeltaX: 0, deltaY: direction * PerfRun.scrollStep)
                calls += 1
                Thread.sleep(forTimeInterval: 0.6)
            }
            direction = -direction
        }
        Thread.sleep(forTimeInterval: 0.8)
        PerfRun.attach(self, app, log.name + "-end")
        let sessions = log.entries("scroll")
        let dropped = sessions.reduce(0) { $0 + $1.value }
        let frames = sessions.reduce(0) { $0 + (Double($1.fields["frames"] ?? "") ?? 0) }
        let points = sessions.reduce(0) { $0 + (Double($1.fields["points"] ?? "") ?? 0) }
        let hz = sessions.compactMap { Double($0.fields["hz"] ?? "") }.max() ?? 0
        let worst = sessions.compactMap { Double($0.fields["worst"] ?? "") }.max() ?? 0
        let slow = sessions.reduce(0) { $0 + (Double($1.fields["slow120"] ?? "") ?? 0) }
        let passes = sessions.reduce(0) { $0 + (Double($1.fields["passes"] ?? "") ?? 0) }
        let worstPass = sessions.compactMap { Double($0.fields["worstpass"] ?? "") }.max() ?? 0
        let memory = log.entries("memory").map(\.value).max() ?? 0
        let seconds = Date().timeIntervalSince(started)
        app.terminate()
        let note = "main-thread frame work over the 120 Hz budget in \(Int(slow)) of \(Int(passes)) scrolling frames (worst \(PerfReport.format(worstPass)) ms); display at \(Int(hz)) Hz dropped \(Int(dropped)) of \(Int(frames)) frames (worst interval \(PerfReport.format(worst)) ms); \(Int(points / PerfRun.rowHeight)) rows in \(calls) scroll gestures over \(Int(seconds)) s"
        return ScrollRun(slow: slow, dropped: dropped, frames: frames, rows: points / PerfRun.rowHeight, memory: memory, note: note)
    }

    @MainActor
    func testSelectCommitAndLargeDiff() throws {
        let log = PerfLogFile("select")
        log.reset()
        let app = PerfRun.launch(log: log, open: PerfRun.large)
        XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 20))
        _ = log.wait(for: "open", count: 1)
        let big = PerfRun.row(app, "Generated: add the lexer tables")
        let other = PerfRun.row(app, "Module22: refactor patch builder")
        XCTAssertTrue(big.waitForExistence(timeout: 10))
        XCTAssertTrue(other.waitForExistence(timeout: 10))
        let window = app.windows.firstMatch
        let origin = window.frame.origin
        let targets = [other, big].map { row in
            window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: row.frame.midX - origin.x, dy: row.frame.midY - origin.y))
        }
        for _ in 0..<6 {
            for target in targets {
                let count = log.entries("diff").count
                target.click()
                _ = log.wait(for: "diff", count: count + 1)
            }
        }
        let selects = log.entries("select-commit").map(\.value)
        let diffs = log.entries("diff").filter { (Int($0.detail ?? "") ?? 0) >= 5000 }.map(\.value)
        PerfRun.attach(self, app, "perf-large-diff")
        PerfReport.add("Select a commit to file list shown (large)", Array(selects.dropFirst()), budget: 100, unit: "ms", note: "click to file rows drawn, median of \(selects.count - 1)")
        PerfReport.add("Diff of a 5,000-line file, first lines", diffs, budget: 100, unit: "ms", note: "file selected to first diff lines drawn, median of \(diffs.count)")
        XCTAssertLessThan(PerfReport.median(Array(selects.dropFirst())), 100)
        XCTAssertLessThan(PerfReport.median(diffs), 100)
        app.terminate()
    }

    @MainActor
    func testStageFilesAndLinesInLarge() throws {
        let copy = try PerfCopy.make("large", repository: "monorepo")
        addTeardownBlock { copy.remove() }
        let log = PerfLogFile("stage")
        log.reset()
        let app = PerfRun.launch(log: log, open: copy.repo)
        XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 20))
        _ = log.wait(for: "open", count: 1)
        ChangesFixtureCopy.openChanges(app)
        let path = "Sources/Module03/Area1/File04.swift"
        for _ in 0..<5 {
            let stage = app.descendants(matching: .any)["stage-unstaged-" + path]
            XCTAssertTrue(stage.waitForExistence(timeout: 10))
            let staged = log.entries("action.stage").count
            stage.click()
            XCTAssertTrue(app.descendants(matching: .any)["change-row-staged-" + path].waitForExistence(timeout: 10))
            _ = log.wait(for: "action.stage", count: staged + 1)
            let unstage = app.descendants(matching: .any)["stage-staged-" + path]
            XCTAssertTrue(unstage.waitForExistence(timeout: 10))
            let unstaged = log.entries("action.unstage").count
            unstage.click()
            XCTAssertTrue(app.descendants(matching: .any)["change-row-unstaged-" + path].waitForExistence(timeout: 10))
            _ = log.wait(for: "action.unstage", count: unstaged + 1)
        }
        let files = log.entries("action.stage").map(\.value) + log.entries("action.unstage").map(\.value)
        let row = app.descendants(matching: .any)["change-row-unstaged-" + path]
        row.click()
        var lines: [Double] = []
        for _ in 0..<3 {
            let gutter = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "gutter-", "local edit")).firstMatch
            XCTAssertTrue(gutter.waitForExistence(timeout: 10))
            gutter.click()
            let before = log.entries("action.stage").count
            let button = app.buttons["Stage 1 line"]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.click()
            lines += [log.wait(for: "action.stage", count: before + 1).last ?? 0]
            XCTAssertTrue(app.descendants(matching: .any)["change-row-staged-" + path].waitForExistence(timeout: 10))
            let unstage = app.descendants(matching: .any)["stage-staged-" + path]
            let unstaged = log.entries("action.unstage").count
            unstage.click()
            _ = log.wait(for: "action.unstage", count: unstaged + 1)
            let back = app.descendants(matching: .any)["change-row-unstaged-" + path]
            XCTAssertTrue(back.waitForExistence(timeout: 10))
            back.click()
        }
        PerfRun.attach(self, app, "perf-stage")
        PerfReport.add("Stage or unstage a file, UI updated (large)", files, budget: 100, unit: "ms", note: "click to the row moving groups, median of \(files.count)")
        PerfReport.add("Stage lines, UI updated (large)", lines, budget: 100, unit: "ms", note: "click on Stage 1 line to the staged row drawn, median of \(lines.count)")
        XCTAssertLessThan(PerfReport.median(files), 100)
        XCTAssertLessThan(PerfReport.median(lines), 100)
        app.terminate()
    }

    @MainActor
    func testStatusRefreshAfterAnOutsideChange() throws {
        let copy = try ChangesFixtureCopy.everyday()
        addTeardownBlock { copy.remove() }
        let log = PerfLogFile("refresh")
        log.reset()
        let app = PerfRun.launch(log: log, open: copy.repo)
        XCTAssertTrue(app.descendants(matching: .any)["commits"].waitForExistence(timeout: 20))
        _ = log.wait(for: "open", count: 1)
        ChangesFixtureCopy.openChanges(app)
        Thread.sleep(forTimeInterval: 1)
        var endToEnd: [Double] = []
        for index in 0..<6 {
            let name = "outside-\(index).txt"
            let before = log.entries("refresh.outside").count
            let started = Date()
            try Data("outside change \(index)\n".utf8).write(to: URL(filePath: copy.repo + "/" + name))
            XCTAssertTrue(app.descendants(matching: .any)["change-row-untracked-" + name].waitForExistence(timeout: 10))
            endToEnd.append(Date().timeIntervalSince(started) * 1000)
            _ = log.wait(for: "refresh.outside", count: before + 1)
            Thread.sleep(forTimeInterval: 0.6)
        }
        let refreshes = log.entries("refresh.outside").map(\.value)
        PerfReport.add("Status refresh after an outside change (everyday)", refreshes, budget: 150, unit: "ms", note: "watcher event to the new row drawn, median of \(refreshes.count); file write to row seen by the test \(PerfReport.format(PerfReport.median(endToEnd))) ms including the 300 ms debounce")
        XCTAssertLessThan(PerfReport.median(refreshes), 150)
        app.terminate()
    }
}

struct PerfEntry {
    let name: String
    let value: Double
    let detail: String?

    var fields: [String: String] {
        var out: [String: String] = [:]
        for part in (detail ?? "").split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            out[String(pair[0])] = String(pair[1]).replacingOccurrences(of: "ms", with: "")
        }
        return out
    }
}

struct PerfLogFile {
    let name: String
    let path: String

    init(_ name: String) {
        self.name = name
        path = Sandbox.root + "/perf/" + name + ".log"
    }

    func reset() {
        try? FileManager.default.createDirectory(atPath: Sandbox.root + "/perf", withIntermediateDirectories: true)
        try? FileManager.default.removeItem(atPath: path)
    }

    func entries(_ name: String) -> [PerfEntry] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 2)
            guard parts.count >= 2, parts[0] == name, let value = Double(parts[1]) else { return nil }
            return PerfEntry(name: name, value: value, detail: parts.count > 2 ? String(parts[2]) : nil)
        }
    }

    func total(_ name: String, key: String) -> Double {
        entries(name).reduce(0) { $0 + (Double($1.fields[key] ?? "") ?? 0) }
    }

    func wait(for name: String, count: Int, timeout: TimeInterval = 15) -> [Double] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let found = entries(name)
            if found.count >= count { return found.map(\.value) }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTFail("No \(name) entry in the perf log")
        return entries(name).map(\.value)
    }
}

enum PerfRun {
    static let large = Sandbox.root + "/fixtures/large/monorepo"
    static let rowHeight: Double = 28
    static let scrollStep: CGFloat = 3000

    @MainActor
    static func launch(log: PerfLogFile, open: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = [
            "-VraiSandbox", Sandbox.root,
            "-VraiAppearance", "light",
            "-VraiNow", Sandbox.now,
            "-VraiWindowSize", "1200x780",
            "-VraiCapture", "YES",
            "-ApplePersistenceIgnoreState", "YES",
            "-VraiPerfLog", log.path
        ]
        if let open { arguments += ["-VraiOpen", open] }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    @MainActor
    static func row(_ app: XCUIApplication, _ subject: String) -> XCUIElement {
        app.descendants(matching: .any)["commits"].descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", subject)).firstMatch
    }

    @MainActor
    static func attach(_ test: XCTestCase, _ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        test.add(shot)
    }
}

struct PerfCopy {
    let folder: String
    let repo: String

    static func make(_ scenario: String, repository: String) throws -> PerfCopy {
        let folder = Sandbox.root + "/tests/" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let source = Sandbox.root + "/fixtures/" + scenario
        let target = folder + "/" + scenario
        try FileManager.default.copyItem(atPath: source, toPath: target)
        let copy = PerfCopy(folder: folder, repo: target + "/" + repository)
        _ = try Sandbox.git(["update-index", "--refresh", "-q"], in: copy.repo)
        return copy
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: folder)
        Sandbox.forgetRecent(repo)
    }
}

enum PerfReport {
    static let path = Sandbox.root + "/perf/ui-budgets.txt"

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return .infinity }
        let sorted = values.sorted()
        return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }

    static var load: String {
        var samples = [Double](repeating: 0, count: 3)
        return getloadavg(&samples, 3) > 0 ? format(samples[0]) : "-"
    }

    static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static func add(_ what: String, _ values: [Double], budget: Double, unit: String, inclusive: Bool = false, note: String) {
        let value = median(values)
        let pass = inclusive ? value <= budget : value < budget
        let range = values.isEmpty ? "-" : format(values.min() ?? 0) + " to " + format(values.max() ?? 0)
        let line = [what, format(value) + " " + unit, (inclusive ? "at most " : "under ") + format(budget) + " " + unit, pass ? "pass" : "FAIL", "range " + range + "; " + note + "; load " + load].joined(separator: " | ") + "\n"
        print("PERF " + line, terminator: "")
        try? FileManager.default.createDirectory(atPath: Sandbox.root + "/perf", withIntermediateDirectories: true)
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: URL(filePath: path))
        }
    }
}
