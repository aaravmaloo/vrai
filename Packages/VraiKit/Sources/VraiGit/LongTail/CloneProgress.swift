import Foundation

public struct CloneProgress: Sendable, Hashable {
    public enum Stage: String, Sendable, Hashable {
        case connecting
        case counting
        case receiving
        case resolving
        case checkingOut
        case submodules
        case finished
    }

    public var stage: Stage
    public var phase: String
    public var fraction: Double?
    public var current: Int?
    public var total: Int?
    public var transferred: String?
    public var speed: String?
    public var submodule: String?
    public var line: String

    public init(stage: Stage, phase: String, fraction: Double? = nil, current: Int? = nil, total: Int? = nil, transferred: String? = nil, speed: String? = nil, submodule: String? = nil, line: String = "") {
        self.stage = stage
        self.phase = phase
        self.fraction = fraction
        self.current = current
        self.total = total
        self.transferred = transferred
        self.speed = speed
        self.submodule = submodule
        self.line = line
    }

    public var hasObjects: Bool { current != nil && total != nil }
}

public struct CloneProgressParser: Sendable {
    public private(set) var submodule: String?
    public private(set) var submodules: [String] = []
    private var root: String

    public init(destination: String) {
        root = destination.hasSuffix("/") ? String(destination.dropLast()) : destination
    }

    public mutating func consume(_ line: String) -> CloneProgress? {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if let match = text.firstMatch(of: /^Cloning into (?:bare repository )?'(.+)'\.\.\.$/) {
            let path = String(match.output.1)
            let roots = [root, "/private" + root, root.hasPrefix("/private/") ? String(root.dropFirst("/private".count)) : root]
            let name = submodules.first { path.hasSuffix("/" + $0) } ?? roots.first { path.hasPrefix($0 + "/") }.map { String(path.dropFirst($0.count + 1)) }
            if let name {
                submodule = name
                if !submodules.contains(name) { submodules.append(name) }
                return CloneProgress(stage: .submodules, phase: text, submodule: name, line: text)
            }
            return CloneProgress(stage: .connecting, phase: text, submodule: submodule, line: text)
        }
        if let match = text.firstMatch(of: /^Submodule '(.+?)' \(.*\) registered for path '(.+)'$/) {
            let name = String(match.output.2)
            if !submodules.contains(name) { submodules.append(name) }
            return CloneProgress(stage: .submodules, phase: text, submodule: submodule, line: text)
        }
        if let match = text.firstMatch(of: /^Submodule path '(.+)': checked out '([0-9a-f]+)'$/) {
            return CloneProgress(stage: .submodules, phase: text, submodule: String(match.output.1), line: text)
        }
        guard let parsed = ProgressParser.parse(text) else { return nil }
        let stage: CloneProgress.Stage
        switch parsed.phase {
        case "Receiving objects": stage = .receiving
        case "Resolving deltas": stage = .resolving
        case "Updating files", "Checking out files": stage = .checkingOut
        default: stage = .counting
        }
        var transferred: String?
        var speed: String?
        if let detail = parsed.detail {
            let parts = detail.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            transferred = parts.first.flatMap { $0.isEmpty ? nil : $0 }
            if parts.count > 1 { speed = parts[1].isEmpty ? nil : parts[1] }
        }
        return CloneProgress(stage: stage, phase: parsed.phase, fraction: parsed.fraction, current: parsed.current, total: parsed.total, transferred: transferred, speed: speed, submodule: submodule, line: text)
    }
}
