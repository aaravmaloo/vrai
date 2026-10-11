import Foundation

public enum PatchParser {
    public static func parse(_ data: Data, computeWordRanges: Bool = true) -> [FileDiff] {
        parse(ParseSupport.string(data), computeWordRanges: computeWordRanges)
    }

    public static func parse(_ text: String, computeWordRanges: Bool = true) -> [FileDiff] {
        var files: [FileDiff] = []
        var current: FileDiff?
        var hunk: Hunk?
        var oldLine = 0
        var newLine = 0
        var combined = false

        func closeHunk() {
            if let done = hunk {
                current?.hunks.append(computeWordRanges ? WordDiff.annotate(done) : done)
            }
            hunk = nil
        }
        func closeFile() {
            closeHunk()
            if let done = current { files.append(done) }
            current = nil
        }

        let lines = text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false).map { Substring(String(String.UnicodeScalarView($0))) }
        for (position, raw) in lines.enumerated() {
            let line = raw
            if line.hasPrefix("diff --git ") {
                closeFile()
                combined = false
                let paths = headerPaths(String(line.dropFirst("diff --git ".count)))
                current = FileDiff(path: paths.new, oldPath: paths.old == paths.new ? nil : paths.old, status: .modified)
                continue
            }
            if line.hasPrefix("diff --cc ") || line.hasPrefix("diff --combined ") {
                closeFile()
                combined = true
                let path = ParseSupport.unquoteCPath(String(line.split(separator: " ", maxSplits: 2).last ?? ""))
                files.append(FileDiff(path: path, status: .conflicted))
                continue
            }
            if combined { continue }
            if line.hasPrefix("* Unmerged path ") { closeFile(); continue }
            guard current != nil else { continue }

            if hunk != nil {
                if let first = line.unicodeScalars.first, first == " " || first == "+" || first == "-" || first == "\\" {
                    let text = String(String.UnicodeScalarView(line.unicodeScalars.dropFirst()))
                    switch first {
                    case " ":
                        hunk?.lines.append(DiffLine(kind: .context, text: text, oldNumber: oldLine, newNumber: newLine))
                        oldLine += 1
                        newLine += 1
                    case "+":
                        hunk?.lines.append(DiffLine(kind: .add, text: text, newNumber: newLine))
                        newLine += 1
                    case "-":
                        hunk?.lines.append(DiffLine(kind: .del, text: text, oldNumber: oldLine))
                        oldLine += 1
                    default:
                        hunk?.lines.append(DiffLine(kind: .noNewline, text: text.trimmingCharacters(in: .whitespaces)))
                    }
                    continue
                }
                if line.isEmpty, position == lines.count - 1 { continue }
                closeHunk()
            }

            if line.hasPrefix("@@ ") {
                closeHunk()
                guard let match = line.firstMatch(of: #/^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@ ?(.*)$/#) else { continue }
                let oldStart = Int(match.output.1) ?? 0
                let newStart = Int(match.output.3) ?? 0
                hunk = Hunk(header: String(line), oldStart: oldStart, oldCount: match.output.2.flatMap { Int($0) } ?? 1, newStart: newStart, newCount: match.output.4.flatMap { Int($0) } ?? 1, title: String(match.output.5), lines: [])
                oldLine = oldStart
                newLine = newStart
            } else if line.hasPrefix("new file mode ") {
                current?.status = .added
                current?.newMode = String(line.dropFirst("new file mode ".count))
            } else if line.hasPrefix("deleted file mode ") {
                current?.status = .deleted
                current?.oldMode = String(line.dropFirst("deleted file mode ".count))
            } else if line.hasPrefix("old mode ") {
                current?.oldMode = String(line.dropFirst("old mode ".count))
            } else if line.hasPrefix("new mode ") {
                current?.newMode = String(line.dropFirst("new mode ".count))
                let modes = (current?.oldMode, current?.newMode)
                if modes.0 == "120000" || modes.1 == "120000" { current?.status = .typeChanged }
            } else if line.hasPrefix("rename from ") {
                current?.oldPath = ParseSupport.unquoteCPath(String(line.dropFirst("rename from ".count)))
                current?.status = .renamed
            } else if line.hasPrefix("rename to ") {
                current?.path = ParseSupport.unquoteCPath(String(line.dropFirst("rename to ".count)))
                current?.status = .renamed
            } else if line.hasPrefix("copy from ") {
                current?.oldPath = ParseSupport.unquoteCPath(String(line.dropFirst("copy from ".count)))
                current?.status = .copied
            } else if line.hasPrefix("copy to ") {
                current?.path = ParseSupport.unquoteCPath(String(line.dropFirst("copy to ".count)))
                current?.status = .copied
            } else if line.hasPrefix("similarity index ") {
                current?.similarity = Int(line.dropFirst("similarity index ".count).dropLast())
            } else if line.hasPrefix("Binary files ") || line == "GIT binary patch" {
                current?.isBinary = true
            } else if line.hasPrefix("index ") {
                if line.hasSuffix(" 160000") { current?.isSubmodule = true }
            } else if line.hasPrefix("--- ") {
                let path = sidePath(String(line.dropFirst(4)))
                let currentPath = current?.path
                if path == nil { current?.status = .added } else if current?.status != .renamed { current?.oldPath = path == currentPath ? nil : path }
            } else if line.hasPrefix("+++ ") {
                if let path = sidePath(String(line.dropFirst(4))) { current?.path = path } else { current?.status = .deleted }
            } else if line.hasPrefix("Submodule ") {
                current?.isSubmodule = true
            }
        }
        closeFile()
        return mergeTypeChanges(files)
    }

