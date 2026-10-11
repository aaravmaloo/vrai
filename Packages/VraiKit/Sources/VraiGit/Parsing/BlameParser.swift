import Foundation

public enum BlameParser {
    public static func command(path: String, at revision: String? = nil) -> GitCommand {
        var args = ["blame", "--porcelain"]
        if let revision { args.append(revision) }
        args.append(contentsOf: ["--", path])
        return .read(args)
    }

    struct Info {
        var author = ""
        var email = ""
        var time = Date.distantPast
        var summary = ""
        var filename = ""
        var previous: OID?
        var previousPath: String?
        var boundary = false
    }

    public static func parse(_ data: Data) -> [BlameLine] {
        var infos: [OID: Info] = [:]
        var lines: [BlameLine] = []
        var currentOID: OID?
        var original = 0
        var final = 0
        var info = Info()
        for raw in ParseSupport.string(data).split(separator: "\n", omittingEmptySubsequences: false) {
            if raw.hasPrefix("\t") {
                guard let oid = currentOID else { continue }
                infos[oid] = info
                lines.append(BlameLine(number: final, text: String(raw.dropFirst()), commit: oid, originalNumber: original, path: info.filename, authorName: info.author, authorEmail: info.email, authorDate: info.time, summary: info.summary, previous: info.previous, previousPath: info.previousPath, isBoundary: info.boundary))
                continue
            }
            let parts = raw.split(separator: " ", maxSplits: 1)
            guard let key = parts.first else { continue }
            let value = parts.count > 1 ? String(parts[1]) : ""
            if key.count == 40 || key.count == 64, let oid = OID(String(key)) {
                let numbers = value.split(separator: " ")
                currentOID = oid
                original = Int(numbers.first ?? "") ?? 0
                final = numbers.count > 1 ? Int(numbers[1]) ?? 0 : 0
                info = infos[oid] ?? Info()
                continue
            }
            switch key {
            case "author": info.author = value
            case "author-mail": info.email = value.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            case "author-time": info.time = ParseSupport.date(value) ?? .distantPast
            case "summary": info.summary = value
            case "filename": info.filename = value
            case "boundary": info.boundary = true
            case "previous":
                let prev = value.split(separator: " ", maxSplits: 1)
                info.previous = prev.first.flatMap { OID(String($0)) }
                info.previousPath = prev.count > 1 ? String(prev[1]) : nil
            default: break
            }
        }
        return lines
    }
}
