import Foundation

public struct ConflictLabels: Sendable, Hashable {
    public var ours: String
    public var base: String
    public var theirs: String

    public init(ours: String, base: String, theirs: String) {
        self.ours = ours
        self.base = base
        self.theirs = theirs
    }

    public static let fallback = ConflictLabels(ours: "HEAD", base: "base", theirs: "incoming")

    public static func parse(_ text: String) -> ConflictLabels? {
        var ours: String?
        var base: String?
        var theirs: String?
        for raw in text.components(separatedBy: "\n") {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if ours == nil, let label = label(line, marker: "<<<<<<<") { ours = label }
            if base == nil, let label = label(line, marker: "|||||||") { base = label }
            if theirs == nil, let label = label(line, marker: ">>>>>>>") { theirs = label }
            if ours != nil, theirs != nil, base != nil { break }
        }
        guard let ours, let theirs, !ConflictRestart.isTemporary(ours), !ConflictRestart.isTemporary(theirs) else { return nil }
        let shownBase = base.flatMap { ConflictRestart.isTemporary($0) ? nil : $0 } ?? fallback.base
        return ConflictLabels(ours: ours, base: shownBase, theirs: theirs)
    }

    static func label(_ line: String, marker: String) -> String? {
        guard line.hasPrefix(marker + " ") else { return nil }
        let label = line.dropFirst(marker.count + 1).trimmingCharacters(in: .whitespaces)
        return label.isEmpty ? nil : label
    }
}

public struct UnmergedStages: Sendable, Hashable {
    public struct Entry: Sendable, Hashable {
        public var oid: OID
        public var mode: String

        public init(oid: OID, mode: String) {
            self.oid = oid
            self.mode = mode
        }
    }

    public var base: Entry?
    public var ours: Entry?
    public var theirs: Entry?

    public init(base: Entry? = nil, ours: Entry? = nil, theirs: Entry? = nil) {
        self.base = base
        self.ours = ours
        self.theirs = theirs
    }

    public var isContentConflict: Bool { ours != nil && theirs != nil }

    public static func parse(_ data: Data) -> UnmergedStages {
        var stages = UnmergedStages()
        for record in data.split(separator: 0) {
            let line = String(decoding: record, as: UTF8.self)
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let fields = line[..<tab].split(separator: " ")
            guard fields.count == 3, let oid = OID(String(fields[1])) else { continue }
            let entry = Entry(oid: oid, mode: String(fields[0]))
            switch fields[2] {
            case "1": stages.base = entry
            case "2": stages.ours = entry
            case "3": stages.theirs = entry
            default: break
            }
        }
        return stages
    }
}

public enum ConflictRestart {
    public static let mergeProgram = "git-merge-one-file"
    static let temporaryPrefix = ".merge_file_"

    public static func mergeOneFile(path: String, stages: UnmergedStages) -> GitCommand {
        let arguments = [
            "merge-one-file",
            stages.base?.oid.rawValue ?? "",
            stages.ours?.oid.rawValue ?? "",
            stages.theirs?.oid.rawValue ?? "",
            path,
            stages.base?.mode ?? "",
            stages.ours?.mode ?? "",
            stages.theirs?.mode ?? ""
        ]
        return GitCommand(arguments, risk: .destructive, access: .write, acceptedExitCodes: [0, 1])
    }

    public static func mergeIndex(paths: [String]) -> GitCommand {
        GitCommand(["merge-index", "-o", "-q", mergeProgram, "--"] + paths, risk: .destructive, access: .write, acceptedExitCodes: Set(0...127))
    }

    public static func mergedBlob(path: String) -> GitCommand {
        .read(["cat-file", "blob", "AUTO_MERGE:" + path], acceptedExitCodes: [0, 128])
    }

    public static let rerereEnabled = ConfigCommands.get("rerere.enabled")

    public static let rerereRemaining = GitCommand.read(["rerere", "remaining"])

    public static func remaining(_ output: String) -> Set<String> {
        Set(output.components(separatedBy: "\n").filter { !$0.isEmpty })
    }

    static func isTemporary(_ label: String) -> Bool {
        label.hasPrefix(temporaryPrefix)
    }

    public static func relabel(_ text: String, with labels: ConflictLabels) -> String {
        let markers: [(marker: String, label: String)] = [("<<<<<<<", labels.ours), ("|||||||", labels.base), (">>>>>>>", labels.theirs)]
        return text.components(separatedBy: "\n").map { raw -> String in
            let carriage = raw.hasSuffix("\r")
            let line = carriage ? String(raw.dropLast()) : raw
            for (marker, label) in markers where line.hasPrefix(marker + " " + temporaryPrefix) {
                return marker + " " + label + (carriage ? "\r" : "")
            }
            return raw
        }.joined(separator: "\n")
    }
}
