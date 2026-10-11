import Foundation

public struct StatusReport: Sendable, Hashable {
    public var oid: OID?
    public var isInitial: Bool
    public var branch: String?
    public var upstream: String?
    public var ahead: Int
    public var behind: Int
    public var stashCount: Int
    public var files: [WorkingFile]
    public var conflicts: [ConflictFile]

    public var head: Head {
        if let branch {
            return isInitial ? .unborn(branch) : .branch(branch)
        }
        if let oid { return .detached(oid) }
        return .unborn("main")
    }
}

public enum StatusParser {
    public static let command = GitCommand.read(["status", "--porcelain=v2", "-z", "--branch", "--show-stash", "--untracked-files=all", "--find-renames"])

    public static func parse(_ data: Data) -> StatusReport {
        var report = StatusReport(oid: nil, isInitial: false, branch: nil, upstream: nil, ahead: 0, behind: 0, stashCount: 0, files: [], conflicts: [])
        let fields = ParseSupport.nulFields(data)
        var index = 0
        while index < fields.count {
            let entry = fields[index]
            index += 1
            guard let kind = entry.first else { continue }
            switch kind {
            case "#":
                header(entry, into: &report)
            case "1":
                let parts = entry.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                guard parts.count == 9 else { continue }
                report.files.append(file(xy: parts[1], sub: parts[2], modes: [parts[3], parts[4], parts[5]], path: String(parts[8]), oldPath: nil))
            case "2":
                let parts = entry.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                guard parts.count == 10 else { continue }
                let oldPath = index < fields.count ? fields[index] : nil
                index += 1
                report.files.append(file(xy: parts[1], sub: parts[2], modes: [parts[3], parts[4], parts[5]], path: String(parts[9]), oldPath: oldPath))
            case "u":
                let parts = entry.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                guard parts.count == 11 else { continue }
                let xy = String(parts[1])
                let path = String(parts[10])
                report.files.append(WorkingFile(path: path, status: .conflicted, staged: .none, isSubmodule: parts[2].hasPrefix("S")))
                report.conflicts.append(ConflictFile(path: path, kind: ConflictFile.Kind(xy: xy) ?? .bothModified))
            case "?":
                report.files.append(WorkingFile(path: String(entry.dropFirst(2)), status: .untracked, staged: .none, worktreeStatus: .untracked))
            default:
                continue
            }
        }
        return report
    }

    static func header(_ line: String, into report: inout StatusReport) {
        let parts = line.split(separator: " ", maxSplits: 2)
        guard parts.count == 3 else { return }
        let value = String(parts[2])
        switch parts[1] {
        case "branch.oid":
            if value == "(initial)" { report.isInitial = true } else { report.oid = OID(value) }
        case "branch.head":
            report.branch = value == "(detached)" ? nil : value
        case "branch.upstream":
            report.upstream = value
        case "branch.ab":
            let counts = value.split(separator: " ")
            if counts.count == 2 {
                report.ahead = Int(counts[0].dropFirst()) ?? 0
                report.behind = Int(counts[1].dropFirst()) ?? 0
            }
        case "stash":
            report.stashCount = Int(value) ?? 0
        default:
            break
        }
    }

    static func file(xy: Substring, sub: Substring, modes: [Substring], path: String, oldPath: String?) -> WorkingFile {
        let x = xy.first ?? "."
        let y = xy.dropFirst().first ?? "."
        let indexStatus = FileStatus(letter: x)
        let worktreeStatus = FileStatus(letter: y)
        let staged: StageState = x == "." ? .none : (y == "." ? .full : .partial)
        let status: FileStatus
        if x == "R" || y == "R" {
            status = .renamed
        } else if x == "C" || y == "C" {
            status = .copied
        } else if let indexStatus, indexStatus != .modified || worktreeStatus == nil {
            status = indexStatus
        } else {
            status = worktreeStatus ?? indexStatus ?? .modified
        }
        return WorkingFile(path: path, oldPath: oldPath, status: status, staged: staged, indexStatus: indexStatus, worktreeStatus: worktreeStatus, isSubmodule: sub.hasPrefix("S") || modes.contains("160000"))
    }
}
