import Foundation
import Testing

struct CopyRulesTests {
    static func copy() throws -> [(file: String, text: String)] {
        let roots = [IconNamesTests.kitRoot.appending(path: "Sources/VraiUI"), IconNamesTests.kitRoot.appending(path: "Sources/VraiCore")]
        let pattern = /(?:String\(localized:\s*|Text\()"((?:[^"\\\n]|\\.)*)"/
        var out: [(file: String, text: String)] = []
        for root in roots {
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let source = try String(contentsOf: url, encoding: .utf8)
                for match in source.matches(of: pattern) {
                    out.append((url.lastPathComponent, prose(String(match.output.1))))
                }
            }
        }
        return out
    }

    static func prose(_ text: String) -> String {
        var out = ""
        var depth = 0
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            if depth == 0, text[index] == "\\", next < text.endIndex, text[next] == "(" {
                depth = 1
                index = text.index(after: next)
                continue
            }
            if depth > 0 {
                if text[index] == "(" { depth += 1 }
                if text[index] == ")" { depth -= 1 }
            } else {
                out.append(text[index])
            }
            index = next
        }
        return out
    }

    @Test func copyIsFound() throws {
        #expect(try Self.copy().count > 1500)
    }

    @Test func noExclamationMarks() throws {
        let gitWords = ["fixup!", "squash!", "amend!"]
        let offenders = try Self.copy().filter { entry in
            var text = entry.text
            for word in gitWords { text = text.replacingOccurrences(of: word, with: "") }
            return text.contains("!")
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    @Test func ellipsisIsOneCharacter() throws {
        let offenders = try Self.copy().filter { $0.text.contains("...") }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    @Test func noDashesBetweenWords() throws {
        let offenders = try Self.copy().filter { $0.text.contains("\u{2014}") || $0.text.contains("\u{2013}") || $0.text.contains(" - ") }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    @Test func noApologiesVagueButtonsOrFirstPerson() throws {
        let banned = [/\bOK\b/, /\b[Ss]orry\b/, /\bOops\b/, /\b[Pp]lease\b/, /\bSuccess/, /\bSubmit\b/, /\bI\b/, /\bI'm\b/, /\b[Ww]e\b/, /\bour\b/, /^Error:/, /^Warning:/]
        let offenders = try Self.copy().filter { entry in banned.contains { entry.text.contains($0) } }
        #expect(offenders.isEmpty, "\(offenders)")
    }
}