    static func mergeTypeChanges(_ files: [FileDiff]) -> [FileDiff] {
        var out: [FileDiff] = []
        for file in files {
            if let last = out.last, last.path == file.path, last.status == .deleted, file.status == .added,
               last.oldMode == "120000" || file.newMode == "120000" || last.oldMode == "160000" || file.newMode == "160000" {
                var merged = last
                merged.status = .typeChanged
                merged.newMode = file.newMode
                merged.hunks += file.hunks
                merged.isBinary = last.isBinary || file.isBinary
                out[out.count - 1] = merged
            } else {
                out.append(file)
            }
        }
        return out
    }

    static func sidePath(_ raw: String) -> String? {
        var value = raw
        if value.hasSuffix("\t") { value.removeLast() }
        if value == "/dev/null" { return nil }
        value = ParseSupport.unquoteCPath(value)
        if value.hasPrefix("a/") || value.hasPrefix("b/") || value.hasPrefix("i/") || value.hasPrefix("w/") || value.hasPrefix("c/") || value.hasPrefix("o/") { value.removeFirst(2) }
        return value
    }

    static func headerPaths(_ rest: String) -> (old: String, new: String) {
        if rest.hasPrefix("\"") {
            var tokens: [String] = []
            var remaining = Substring(rest)
            while !remaining.isEmpty {
                if remaining.hasPrefix("\"") {
                    var end = remaining.index(after: remaining.startIndex)
                    while end < remaining.endIndex {
                        if remaining[end] == "\\" { end = remaining.index(end, offsetBy: 2, limitedBy: remaining.endIndex) ?? remaining.endIndex; continue }
                        if remaining[end] == "\"" { break }
                        end = remaining.index(after: end)
                    }
                    let stop = end < remaining.endIndex ? remaining.index(after: end) : end
                    tokens.append(ParseSupport.unquoteCPath(String(remaining[..<stop])))
                    remaining = remaining[stop...].drop { $0 == " " }
                } else {
                    let space = remaining.firstIndex(of: " ") ?? remaining.endIndex
                    tokens.append(String(remaining[..<space]))
                    remaining = remaining[space...].drop { $0 == " " }
                }
            }
            let strip = { (s: String) -> String in s.count > 2 && s.dropFirst().first == "/" ? String(s.dropFirst(2)) : s }
            return (strip(tokens.first ?? ""), strip(tokens.last ?? ""))
        }
        let count = rest.count
        if count >= 5, (count - 1) % 2 == 0 {
            let half = (count - 1) / 2
            let a = String(rest.prefix(half))
            let b = String(rest.suffix(half))
            if a.dropFirst(2) == b.dropFirst(2) { return (String(a.dropFirst(2)), String(b.dropFirst(2))) }
        }
        if let range = rest.range(of: " b/") {
            return (String(rest[..<range.lowerBound].dropFirst(2)), String(rest[range.upperBound...]))
        }
        return (rest, rest)
    }
}

public enum WordDiff {
    public static let maximumChangedFraction = 0.7

    public static func annotate(_ hunk: Hunk) -> Hunk {
        var hunk = hunk
        var index = 0
        while index < hunk.lines.count {
            guard hunk.lines[index].kind == .del else { index += 1; continue }
            var delEnd = index
            while delEnd < hunk.lines.count, hunk.lines[delEnd].kind == .del { delEnd += 1 }
            var addEnd = delEnd
            while addEnd < hunk.lines.count, hunk.lines[addEnd].kind == .add { addEnd += 1 }
            let pairs = min(delEnd - index, addEnd - delEnd)
            for offset in 0..<pairs {
                let (old, new) = ranges(hunk.lines[index + offset].text, hunk.lines[delEnd + offset].text)
                hunk.lines[index + offset].wordRanges = old
                hunk.lines[delEnd + offset].wordRanges = new
            }
            index = max(addEnd, index + 1)
        }
        return hunk
    }

    public static func tokens(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        var kind = 0
        for ch in text {
            let k = ch.isLetter || ch.isNumber || ch == "_" ? 1 : (ch.isWhitespace ? 2 : 3)
            if k == 3 || k != kind, !current.isEmpty {
                out.append(current)
                current = ""
            }
            current.append(ch)
            kind = k
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    public static func ranges(_ old: String, _ new: String) -> ([Range<Int>], [Range<Int>]) {
        let a = tokens(old)
        let b = tokens(new)
        guard !a.isEmpty, !b.isEmpty, a.count * b.count <= 250_000 else { return ([], []) }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var keepA = Array(repeating: false, count: a.count)
        var keepB = Array(repeating: false, count: b.count)
        var i = 0
        var j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                keepA[i] = true
                keepB[j] = true
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        let changedA = zip(a, keepA).filter { !$0.1 }.reduce(0) { $0 + $1.0.count }
        let changedB = zip(b, keepB).filter { !$0.1 }.reduce(0) { $0 + $1.0.count }
        if Double(changedA) > Double(old.count) * maximumChangedFraction || Double(changedB) > Double(new.count) * maximumChangedFraction {
            return ([], [])
        }
        return (spans(a, keepA), spans(b, keepB))
    }

    static func spans(_ tokens: [String], _ keep: [Bool]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var offset = 0
        for (token, kept) in zip(tokens, keep) {
            let next = offset + token.count
            if !kept {
                if let last = out.last, last.upperBound == offset { out[out.count - 1] = last.lowerBound..<next } else { out.append(offset..<next) }
            }
            offset = next
        }
        return out
    }
}
