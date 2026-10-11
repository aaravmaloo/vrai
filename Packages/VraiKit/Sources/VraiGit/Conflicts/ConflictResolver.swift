import Foundation

public enum ConflictChoice: String, Sendable, Hashable, Codable, CaseIterable {
    case ours
    case theirs
    case both
    case base
}

public enum ConflictResolver {
    public enum Failure: Error, Sendable, Hashable {
        case blockNotFound(Int)
        case noBase(Int)
    }

    struct Located {
        var conflict: ConflictBlock.Conflict
        var ours: Range<Int>
        var base: Range<Int>?
        var theirs: Range<Int>
    }

    struct Document {
        var lines: [String]
        var endsWithNewline: Bool
        var located: [Located]

        init(_ text: String) {
            var lines = text.components(separatedBy: "\n")
            endsWithNewline = lines.last == ""
            if endsWithNewline { lines.removeLast() }
            self.lines = lines
            let stripped = lines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
            located = ConflictParser.blocks(in: stripped.joined(separator: "\n") + "\n").compactMap { block in
                guard case .conflict(let conflict) = block else { return nil }
                let start = conflict.range.lowerBound + 1
                let ours = start..<(start + conflict.ours.count)
                var separator = ours.upperBound
                var base: Range<Int>?
                if let lines = conflict.base {
                    let range = (ours.upperBound + 1)..<(ours.upperBound + 1 + lines.count)
                    base = range
                    separator = range.upperBound
                }
                let theirs = (separator + 1)..<(separator + 1 + conflict.theirs.count)
                return Located(conflict: conflict, ours: ours, base: base, theirs: theirs)
            }
        }

        var text: String {
            lines.isEmpty ? "" : lines.joined(separator: "\n") + (endsWithNewline ? "\n" : "")
        }

        var usesCRLF: Bool {
            lines.contains { $0.hasSuffix("\r") }
        }
    }

    public static func conflicts(in text: String) -> [ConflictBlock.Conflict] {
        Document(text).located.map(\.conflict)
    }

    public static func hasMarkers(_ text: String) -> Bool {
        !Document(text).located.isEmpty
    }

    public static func needsBase(_ text: String, block: Int?) -> Bool {
        Document(text).located.contains { ($0.conflict.index == block || block == nil) && $0.base == nil }
    }

    public static func resolve(_ text: String, block: Int?, with choice: ConflictChoice, diff3: String? = nil) throws -> String {
        var document = Document(text)
        let targets = document.located.filter { block == nil || $0.conflict.index == block }
        if let block, targets.isEmpty { throw Failure.blockNotFound(block) }
        let alternatives = diff3.map { ConflictResolver.alternatives(in: $0) } ?? []
        let crlf = document.usesCRLF
        for target in targets.reversed() {
            let replacement = try lines(for: target, in: document.lines, choice: choice, alternatives: alternatives, crlf: crlf)
            document.lines.replaceSubrange(target.conflict.range, with: replacement)
        }
        return document.text
    }

    static func lines(for target: Located, in lines: [String], choice: ConflictChoice, alternatives: [ConflictBlock.Conflict], crlf: Bool) throws -> [String] {
        switch choice {
        case .ours:
            return Array(lines[target.ours])
        case .theirs:
            return Array(lines[target.theirs])
        case .both:
            return Array(lines[target.ours]) + Array(lines[target.theirs])
        case .base:
            if let base = target.base { return Array(lines[base]) }
            guard let found = matchingBase(for: target.conflict, in: alternatives) else { throw Failure.noBase(target.conflict.index) }
            return crlf ? found.map { $0 + "\r" } : found
        }
    }

    public static func alternatives(in diff3: String, longestRun: Int = 6) -> [ConflictBlock.Conflict] {
        let blocks = ConflictParser.blocks(in: diff3)
        let singles = blocks.compactMap { block -> ConflictBlock.Conflict? in
            if case .conflict(let conflict) = block { conflict } else { nil }
        }
        var runs: [ConflictBlock.Conflict] = []
        for start in blocks.indices {
            guard case .conflict(let first) = blocks[start] else { continue }
            var run = first
            run.base = first.base ?? []
            var joined = 1
            var index = start + 1
            while index + 1 < blocks.count, joined < longestRun,
                  case .context(let between, _) = blocks[index], case .conflict(let next) = blocks[index + 1] {
                run.ours += between + next.ours
                run.base = (run.base ?? []) + between + (next.base ?? [])
                run.theirs += between + next.theirs
                run.range = run.range.lowerBound..<next.range.upperBound
                runs.append(run)
                joined += 1
                index += 2
            }
        }
        return singles + runs
    }

    public static func matchingBase(for conflict: ConflictBlock.Conflict, in alternatives: [ConflictBlock.Conflict]) -> [String]? {
        if let exact = alternatives.first(where: { $0.ours == conflict.ours && $0.theirs == conflict.theirs }) {
            return exact.base ?? []
        }
        let containing = alternatives.first { contains($0.ours, conflict.ours) && contains($0.theirs, conflict.theirs) }
        return containing.map { $0.base ?? [] }
    }

    static func contains(_ haystack: [String], _ needle: [String]) -> Bool {
        if needle.isEmpty { return true }
        guard needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count) where Array(haystack[start..<(start + needle.count)]) == needle {
            return true
        }
        return false
    }
}
