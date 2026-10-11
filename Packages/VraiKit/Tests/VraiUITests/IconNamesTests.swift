import AppKit
import Foundation
import Testing

struct IconNamesTests {
    static let kitRoot = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let vraiRoot = kitRoot.deletingLastPathComponent().deletingLastPathComponent()

    static func allowedNames() throws -> Set<String> {
        let url = try #require(Bundle.module.url(forResource: "icons", withExtension: "json", subdirectory: "Resources"))
        let rows = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String]])
        return Set(rows.compactMap(\.first))
    }

    static func swiftSources() -> [URL] {
        let roots = [kitRoot.appending(path: "Sources"), vraiRoot.appending(path: "App"), vraiRoot.appending(path: "Helpers")]
        var files: [URL] = []
        for root in roots {
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                files.append(url)
            }
        }
        return files
    }

    static func literals(in text: String) -> [(label: String?, value: String)] {
        let pattern = /(?:(systemName|systemImage|icon)\s*:\s*)?"([^"\\\n]*)"/
        return text.matches(of: pattern).map { (label: $0.output.1.map(String.init), value: String($0.output.2)) }
    }

    @Test func iconListIsComplete() throws {
        #expect(try Self.allowedNames().count == 141)
    }

    @Test func everySymbolInSourceIsInIconsJSON() throws {
        let allowed = try Self.allowedNames()
        let sources = Self.swiftSources()
        #expect(!sources.isEmpty)
        var offenders: [String] = []
        for file in sources {
            let text = try String(contentsOf: file, encoding: .utf8)
            for literal in Self.literals(in: text) {
                let looksLikeSymbol = literal.label != nil
                    || (literal.value.contains(".") && literal.value.wholeMatch(of: /[a-z0-9]+(\.[a-z0-9]+)+/) != nil
                        && NSImage(systemSymbolName: literal.value, accessibilityDescription: nil) != nil)
                if looksLikeSymbol, !literal.value.isEmpty, !allowed.contains(literal.value) {
                    offenders.append("\(file.lastPathComponent): \(literal.value)")
                }
            }
        }
        #expect(offenders.isEmpty, "Symbols not in icons.json: \(offenders)")
    }

    @Test func everyAllowedNameIsARealSymbol() throws {
        let missing = try Self.allowedNames().filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        #expect(missing.isEmpty, "Not SF Symbols on this system: \(missing.sorted())")
    }
}
