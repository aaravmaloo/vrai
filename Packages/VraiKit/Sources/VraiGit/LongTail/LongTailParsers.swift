import Foundation

public struct RemoteHeads: Sendable, Hashable {
    public var defaultBranch: String?
    public var branches: [String]

    public init(defaultBranch: String? = nil, branches: [String] = []) {
        self.defaultBranch = defaultBranch
        self.branches = branches
    }
}

public struct Contributor: Sendable, Hashable, Identifiable {
    public var name: String
    public var email: String
    public var commits: Int

    public var id: String { name + " <" + email + ">" }
}

public struct FsckReport: Sendable, Hashable {
    public struct Finding: Sendable, Hashable {
        public var kind: String
        public var type: String
        public var oid: String
    }

    public var dangling: [Finding] = []
    public var missing: [Finding] = []
    public var problems: [String] = []

    public var isHealthy: Bool { missing.isEmpty && problems.isEmpty }
}

public struct ComparedCommit: Sendable, Hashable, Identifiable {
    public enum Side: Sendable, Hashable {
        case left
        case right
    }

    public var id: OID
    public var side: Side
    public var equivalent: Bool
    public var subject: String
    public var author: String
    public var date: Date
}

public struct FileStat: Sendable, Hashable, Identifiable {
    public var path: String
    public var additions: Int?
    public var deletions: Int?

    public var id: String { path }
}

public struct ChangedPath: Sendable, Hashable, Identifiable {
    public var status: String
    public var path: String
    public var oldPath: String?

    public var id: String { path }
}

public struct PatchSummary: Sendable, Hashable, Identifiable {
    public var file: String
    public var subject: String
    public var author: String
    public var email: String

    public var id: String { file + "\u{1}" + subject }
}

public struct SignatureReport: Sendable, Hashable {
    public var good: Bool
    public var signer: String?
    public var keyType: String?
    public var fingerprint: String?
    public var message: String

    public init(good: Bool, signer: String? = nil, keyType: String? = nil, fingerprint: String? = nil, message: String) {
        self.good = good
        self.signer = signer
        self.keyType = keyType
        self.fingerprint = fingerprint
        self.message = message
    }
}

public struct ManualSpan: Sendable, Hashable {
    public enum Style: Sendable, Hashable {
        case plain
        case bold
        case underline
    }

    public var text: String
    public var style: Style
}

