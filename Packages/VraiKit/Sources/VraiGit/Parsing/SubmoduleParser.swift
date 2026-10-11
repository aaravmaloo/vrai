import Foundation

public enum SubmoduleParser {
    public static let statusCommand = GitCommand.read(["submodule", "status", "--recursive"])
    public static let gitmodulesCommand = GitCommand.read(["config", "-z", "-f", ".gitmodules", "--list"], acceptedExitCodes: [0, 1])

    public static func stageCommand(paths: [String]) -> GitCommand {
        .read(["ls-files", "--stage", "-z", "--"] + paths.map { ":(literal)" + $0 })
    }

    public struct Gitlink: Sendable, Hashable {
        public var path: String
        public var oid: OID?
        public var conflicted: Bool
    }

    public enum Head: Sendable, Hashable {
        case unpopulated
        case commit(OID)
        case unresolved
    }

    public static func gitlinks(_ data: Data) -> [Gitlink] {
        var links: [Gitlink] = []
        var index: [String: Int] = [:]
        for entry in ParseSupport.nulFields(data) where entry.hasPrefix("160000 ") {
            guard let tab = entry.firstIndex(of: "\t") else { continue }
            let meta = entry[..<tab].split(separator: " ")
            guard meta.count == 3 else { continue }
            let path = String(entry[entry.index(after: tab)...])
            let stage = Int(meta[2]) ?? 0
            let oid = OID(String(meta[1]))
            if let existing = index[path] {
                links[existing].conflicted = true
                if stage == 2 { links[existing].oid = oid }
            } else {
                index[path] = links.count
                links.append(Gitlink(path: path, oid: stage == 0 || stage == 2 ? oid : nil, conflicted: stage != 0))
            }
        }
        return links
    }

    public static func head(at directory: URL) -> Head {
        let dotGit = directory.appending(path: ".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path(percentEncoded: false), isDirectory: &isDirectory) else { return .unpopulated }
        var gitDir = dotGit
        if !isDirectory.boolValue {
            guard let text = try? String(contentsOf: dotGit, encoding: .utf8), text.hasPrefix("gitdir: ") else { return .unpopulated }
            let target = text.dropFirst("gitdir: ".count).trimmingCharacters(in: .whitespacesAndNewlines)
            gitDir = target.hasPrefix("/") ? URL(filePath: target, directoryHint: .isDirectory) : directory.appending(path: target, directoryHint: .isDirectory).standardized
        }
        guard let head = try? String(contentsOf: gitDir.appending(path: "HEAD"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else { return .unpopulated }
        if let oid = OID(head) { return .commit(oid) }
        guard head.hasPrefix("ref: ") else { return .unresolved }
        let ref = gitDir.appending(path: String(head.dropFirst("ref: ".count)))
        if let loose = try? String(contentsOf: ref, encoding: .utf8), let oid = OID(loose.trimmingCharacters(in: .whitespacesAndNewlines)) { return .commit(oid) }
        return .unresolved
    }

    public static func submodule(_ link: Gitlink, declared: (name: String, path: String, url: String?, branch: String?)?, head: Head) -> Submodule {
        let checkedOut: OID? = if case .commit(let oid) = head { oid } else { nil }
        let state: Submodule.State
        if link.conflicted {
            state = .conflicted
        } else if checkedOut == nil {
            state = .uninitialized
        } else {
            state = checkedOut == link.oid ? .clean : .ahead
        }
        return Submodule(path: link.path, name: declared?.name, url: declared?.url, branch: declared?.branch, recorded: link.oid, checkedOut: checkedOut, state: state)
    }

    public struct StatusLine: Sendable, Hashable {
        public var flag: Character
        public var oid: OID?
        public var path: String
        public var describe: String?
    }

    public static func statusLines(_ data: Data) -> [StatusLine] {
        ParseSupport.string(data).split(separator: "\n").compactMap { raw in
            guard let flag = raw.first else { return nil }
            let rest = String(raw.dropFirst())
            guard let space = rest.firstIndex(of: " ") else { return nil }
            let oid = OID(String(rest[..<space]))
            var path = String(rest[rest.index(after: space)...])
            var describe: String?
            if path.hasSuffix(")"), let open = path.range(of: " (", options: .backwards) {
                describe = String(path[open.upperBound..<path.index(before: path.endIndex)])
                path = String(path[..<open.lowerBound])
            }
            return StatusLine(flag: flag, oid: oid, path: path, describe: describe)
        }
    }

    public static func merge(status: [StatusLine], gitmodules: Data, recorded: [String: OID] = [:]) -> [Submodule] {
        let declared = ConfigParser.gitmodules(gitmodules)
        var result: [Submodule] = []
        for line in status {
            let info = declared.first { $0.path == line.path }
            let state: Submodule.State
            switch line.flag {
            case "-": state = .uninitialized
            case "+": state = .ahead
            case "U": state = .conflicted
            default: state = .clean
            }
            result.append(Submodule(
                path: line.path,
                name: info?.name,
                url: info?.url,
                branch: info?.branch,
                recorded: recorded[line.path] ?? (line.flag == "+" ? nil : line.oid),
                checkedOut: line.flag == "-" ? nil : line.oid,
                state: state,
                describe: line.describe
            ))
        }
        return result
    }
}
