import Foundation

public enum LogParser {
    public static let historyFields = ["%H", "%P", "%an", "%ae", "%at", "%cn", "%ce", "%ct", "%s", "%D"]
    public static let historyFormat = historyFields.joined(separator: "%x00")
    public static let signatureFormat = "%H%x00%G?"

    public static func historyArguments(scope: [String], limit: Int? = nil, extra: [String] = [], paths: [String] = []) -> [String] {
        var args = ["log", "--topo-order", "-z", "--decorate=full", "--format=" + historyFormat]
        if let limit { args.append("--max-count=\(limit)") }
        args.append(contentsOf: extra)
        args.append(contentsOf: scope)
        args.append("--")
        args.append(contentsOf: paths)
        return args
    }

    public static func history(_ data: Data) -> [Commit] {
        ParseSupport.records(data, fieldCount: historyFields.count).compactMap(commit(from:))
    }

    public static func commit(from fields: [String]) -> Commit? {
        guard fields.count >= historyFields.count, let id = OID(fields[0]) else { return nil }
        return Commit(
            id: id,
            parents: fields[1].split(separator: " ").compactMap { OID(String($0)) },
            authorName: fields[2],
            authorEmail: fields[3],
            authorDate: ParseSupport.date(fields[4]) ?? .distantPast,
            committerName: fields[5],
            committerEmail: fields[6],
            committerDate: ParseSupport.date(fields[7]) ?? .distantPast,
            subject: fields[8],
            signature: .unchecked,
            refs: decorations(fields[9])
        )
    }

    public static func decorations(_ text: String) -> [RefLabel] {
        guard !text.isEmpty else { return [] }
        var labels: [RefLabel] = []
        for part in text.components(separatedBy: ", ") {
            if part.hasPrefix("HEAD -> ") {
                labels.append(RefLabel(fullName: String(part.dropFirst("HEAD -> ".count)), isHead: true))
            } else if part == "HEAD" {
                labels.append(RefLabel(kind: .head, name: "HEAD", fullName: "HEAD", isHead: true))
            } else if part.hasPrefix("tag: ") {
                labels.append(RefLabel(fullName: String(part.dropFirst("tag: ".count))))
            } else if part.hasSuffix("/HEAD"), part.hasPrefix("refs/remotes/") {
                continue
            } else if part == "refs/stash" {
                continue
            } else {
                labels.append(RefLabel(fullName: part))
            }
        }
        return labels
    }

    public static func signatures(_ data: Data) -> [OID: SignatureState] {
        var out: [OID: SignatureState] = [:]
        for fields in ParseSupport.records(data, fieldCount: 2) {
            if let oid = OID(fields[0]) { out[oid] = SignatureState(gitCode: fields[1]) }
        }
        return out
    }

    static let detailFields = ["%H", "%P", "%an", "%ae", "%at", "%cn", "%ce", "%ct", "%G?", "%GS", "%GK", "%s", "%b", "%D"]
    public static let detailFormat = detailFields.map { $0 + "%x00" }.joined()

    public static func detailCommand(_ id: OID, renameThreshold: Int = 50) -> GitCommand {
        .read(["show", "-z", "--decorate=full", "--raw", "--numstat", "--find-renames=\(renameThreshold)%", "--first-parent", "-m", "--format=" + detailFormat, id.rawValue, "--"])
    }

    public static func detail(_ data: Data) -> CommitDetail? {
        let fields = ParseSupport.nulFields(data)
        guard fields.count >= detailFields.count, let id = OID(fields[0]) else { return nil }
        let body = fields[12].trimmingCharacters(in: .newlines)
        let commit = Commit(
            id: id,
            parents: fields[1].split(separator: " ").compactMap { OID(String($0)) },
            authorName: fields[2],
            authorEmail: fields[3],
            authorDate: ParseSupport.date(fields[4]) ?? .distantPast,
            committerName: fields[5],
            committerEmail: fields[6],
            committerDate: ParseSupport.date(fields[7]) ?? .distantPast,
            subject: fields[11],
            body: body.isEmpty ? nil : body,
            signature: SignatureState(gitCode: fields[8]),
            refs: decorations(fields[13])
        )
        let rest = Array(fields[detailFields.count...])
        return CommitDetail(commit: commit, signer: fields[9].isEmpty ? nil : fields[9], signingKey: fields[10].isEmpty ? nil : fields[10], files: changedFiles(rest))
    }

    public static func changedFiles(_ tokens: [String]) -> [ChangedFile] {
        var files: [ChangedFile] = []
        var byPath: [String: Int] = [:]
        var index = 0
        while index < tokens.count {
            var token = tokens[index]
            while token.hasPrefix("\n") { token.removeFirst() }
            index += 1
            if token.hasPrefix(":") {
                let parts = token.split(separator: " ")
                guard parts.count >= 5, let letter = parts[4].first else { continue }
                let similarity = Int(parts[4].dropFirst())
                let status = FileStatus(letter: letter) ?? .modified
                if (letter == "R" || letter == "C"), index + 1 < tokens.count {
                    let old = tokens[index]
                    let new = tokens[index + 1]
                    index += 2
                    byPath[new] = files.count
                    files.append(ChangedFile(path: new, oldPath: old, status: status))
                    _ = similarity
                } else if index < tokens.count {
                    let path = tokens[index]
                    index += 1
                    if byPath[path] == nil {
                        byPath[path] = files.count
                        files.append(ChangedFile(path: path, status: status))
                    }
                }
            } else if let tab = token.firstIndex(of: "\t") {
                let adds = token[..<tab]
                let afterAdds = token[token.index(after: tab)...]
                guard let tab2 = afterAdds.firstIndex(of: "\t") else { continue }
                let dels = afterAdds[..<tab2]
                var path = String(afterAdds[afterAdds.index(after: tab2)...])
                if path.isEmpty, index + 1 < tokens.count {
                    path = tokens[index + 1]
                    index += 2
                }
                guard let position = byPath[path] else { continue }
                files[position].isBinary = adds == "-" && dels == "-"
                files[position].additions = Int(adds) ?? 0
                files[position].deletions = Int(dels) ?? 0
            }
        }
        return files
    }
}
