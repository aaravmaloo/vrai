import Foundation
import Testing
@testable import VraiUI

struct TokensSyncTests {
    static let designSystemTokens = IconNamesTests.vraiRoot.appending(path: "prototype_ui/design-system/project/assets/SwiftUI/VraiTokens.swift")

    @Test(.enabled(if: FileManager.default.fileExists(atPath: designSystemTokens.path(percentEncoded: false)), "prototype_ui is not checked in"))
    func tokensMatchTheDesignSystem() throws {
        let kit = IconNamesTests.kitRoot
        let synced = try String(contentsOf: kit.appending(path: "Sources/VraiUI/Tokens/VraiTokens.swift"), encoding: .utf8)
        let source = try String(contentsOf: Self.designSystemTokens, encoding: .utf8)
        #expect(synced == source, "Run Vrai/Scripts/sync-design-system.sh")
    }

    @Test func sidebarWidthComesFromTokens() {
        #expect(Vrai.Size.sidebar == 248)
        #expect(Vrai.Size.toolbar == 52)
    }
}
