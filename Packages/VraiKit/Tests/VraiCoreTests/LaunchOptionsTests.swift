import Foundation
import Testing
@testable import VraiCore

struct LaunchOptionsTests {
    @Test func parsesAllFourHooks() {
        let options = LaunchOptions(arguments: [
            "/Applications/Vrai.app/Contents/MacOS/Vrai",
            "-VraiSandbox", "/tmp/vrai-sandbox",
            "-VraiOpen", "/tmp/vrai-sandbox/fixtures/everyday/vrai",
            "-VraiAppearance", "dark",
            "-VraiNow", "1791720000"
        ])
        #expect(options.sandbox?.path(percentEncoded: false).hasSuffix("vrai-sandbox/") == true)
        #expect(options.open?.lastPathComponent == "vrai")
        #expect(options.appearance == .dark)
        #expect(options.now == Date(timeIntervalSince1970: 1_791_720_000))
        #expect(options.isSandboxed)
    }

    @Test func ignoresUnknownArgumentsAndMissingValues() {
        let options = LaunchOptions(arguments: ["Vrai", "-NSDocumentRevisionsDebugMode", "YES", "-VraiAppearance", "sepia", "-VraiNow"])
        #expect(options == LaunchOptions())
        #expect(!options.isSandboxed)
    }

    @Test func sandboxDefaultsLiveUnderTheSandbox() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "vrai-launch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let defaults = LaunchOptions(sandbox: dir).makeDefaults()
        defaults.set("dark", forKey: "theme")
        #expect(defaults.synchronize())
        let plist = dir.appending(path: "\(LaunchOptions.sandboxSuiteName).plist")
        #expect(FileManager.default.fileExists(atPath: plist.path(percentEncoded: false)))
        #expect(LaunchOptions(sandbox: dir).recentsFile?.lastPathComponent == "recents.json")
    }
}