public enum LongTailParsers {
    public static func remoteHeads(_ text: String) -> RemoteHeads {
        var heads = RemoteHeads()
        var headOID: String?
        var tips: [String: String] = [:]
        for raw in text.split(separator: "\n") {
            let line = String(raw)
            if line.hasPrefix("ref: ") {
                let parts = line.dropFirst(5).split(separator: "\t")
                if parts.count == 2, parts[1] == "HEAD", parts[0].hasPrefix("refs/heads/") {
                    heads.defaultBranch = String(parts[0].dropFirst("refs/heads/".count))
                }
                continue
            }
            let parts = line.split(whereSeparator: { $0 == "\t" || $0 == " " })
            guard parts.count >= 2 else { continue }
            let oid = String(parts[0])
            let ref = String(parts[1])
            if ref == "HEAD" {
                headOID = oid
            } else if ref.hasPrefix("refs/heads/") {
                let name = String(ref.dropFirst("refs/heads/".count))
                if !heads.branches.contains(name) { heads.branches.append(name) }
                tips[name] = oid
            }
        }
        if heads.defaultBranch == nil, let headOID {
            heads.defaultBranch = ["main", "master", "trunk"].first { tips[$0] == headOID } ?? tips.first { $0.value == headOID }?.key
        }
        heads.branches.sort { lhs, rhs in
            if lhs == heads.defaultBranch { return true }
            if rhs == heads.defaultBranch { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        return heads
    }

    public static func keyValues(_ text: String, separator: Character) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let index = line.firstIndex(of: separator) else { continue }
            let key = line[line.startIndex..<index].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: index)...].trimmingCharacters(in: .whitespaces)
            out[key] = value
        }
        return out
    }

    public static func lastModified(_ data: Data) -> [String: OID] {
        var out: [String: OID] = [:]
        for record in ParseSupport.nulFields(data) where !record.isEmpty {
            let parts = record.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let id = OID(String(parts[0])) else { continue }
            out[String(parts[1])] = id
        }
        return out
    }

    public static func commitDates(_ text: String) -> [OID: (date: Date, subject: String)] {
        var out: [OID: (date: Date, subject: String)] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: "\u{0}", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3, let id = OID(String(fields[0])), let seconds = TimeInterval(String(fields[1])) else { continue }
            out[id] = (Date(timeIntervalSince1970: seconds), String(fields[2]))
        }
        return out
    }

    public static func signature(_ errorOutput: String, exitCode: Int32) -> SignatureReport {
        let text = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = text.firstMatch(of: /Good "git" signature for (.+?) with (\S+) key (\S+)/) {
            return SignatureReport(good: exitCode == 0, signer: String(match.output.1), keyType: String(match.output.2), fingerprint: String(match.output.3), message: text)
        }
        if let match = text.firstMatch(of: /Good signature from "([^"]+)"/) {
            let fingerprint = text.firstMatch(of: /using \S+ key ([0-9A-F]+)/).map { String($0.output.1) }
            return SignatureReport(good: exitCode == 0, signer: String(match.output.1), keyType: "GPG", fingerprint: fingerprint, message: text)
        }
        return SignatureReport(good: false, signer: nil, keyType: nil, fingerprint: nil, message: text)
    }

    public static func nulKeyValues(_ data: Data) -> [String: String] {
        var out: [String: String] = [:]
        for record in ParseSupport.nulFields(data) where !record.isEmpty {
            let parts = record.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            out[String(parts[0])] = String(parts[1])
        }
        return out
    }

    public static func contributors(_ text: String) -> [Contributor] {
        text.split(separator: "\n").compactMap { line in
            guard let match = line.firstMatch(of: /^\s*(\d+)\t(.*?)(?: <([^>]*)>)?$/), let count = Int(match.output.1) else { return nil }
            return Contributor(name: String(match.output.2), email: match.output.3.map(String.init) ?? "", commits: count)
        }
    }

    public static func fsck(stdout: String, stderr: String) -> FsckReport {
        var report = FsckReport()
        for line in (stdout + "\n" + stderr).split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.isEmpty || text.hasPrefix("Checking ") || text.hasPrefix("notice:") { continue }
            let words = text.split(separator: " ")
            if words.count == 3, words[0] == "dangling" || words[0] == "unreachable" {
                report.dangling.append(FsckReport.Finding(kind: String(words[0]), type: String(words[1]), oid: String(words[2])))
            } else if words.count == 3, words[0] == "missing" {
                report.missing.append(FsckReport.Finding(kind: "missing", type: String(words[1]), oid: String(words[2])))
            } else {
                report.problems.append(text)
            }
        }
        return report
    }

    public static func cleanPreview(_ text: String) -> [String] {
        text.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("Would remove ") else { return nil }
            return String(line.dropFirst("Would remove ".count))
        }
    }

    public static func lines(_ text: String) -> [String] {
        text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public static func compared(_ data: Data) -> [ComparedCommit] {
        ParseSupport.records(data, fieldCount: 5).compactMap { record in
            var mark = record[0]
            if mark.hasPrefix("\n") { mark.removeFirst() }
            guard let id = OID(record[1]) else { return nil }
            let side: ComparedCommit.Side = mark == "<" ? .left : .right
            let date = ParseSupport.date(record[4]) ?? Date(timeIntervalSince1970: 0)
            return ComparedCommit(id: id, side: mark == "=" ? .right : side, equivalent: mark == "=", subject: record[2], author: record[3], date: date)
        }
    }

    public static func leftRightCounts(_ text: String) -> (left: Int, right: Int) {
        let parts = text.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        guard parts.count == 2 else { return (0, 0) }
        return (parts[0], parts[1])
    }

    public static func cherryPicked(_ text: String) -> Set<String> {
        Set(text.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("- ") else { return nil }
            return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        })
    }

    public static func numstat(_ data: Data) -> [FileStat] {
        let fields = ParseSupport.nulFields(data)
        var out: [FileStat] = []
        var index = 0
        while index < fields.count {
            var field = fields[index]
            if field.hasPrefix("\n") { field.removeFirst() }
            let parts = field.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3 else {
                index += 1
                continue
            }
            let additions = Int(parts[0])
            let deletions = Int(parts[1])
            var path = String(parts[2])
            if path.isEmpty, index + 2 < fields.count {
                path = fields[index + 2]
                index += 3
            } else {
                index += 1
            }
            out.append(FileStat(path: path, additions: additions, deletions: deletions))
        }
        return out
    }

    public static func changedPaths(_ data: Data) -> [ChangedPath] {
        let fields = ParseSupport.nulFields(data)
        var out: [ChangedPath] = []
        var index = 0
        while index < fields.count {
            var status = fields[index]
            if status.hasPrefix("\n") { status.removeFirst() }
            guard !status.isEmpty else {
                index += 1
                continue
            }
            let letter = String(status.prefix(1))
            if letter == "R" || letter == "C", index + 2 < fields.count {
                out.append(ChangedPath(status: letter, path: fields[index + 2], oldPath: fields[index + 1]))
                index += 3
            } else if index + 1 < fields.count {
                out.append(ChangedPath(status: letter, path: fields[index + 1], oldPath: nil))
                index += 2
            } else {
                index += 1
            }
        }
        return out
    }

    public static func mailinfo(_ text: String, file: String) -> PatchSummary {
        let values = keyValues(text, separator: ":")
        return PatchSummary(file: file, subject: values["Subject"] ?? "", author: values["Author"] ?? "", email: values["Email"] ?? "")
    }

    public static func objectCount(showIndex text: String) -> Int {
        text.split(separator: "\n").count
    }

    public static func manual(_ data: Data) -> [[ManualSpan]] {
        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { manualLine(Array(String($0))) }
    }

    static func manualLine(_ characters: [Character]) -> [ManualSpan] {
        var spans: [ManualSpan] = []
        var index = 0
        func append(_ character: Character, _ style: ManualSpan.Style) {
            if let last = spans.last, last.style == style {
                spans[spans.count - 1].text.append(character)
            } else {
                spans.append(ManualSpan(text: String(character), style: style))
            }
        }
        while index < characters.count {
            let character = characters[index]
            if index + 2 < characters.count, characters[index + 1] == "\u{8}" {
                let shown = characters[index + 2]
                append(shown, character == "_" && shown != "_" ? .underline : .bold)
                index += 3
                while index + 1 < characters.count, characters[index] == "\u{8}" { index += 2 }
                continue
            }
            if character == "\u{8}" {
                index += 1
                continue
            }
            if character.asciiValue == 0x1B {
                index += 1
                while index < characters.count, !(characters[index].isLetter) { index += 1 }
                index += 1
                continue
            }
            append(character, .plain)
            index += 1
        }
        return spans
    }
}
