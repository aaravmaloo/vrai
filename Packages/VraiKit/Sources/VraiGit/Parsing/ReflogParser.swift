import Foundation

public enum ReflogParser {
    public static func command(ref: String = "HEAD", limit: Int = 500) -> GitCommand {
        .read(["reflog", "show", "-z", "--date=unix", "--format=%H%x00%gd%x00%gs%x00%ct", "-n", String(limit), ref, "--"], acceptedExitCodes: [0, 128])
    }

    public static func parse(_ data: Data) -> [ReflogEntry] {
        ParseSupport.records(data, fieldCount: 4).enumerated().compactMap { offset, fields in
            guard let oid = OID(fields[0]) else { return nil }
            let selector = fields[1]
            var name = selector
            var stamp: TimeInterval?
            if let open = selector.range(of: "@{", options: .backwards), selector.hasSuffix("}") {
                name = String(selector[..<open.lowerBound])
                let inside = selector[open.upperBound..<selector.index(before: selector.endIndex)]
                if let value = TimeInterval(inside), value >= 100_000_000 { stamp = value }
            }
            let date = stamp.map { Date(timeIntervalSince1970: $0) } ?? ParseSupport.date(fields[3]) ?? .distantPast
            return ReflogEntry(id: oid, selector: name + "@{" + String(offset) + "}", message: fields[2], date: date)
        }
    }
}
