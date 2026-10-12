import Foundation
import Testing
@testable import VraiCore

struct UpdateFeedTests {
    static let key = Data(repeating: 7, count: 32).base64EncodedString()
    static let feed = "https://updates.example.com/vrai/appcast.xml"

    @Test func acceptsAnHTTPSFeedAndA32ByteKey() throws {
        let feed = try #require(UpdateFeed(info: ["SUFeedURL": Self.feed, "SUPublicEDKey": Self.key], arguments: ["Vrai"]))
        #expect(feed.url.absoluteString == Self.feed)
        #expect(feed.publicKey == Self.key)
    }

    @Test func emptyBuildSettingsMeanNoUpdater() {
        #expect(UpdateFeed(info: ["SUFeedURL": "", "SUPublicEDKey": ""], arguments: ["Vrai"]) == nil)
        #expect(UpdateFeed(info: [:], arguments: ["Vrai"]) == nil)
        #expect(UpdateFeed(info: ["SUFeedURL": "$(VRAI_FEED_URL)", "SUPublicEDKey": "$(VRAI_PUBLIC_ED_KEY)"], arguments: ["Vrai"]) == nil)
    }

    @Test func rejectsInsecureFeedsAndMalformedKeys() {
        #expect(UpdateFeed(info: ["SUFeedURL": "http://updates.example.com/appcast.xml", "SUPublicEDKey": Self.key], arguments: []) == nil)
        #expect(UpdateFeed(info: ["SUFeedURL": "https://", "SUPublicEDKey": Self.key], arguments: []) == nil)
        #expect(UpdateFeed(info: ["SUFeedURL": Self.feed, "SUPublicEDKey": "not a key"], arguments: []) == nil)
        #expect(UpdateFeed(info: ["SUFeedURL": Self.feed, "SUPublicEDKey": Data(count: 16).base64EncodedString()], arguments: []) == nil)
    }

    @Test func neverStartsInTheSandbox() {
        let info = ["SUFeedURL": Self.feed, "SUPublicEDKey": Self.key]
        #expect(UpdateFeed(info: info, arguments: ["Vrai", "-VraiSandbox", "/tmp/vrai-sandbox"]) == nil)
    }
}
