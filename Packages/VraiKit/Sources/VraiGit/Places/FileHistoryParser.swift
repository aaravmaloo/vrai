import Foundation

public struct FileHistoryEntry: Sendable, Hashable, Identifiable {
    public var commit: Commit
    public var file: ChangedFile

    public var id: OID { commit.id }

    public init(commit: Commit, file: ChangedFile) {
        self.commit = commit
        self.file = file
    }
}

public enum FileHistoryParser {
    static let marker: Character = "\u{1E}"

    public static func command(path: String, renameThreshold: Int = 50, limit: Int? = nil) -> GitCommand {
        var arguments = ["log", "--follow", "-z", "--raw", "--numstat", "--find-renames=\(renameThreshold)%", "--decorate=full", "--format=%x1e" + LogParser.historyFormat + "%x00"]
        if let limit { arguments.append("--max-count=\(limit)") }
        arguments += ["--", path]
        return .read(arguments)
    }

    public static func parse(_ data: Data, path: String) -> [FileHistoryEntry] {
        let tokens = ParseSupport.nulFields(data)
        var entries: [FileHistoryEntry] = []
        var index = 0
        var fields: [String]?
        var files: [String] = []
        func flush() {
            guard let fields, let commit = LogParser.commit(from: fields) else { return }
            let changed = LogParser.changedFiles(files)
            let file = changed.first { $0.path == path || $0.oldPath == path } ?? changed.first ?? ChangedFile(path: path, status: .modified)
            entries.append(FileHistoryEntry(commit: commit, file: file))
        }
        while index < tokens.count {
            var token = tokens[index]
            while token.hasPrefix("\n") { token.removeFirst() }
            if token.first == marker {
                flush()
                token.removeFirst()
                let count = LogParser.historyFields.count
                var collected = [token]
                var next = index + 1
                while collected.count < count, next < tokens.count {
                    collected.append(tokens[next])
                    next += 1
                }
                fields = collected
                files = []
                index = next
                continue
            }
            if fields != nil, !token.isEmpty { files.append(tokens[index]) }
            index += 1
        }
        flush()
        var current = path
        var out: [FileHistoryEntry] = []
        for var entry in entries {
            if entry.file.path != current, entry.file.oldPath == nil, entry.file.status != .renamed {
                entry.file.path = current
            }
            if let old = entry.file.oldPath, entry.file.status == .renamed || entry.file.status == .copied { current = old }
            out.append(entry)
        }
        return out
    }
}
