import Foundation

public struct HighlightToken: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case keyword
        case string
        case number
        case comment
        case type
        case function
        case attribute
    }

    public var text: String
    public var kind: Kind?

    public init(_ text: String, _ kind: Kind? = nil) {
        self.text = text
        self.kind = kind
    }
}

public enum SyntaxHighlighter {
    static let swiftKeywords = Set("actor any as associatedtype async await break case catch class continue default defer deinit do else enum extension fallthrough false fileprivate for func guard if import in init inout internal is let mutating nil nonisolated open operator override private protocol public repeat rethrows return self Self some static struct subscript super switch throw throws true try typealias var weak where while".split(separator: " ").map(String.init))
    static let jsKeywords = Set("async await break case catch class const continue default delete do else export extends false finally for from function if import in instanceof let new null of return static super switch this throw true try typeof undefined var void while yield".split(separator: " ").map(String.init))

    public static func language(for path: String) -> String {
        let ext = path.firstMatch(of: #/\.([A-Za-z0-9]+)$/#).map { String($0.output.1).lowercased() } ?? ""
        switch ext {
        case "swift": return "swift"
        case "js", "mjs", "jsx", "json": return "js"
        case "ts", "tsx": return "ts"
        case "md": return "md"
        case "yml", "yaml": return "yaml"
        case "sh": return "sh"
        default: return "text"
        }
    }

    public static func fileSymbol(for path: String) -> String {
        let ext = path.firstMatch(of: #/\.([A-Za-z0-9]+)$/#).map { String($0.output.1).lowercased() } ?? ""
        if ext == "swift" { return "swift" }
        if ["png", "jpg", "jpeg", "gif", "svg", "webp", "icns", "pdf"].contains(ext) { return "photo" }
        if ["json", "yml", "yaml", "toml", "plist", "js", "ts", "mjs", "jsx", "tsx", "c", "h", "m", "sh"].contains(ext) { return "curlybraces" }
        if ["md", "txt", "rtf"].contains(ext) { return "doc.text" }
        return "doc"
    }

    static func isWord(_ c: Unicode.Scalar) -> Bool {
        (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9") || c == "_"
    }

    static func isIdentStart(_ c: Unicode.Scalar) -> Bool {
        (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_"
    }

    static func isDigit(_ c: Unicode.Scalar) -> Bool { c >= "0" && c <= "9" }

    static func isSpace(_ c: Unicode.Scalar) -> Bool {
        switch c.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
        default: false
        }
    }

    static func isLineTerminator(_ c: Unicode.Scalar) -> Bool {
        c == "\n" || c == "\r" || c.value == 0x2028 || c.value == 0x2029
    }

    public static func highlight(_ text: String, language: String?) -> [HighlightToken] {
        guard let language, language != "text", language != "md" else { return [HighlightToken(text)] }
        let keywords = language == "js" || language == "ts" ? jsKeywords : swiftKeywords
        let s = Array(text.unicodeScalars)
        var out: [HighlightToken] = []
        var i = 0

        func str(_ range: Range<Int>) -> String {
            var v = String.UnicodeScalarView()
            v.append(contentsOf: s[range])
            return String(v)
        }
        func restHasNoTerminator(from start: Int) -> Bool {
            !s[start...].contains(where: isLineTerminator)
        }
        func boundary(_ p: Int) -> Bool {
            let before = p > 0 && isWord(s[p - 1])
            let after = p < s.count && isWord(s[p])
            return before != after
        }

        while i < s.count {
            let c = s[i]
            if c == "/", i + 1 < s.count, s[i + 1] == "/", restHasNoTerminator(from: i) {
                out.append(HighlightToken(str(i..<s.count), .comment))
                i = s.count
                continue
            }
            if c == "#", restHasNoTerminator(from: i) {
                if language != "yaml" && language != "sh" {
                    out.append(HighlightToken("#"))
                    i += 1
                } else {
                    out.append(HighlightToken(str(i..<s.count), .comment))
                    i = s.count
                }
                continue
            }
            if c == "/", i + 1 < s.count, s[i + 1] == "*" {
                var j = i + 2
                var end: Int?
                while j + 1 < s.count, !isLineTerminator(s[j]) {
                    if s[j] == "*", s[j + 1] == "/" { end = j + 2; break }
                    j += 1
                }
                if let end {
                    out.append(HighlightToken(str(i..<end), .comment))
                    i = end
                    continue
                }
            }
            if c == "\"" || c == "'" || c == "`" {
                var j = i + 1
                var end: Int?
                while j < s.count {
                    if s[j] == "\\" {
                        if j + 1 < s.count, !isLineTerminator(s[j + 1]) { j += 2; continue }
                        break
                    }
                    if s[j] == c { end = j + 1; break }
                    j += 1
                }
                if let end {
                    out.append(HighlightToken(str(i..<end), .string))
                    i = end
                    continue
                }
            }
            if c == "@", i + 1 < s.count, isIdentStart(s[i + 1]) {
                var j = i + 2
                while j < s.count, isWord(s[j]) { j += 1 }
                out.append(HighlightToken(str(i..<j), .attribute))
                i = j
                continue
            }
            if isDigit(c), boundary(i) {
                var j = i + 1
                while j < s.count, isDigit(s[j]) || s[j] == "_" || s[j] == "." { j += 1 }
                var end: Int?
                var k = j
                while k > i {
                    if boundary(k) { end = k; break }
                    k -= 1
                }
                if let end {
                    out.append(HighlightToken(str(i..<end), .number))
                    i = end
                    continue
                }
            }
            if isIdentStart(c) {
                var j = i + 1
                while j < s.count, isWord(s[j]) { j += 1 }
                let word = str(i..<j)
                var k = j
                while k < s.count, isSpace(s[k]) { k += 1 }
                let callsNext = k < s.count && s[k] == "("
                if keywords.contains(word) {
                    out.append(HighlightToken(word, .keyword))
                } else if let first = word.unicodeScalars.first, first >= "A" && first <= "Z" {
                    out.append(HighlightToken(word, .type))
                } else if callsNext {
                    out.append(HighlightToken(word, .function))
                } else {
                    out.append(HighlightToken(word))
                }
                i = j
                continue
            }
            if isSpace(c) {
                var j = i + 1
                while j < s.count, isSpace(s[j]) { j += 1 }
                out.append(HighlightToken(str(i..<j)))
                i = j
                continue
            }
            out.append(HighlightToken(str(i..<(i + 1))))
            i += 1
        }
        var merged: [HighlightToken] = []
        for token in out {
            if let last = merged.last, last.kind == nil, token.kind == nil {
                merged[merged.count - 1].text += token.text
            } else {
                merged.append(token)
            }
        }
        return merged
    }
}
