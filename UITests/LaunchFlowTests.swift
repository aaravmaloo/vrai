import XCTest

final class LaunchFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-VraiSandbox", Sandbox.root, "-VraiAppearance", appearance, "-VraiNow", Sandbox.now, "-VraiCapture", "YES", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        return app
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testWelcomeWindowLight() throws {
        let app = launch(appearance: "light")
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Open a repository\u{2026}"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Recent"].exists)
        attach(app, name: "welcome-light")
        app.terminate()
    }

    @MainActor
    func testWelcomeWindowDark() throws {
        let app = launch(appearance: "dark")
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Open a repository\u{2026}"].waitForExistence(timeout: 5))
        attach(app, name: "welcome-dark")
        app.terminate()
    }

    @MainActor
    func testAppIconInTheDock() throws {
        let app = launch(appearance: "light")
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        let dock = XCUIApplication(bundleIdentifier: "com.apple.dock")
        let item = dock.descendants(matching: .any).matching(NSPredicate(format: "title == %@", "Vrai")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: item.screenshot())
        shot.name = "m0-dock-icon"
        shot.lifetime = .keepAlways
        add(shot)
        app.terminate()
    }
}

enum Sandbox {
    static let root: String = {
        let tmp = NSTemporaryDirectory().hasSuffix("/") ? NSTemporaryDirectory() : NSTemporaryDirectory() + "/"
        return ProcessInfo.processInfo.environment["VRAI_SANDBOX"] ?? tmp + "vrai-sandbox"
    }()

    static let now = "1791720000"

    static func fixture(_ scenario: String) -> String {
        let folder = scenario == "empty" ? "pocket-notes" : "vrai"
        return root + "/fixtures/" + scenario + "/" + folder
    }

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        for key in ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "SSH_AUTH_SOCK"] {
            env.removeValue(forKey: key)
        }
        env["VRAI_SANDBOX"] = root
        env["HOME"] = root + "/home"
        env["XDG_CONFIG_HOME"] = root + "/home/.config"
        env["GIT_CONFIG_GLOBAL"] = root + "/gitconfig"
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_ASKPASS"] = "/usr/bin/false"
        env["SSH_ASKPASS"] = "/usr/bin/false"
        env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes"
        env["GIT_CEILING_DIRECTORIES"] = root
        return env
    }

    static func forgetRecent(_ path: String) {
        let url = URL(filePath: root + "/recents.json")
        guard let data = try? Data(contentsOf: url), var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let list = object["repositories"] as? [[String: Any]] else { return }
        object["repositories"] = list.filter { ($0["path"] as? String) != path }
        guard let updated = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return }
        try? updated.write(to: url, options: .atomic)
    }

    struct Outcome {
        let status: Int32
        let output: String
    }

    static func git(_ arguments: [String], in directory: String) throws -> Outcome {
        let candidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/Applications/Xcode.app/Contents/Developer/usr/bin/git", "/Library/Developer/CommandLineTools/usr/bin/git", "/usr/bin/git"]
        let executable = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/git"
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: executable)
        process.arguments = ["-C", directory] + arguments
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Outcome(status: process.terminationStatus, output: executable + ": " + String(decoding: data, as: UTF8.self))
    }
}
