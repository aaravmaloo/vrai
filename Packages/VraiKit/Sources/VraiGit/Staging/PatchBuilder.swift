import Foundation

public enum PatchBuilder {
    public static let noNewlineMarker = "\\ No newline at end of file"

    struct Op {
        var sign: Character
        var text: String
        var oldNoNewline: Bool
        var newNoNewline: Bool

        var inOld: Bool { sign != "+" }
        var inNew: Bool { sign != "-" }
    }

    public static func canBuild(for file: FileDiff) -> Bool {
        !file.isBinary && !file.isSubmodule && file.status != .conflicted && !file.hunks.isEmpty
    }

    public static func patch(for selection: LineSelection, reverse: Bool) -> Data? {
        patch(file: selection.file, lines: selection.lines, reverse: reverse).map { Data($0.utf8) }
    }

    public static func patch(file: FileDiff, lines selected: Set<LineID>, reverse: Bool) -> String? {
        guard canBuild(for: file) else { return nil }
        var body = ""
        var delta = 0
        var resultLines = 0
        for (index, hunk) in file.hunks.enumerated() {
            var ops = operations(for: hunk, index: index, selected: selected, reverse: reverse)
            let changes = ops.contains { $0.sign != " " }
            if !changes {
                resultLines += reverse ? hunk.lines.count { $0.kind == .context || $0.kind == .add } : hunk.lines.count { $0.kind == .context || $0.kind == .del }
                continue
            }
            settleNewlines(&ops, reverse: reverse)
            ops = splitContext(ops)
            let oldCount = ops.count { $0.inOld }
            let newCount = ops.count { $0.inNew }
            resultLines += reverse ? oldCount : newCount
            let oldStart: Int
            let newStart: Int
            if reverse {
                newStart = hunk.newStart
                let base = (hunk.newCount > 0 ? hunk.newStart : hunk.newStart + 1) + delta
                oldStart = oldCount > 0 ? base : base - 1
                delta += oldCount - newCount
            } else {
                oldStart = hunk.oldStart
                let base = (hunk.oldCount > 0 ? hunk.oldStart : hunk.oldStart + 1) + delta
                newStart = newCount > 0 ? base : base - 1
                delta += newCount - oldCount
            }
            body += "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@\n"
            for op in ops {
                body += String(op.sign) + op.text + "\n"
                let marker = switch op.sign {
                case "-": op.oldNoNewline
                case "+": op.newNoNewline
                default: op.oldNoNewline && op.newNoNewline
                }
                if marker { body += noNewlineMarker + "\n" }
            }
        }
        guard !body.isEmpty else { return nil }
        return header(for: file, reverse: reverse, resultEmpty: resultLines == 0) + body
    }

    static func operations(for hunk: Hunk, index: Int, selected: Set<LineID>, reverse: Bool) -> [Op] {
        var ops: [Op] = []
        let lines = hunk.lines
        for (position, line) in lines.enumerated() {
            let noNewline = position + 1 < lines.count && lines[position + 1].kind == .noNewline
            let picked = selected.contains(LineID(hunk: index, line: position))
            switch line.kind {
            case .context:
                ops.append(Op(sign: " ", text: line.text, oldNoNewline: noNewline, newNoNewline: noNewline))
            case .del:
                if picked {
                    ops.append(Op(sign: "-", text: line.text, oldNoNewline: noNewline, newNoNewline: false))
                } else if !reverse {
                    ops.append(Op(sign: " ", text: line.text, oldNoNewline: noNewline, newNoNewline: noNewline))
                }
            case .add:
                if picked {
                    ops.append(Op(sign: "+", text: line.text, oldNoNewline: false, newNoNewline: noNewline))
                } else if reverse {
                    ops.append(Op(sign: " ", text: line.text, oldNoNewline: noNewline, newNoNewline: noNewline))
                }
            case .noNewline:
                break
            }
        }
        return ops
    }

    static func settleNewlines(_ ops: inout [Op], reverse: Bool) {
        let result = ops.indices.filter { reverse ? ops[$0].inOld : ops[$0].inNew }
        for index in result.dropLast() {
            if reverse { ops[index].oldNoNewline = false } else { ops[index].newNoNewline = false }
        }
    }

    static func splitContext(_ ops: [Op]) -> [Op] {
        var out: [Op] = []
        for op in ops {
            if op.sign == " ", op.oldNoNewline != op.newNoNewline {
                out.append(Op(sign: "-", text: op.text, oldNoNewline: op.oldNoNewline, newNoNewline: false))
                out.append(Op(sign: "+", text: op.text, oldNoNewline: false, newNoNewline: op.newNoNewline))
            } else {
                out.append(op)
            }
        }
        return out
    }

    static func header(for file: FileDiff, reverse: Bool, resultEmpty: Bool) -> String {
        let created = file.status == .added || file.status == .untracked
        let deleted = file.status == .deleted
        let path = file.path
        let creation: Bool
        let deletion: Bool
        if reverse {
            deletion = deleted
            creation = created && resultEmpty
        } else {
            creation = created
            deletion = deleted && resultEmpty
        }
        var text = "diff --git " + quoted("a/" + path) + " " + quoted("b/" + path) + "\n"
        if creation {
            text += "new file mode " + (file.newMode ?? "100644") + "\n"
            text += "--- /dev/null\n"
            text += "+++ " + label("b/" + path) + "\n"
        } else if deletion {
            text += "deleted file mode " + (file.oldMode ?? "100644") + "\n"
            text += "--- " + label("a/" + path) + "\n"
            text += "+++ /dev/null\n"
        } else {
            text += "--- " + label("a/" + path) + "\n"
            text += "+++ " + label("b/" + path) + "\n"
        }
        return text
    }

    static func label(_ name: String) -> String {
        let value = quoted(name)
        return value == name && name.contains(" ") ? name + "\t" : value
    }

    static func quoted(_ name: String) -> String {
        let needs = name.utf8.contains { $0 < 0x20 || $0 == 0x22 || $0 == 0x5C || $0 == 0x7F }
        guard needs else { return name }
        var out: [UInt8] = [0x22]
        for byte in name.utf8 {
            let escaped: String? = switch byte {
            case 0x07: "\\a"
            case 0x08: "\\b"
            case 0x09: "\\t"
            case 0x0A: "\\n"
            case 0x0B: "\\v"
            case 0x0C: "\\f"
            case 0x0D: "\\r"
            case 0x22: "\\\""
            case 0x5C: "\\\\"
            case 0..<0x20, 0x7F: "\\" + octal(byte)
            default: nil
            }
            if let escaped { out += Array(escaped.utf8) } else { out.append(byte) }
        }
        out.append(0x22)
        return String(decoding: out, as: UTF8.self)
    }

    static func octal(_ byte: UInt8) -> String {
        let digits = String(byte, radix: 8)
        return String(repeating: "0", count: max(0, 3 - digits.count)) + digits
    }
}
