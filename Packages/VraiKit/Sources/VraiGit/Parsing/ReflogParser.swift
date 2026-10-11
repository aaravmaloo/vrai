import Foundation

public enum ReflogParser {
    public static func command(ref: String = "HEAD", limit: Int = 500) -> GitCommand {
        .read(["reflog", "show", "-z", "--format=%H%x00%gd%x00%gs%x00%ct", "-n", String(limit), ref, "--"], acceptedExitCodes: [0, 128])
    }

    public static func parse(_ data: Data) -> [ReflogEntry] {
        ParseSupport.records(data, fieldCount: 4).compactMap { fields in
            guard let oid = OID(fields[0]) else { return nil }
            return ReflogEntry(id: oid, selector: fields[1], message: fields[2], date: ParseSupport.date(fields[3]) ?? .distantPast)
        }
    }
}
