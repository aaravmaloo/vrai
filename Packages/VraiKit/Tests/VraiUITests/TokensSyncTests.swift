import Foundation
import Testing
@testable import VraiUI

struct TokensSyncTests {
    @Test func tokensMatchTheDesignSystem() throws {
        let kit = IconNamesTests.kitRoot
        let root = IconNamesTests.vraiRoot
        let synced = try String(contentsOf: kit.appending(path: "Sources/VraiUI/Tokens/VraiTokens.swift"), encoding: .utf8)
        let source = try String(contentsOf: root.appending(path: "prototype_ui/design-system/project/assets/SwiftUI/VraiTokens.swift"), encoding: .utf8)
        #expect(synced == source, "Run Vrai/Scripts/sync-design-system.sh")
    }

    @Test func sidebarWidthComesFromTokens() {
        #expect(Vrai.Size.sidebar == 248)
        #expect(Vrai.Size.toolbar == 52)
    }
}
