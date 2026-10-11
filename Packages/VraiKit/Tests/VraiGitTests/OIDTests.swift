import Testing
@testable import VraiGit

struct OIDTests {
    @Test func acceptsSHA1AndSHA256() {
        #expect(OID(String(repeating: "a", count: 40)) != nil)
        #expect(OID(String(repeating: "b", count: 64)) != nil)
    }

    @Test func rejectsOtherLengthsAndCharacters() {
        #expect(OID("abc") == nil)
        #expect(OID(String(repeating: "g", count: 40)) == nil)
        #expect(OID(String(repeating: "a", count: 41)) == nil)
    }

    @Test func lowercasesAndShortens() throws {
        let oid = try #require(OID("E41C9A2" + String(repeating: "0", count: 33)))
        #expect(oid.rawValue.hasPrefix("e41c9a2"))
        #expect(oid.short == "e41c9a2")
        #expect(oid.short(expert: true) == "e41c9a2000")
    }

    @Test func zero() throws {
        #expect(try #require(OID(String(repeating: "0", count: 40))).isZero)
    }
}
