import Foundation

public enum StashParser {
    public static let command = GitCommand.read(["stash", "list", "-z", "--format=%H%x00%gd%x00%gs%x00%ct%x00%P"])

    public static func parse(_ data: Data) -> [Stash] {
        ParseSupport.records(data, fieldCount: 5).enumerated().compactMap { offset, fields in
            guard let oid = OID(fields[0]) else { return nil }
            let selector = fields[1]
            let index = selector.firstMatch(of: #/\{(\d+)\}/#).flatMap { Int($0.output.1) } ?? offset
            let message = fields[2]
            let branch = message.firstMatch(of: #/^(?:WIP on|On) (.+?): /#).map { String($0.output.1) }
            let parents = fields[4].split(separator: " ").compactMap { OID(String($0)) }
            return Stash(index: index, oid: oid, message: message, branch: branch, base: parents.first, date: ParseSupport.date(fields[3]) ?? .distantPast)
        }
    }
}
