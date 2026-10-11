import Foundation

enum ParseSupport {
    static func string(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    static func nulFields(_ data: Data) -> [String] {
        var fields: [String] = []
        var start = data.startIndex
        var index = data.startIndex
        while index < data.endIndex {
            if data[index] == 0 {
                fields.append(String(decoding: data[start..<index], as: UTF8.self))
                start = data.index(after: index)
            }
            index = data.index(after: index)
        }
        if start < data.endIndex { fields.append(String(decoding: data[start..<data.endIndex], as: UTF8.self)) }
        return fields
    }

    static func records(_ data: Data, fieldCount: Int) -> [[String]] {
        var fields = nulFields(data)
        if fields.count % fieldCount != 0, fields.last?.isEmpty == true || fields.last == "\n" { fields.removeLast() }
        var out: [[String]] = []
        out.reserveCapacity(fields.count / fieldCount)
        var index = 0
        while index + fieldCount <= fields.count {
            var record = Array(fields[index..<index + fieldCount])
            if index > 0, record[0].hasPrefix("\n") { record[0].removeFirst() }
            out.append(record)
            index += fieldCount
        }
        return out
    }

    static func date(_ text: String) -> Date? {
        TimeInterval(text.trimmingCharacters(in: .whitespaces)).map { Date(timeIntervalSince1970: $0) }
    }

    static func unquoteCPath(_ text: String) -> String {
        guard text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") else { return text }
        var bytes: [UInt8] = []
        var scalars = Array(text.utf8.dropFirst().dropLast())
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if c == UInt8(ascii: "\\"), i + 1 < scalars.count {
                let n = scalars[i + 1]
                switch n {
                case UInt8(ascii: "n"): bytes.append(0x0A); i += 2
                case UInt8(ascii: "t"): bytes.append(0x09); i += 2
                case UInt8(ascii: "r"): bytes.append(0x0D); i += 2
                case UInt8(ascii: "a"): bytes.append(0x07); i += 2
                case UInt8(ascii: "b"): bytes.append(0x08); i += 2
                case UInt8(ascii: "f"): bytes.append(0x0C); i += 2
                case UInt8(ascii: "v"): bytes.append(0x0B); i += 2
                case UInt8(ascii: "0")...UInt8(ascii: "7"):
                    var value = 0
                    var j = i + 1
                    while j < scalars.count, j < i + 4, (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(scalars[j]) {
                        value = value * 8 + Int(scalars[j] - UInt8(ascii: "0"))
                        j += 1
                    }
                    bytes.append(UInt8(truncatingIfNeeded: value))
                    i = j
                default:
                    bytes.append(n)
                    i += 2
                }
            } else {
                bytes.append(c)
                i += 1
            }
        }
        scalars.removeAll()
        return String(decoding: bytes, as: UTF8.self)
    }
}
