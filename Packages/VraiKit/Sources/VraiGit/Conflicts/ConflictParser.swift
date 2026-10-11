import Foundation

public enum ConflictParser {
    public static func blocks(in text: String) -> [ConflictBlock] {
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        var blocks: [ConflictBlock] = []
        var context: [String] = []
        var contextStart = 0
        var index = 0
        var conflictIndex = 0

        func flushContext(until end: Int) {
            if !context.isEmpty { blocks.append(.context(lines: context, range: contextStart..<end)) }
            context = []
        }

        while index < lines.count {
            let line = lines[index]
            guard line.hasPrefix("<<<<<<<"), let parsed = conflict(at: index, in: lines) else {
                if context.isEmpty { contextStart = index }
                context.append(line)
                index += 1
                continue
            }
            flushContext(until: index)
            conflictIndex += 1
            var block = parsed.block
            block.index = conflictIndex
            blocks.append(.conflict(block))
            index = parsed.end
        }
        flushContext(until: lines.count)
        return blocks
    }

    static func conflict(at start: Int, in lines: [String]) -> (block: ConflictBlock.Conflict, end: Int)? {
        let oursLabel = label(lines[start], marker: "<<<<<<<")
        var ours: [String] = []
        var base: [String]?
        var baseLabel: String?
        var theirs: [String] = []
        var section = 0
        var index = start + 1
        while index < lines.count {
            let line = lines[index]
            if section == 0, line.hasPrefix("|||||||") {
                section = 1
                base = []
                baseLabel = label(line, marker: "|||||||")
            } else if section < 2, line == "=======" || line.hasPrefix("======= ") {
                section = 2
            } else if section == 2, line.hasPrefix(">>>>>>>") {
                let block = ConflictBlock.Conflict(index: 0, oursLabel: oursLabel, ours: ours, baseLabel: baseLabel, base: base, theirsLabel: label(line, marker: ">>>>>>>"), theirs: theirs, range: start..<(index + 1))
                return (block, index + 1)
            } else if line.hasPrefix("<<<<<<<") {
                return nil
            } else {
                switch section {
                case 0: ours.append(line)
                case 1: base?.append(line)
                default: theirs.append(line)
                }
            }
            index += 1
        }
        return nil
    }

    static func label(_ line: String, marker: String) -> String {
        line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
    }

    public static func hasMarkers(_ text: String) -> Bool {
        blocks(in: text).contains { if case .conflict = $0 { true } else { false } }
    }
}
