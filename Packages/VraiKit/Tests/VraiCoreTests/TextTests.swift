import Foundation
import Testing
@testable import VraiCore

struct TextGoldenTests {
    static var goldens: [String: Any] {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/util-goldens.json")
        return (try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]) ?? [:]
    }

    @Test func pluralMatchesJavaScript() throws {
        let cases = try #require(Self.goldens["plural"] as? [[String: Any]])
        #expect(cases.count == 15)
        for entry in cases {
            let count = entry["count"] as? Int ?? 0
            let word = entry["word"] as? String ?? ""
            let plural = entry["plural"] as? String
            #expect(n(count, word, plural) == entry["out"] as? String, "\(count) \(word)")
        }
    }

    @Test func agoMatchesJavaScript() throws {
        let now = Date(timeIntervalSince1970: try #require(Self.goldens["now"] as? Double))
        let utc = try #require(TimeZone(identifier: "UTC"))
        let cases = try #require(Self.goldens["ago"] as? [[String: Any]])
        #expect(cases.count == 27)
        for entry in cases {
            let seconds = entry["seconds"] as? Double ?? 0
            let date = now.addingTimeInterval(-seconds)
            #expect(RelativeDate.ago(date, now: now, timeZone: utc) == entry["out"] as? String, "\(seconds)s")
        }
    }

    @Test func highlightMatchesJavaScript() throws {
        let cases = try #require(Self.goldens["highlight"] as? [[String: Any]])
        #expect(cases.count == 20)
        for entry in cases {
            let text = entry["text"] as? String ?? ""
            let lang = entry["lang"] as? String
            let expected = (entry["out"] as? [[String: Any]] ?? []).map { HighlightToken($0["t"] as? String ?? "", ($0["k"] as? String).flatMap(HighlightToken.Kind.init(rawValue:))) }
            #expect(SyntaxHighlighter.highlight(text, language: lang) == expected, "\(lang ?? "-"): \(text)")
        }
    }

    @Test func pathHelpersMatchJavaScript() throws {
        let cases = try #require(Self.goldens["paths"] as? [[String: Any]])
        for entry in cases {
            let path = entry["path"] as? String ?? ""
            #expect(SyntaxHighlighter.language(for: path) == entry["lang"] as? String, "\(path)")
            #expect(SyntaxHighlighter.fileSymbol(for: path) == entry["icon"] as? String, "\(path)")
            #expect(PathParts.split(path) == (entry["split"] as? [String]).map { PathParts(directory: $0[0], name: $0[1]) }, "\(path)")
        }
    }
}
