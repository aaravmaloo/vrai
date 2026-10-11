import Foundation

public struct GitProgress: Sendable, Hashable {
    public var phase: String
    public var percent: Int?
    public var current: Int?
    public var total: Int?
    public var detail: String?
    public var done: Bool

    public var fraction: Double? { percent.map { Double($0) / 100 } }
}

public enum ProgressParser {
    public static func parse(_ line: String) -> GitProgress? {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("remote: ") { text = String(text.dropFirst("remote: ".count)).trimmingCharacters(in: .whitespaces) }
        guard let match = text.firstMatch(of: #/^([A-Za-z][A-Za-z ]*?):\s+(\d+)%\s*\((\d+)/(\d+)\)(?:,\s*(.*?))?(?:,\s*done\.)?$/#) else {
            if let count = text.firstMatch(of: #/^([A-Za-z][A-Za-z ]*?):\s+(\d+)(?:,\s*done\.)?$/#) {
                return GitProgress(phase: String(count.output.1), percent: nil, current: Int(count.output.2), total: nil, detail: nil, done: text.hasSuffix("done."))
            }
            return nil
        }
        var detail = match.output.5.map(String.init)
        if let d = detail, d.hasSuffix(", done.") { detail = String(d.dropLast(", done.".count)) }
        if detail == "done." { detail = nil }
        return GitProgress(
            phase: String(match.output.1),
            percent: Int(match.output.2),
            current: Int(match.output.3),
            total: Int(match.output.4),
            detail: detail?.isEmpty == true ? nil : detail,
            done: text.hasSuffix("done.")
        )
    }
}
