import Foundation

public struct EditorMessage: Sendable, Hashable, Codable {
    public var commit: String?
    public var message: String

    public init(commit: String?, message: String) {
        self.commit = commit
        self.message = message
    }
}

public struct InteractivePlan: Sendable, Hashable {
    public enum Problem: Sendable, Hashable {
        case empty
        case startsWithFold
    }

    public struct Files: Sendable, Hashable {
        public var directory: URL
        public var todo: URL
        public var messages: URL

        public init(gitDir: URL) {
            directory = gitDir.appending(path: "vrai/rebase", directoryHint: .isDirectory)
            todo = directory.appending(path: "todo")
            messages = directory.appending(path: "messages.json")
        }

        public var hasMessages: Bool {
            FileManager.default.fileExists(atPath: messages.path(percentEncoded: false))
        }

        public func clear() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    public var steps: [RebaseStep]

    public init(steps: [RebaseStep]) {
        self.steps = steps
    }

    public var problem: Problem? {
        let kept = steps.filter { $0.action != .drop }
        if steps.isEmpty { return .empty }
        if kept.first?.action.foldsIntoPrevious == true { return .startsWithFold }
        return nil
    }

    public var todo: String {
        steps.map { step in
            let subject = step.subject.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
            return "\(step.action.rawValue) \(step.commit.rawValue) # \(subject)"
        }.joined(separator: "\n") + "\n"
    }

    public var messages: [EditorMessage] {
        var entries: [EditorMessage] = []
        var chainEnd: OID?
        var chainMessage: String?

        func flush() {
            if let chainEnd, let chainMessage { entries.append(EditorMessage(commit: chainEnd.rawValue, message: chainMessage)) }
            chainEnd = nil
            chainMessage = nil
        }

        for step in steps where step.action != .drop {
            if step.action.foldsIntoPrevious {
                chainEnd = step.commit
                if step.action == .squash, let message = step.message { chainMessage = message }
                continue
            }
            flush()
            if step.action == .reword, let message = step.message {
                entries.append(EditorMessage(commit: step.commit.rawValue, message: message))
            }
        }
        flush()
        return entries
    }

    public func write(to files: Files) throws {
        let manager = FileManager.default
        try? manager.removeItem(at: files.directory)
        try manager.createDirectory(at: files.directory, withIntermediateDirectories: true)
        try Data(todo.utf8).write(to: files.todo)
        let entries = messages
        if !entries.isEmpty {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(entries).write(to: files.messages)
        }
    }

    public static func listCommand(onto: String) -> GitCommand {
        .read(["log", "--reverse", "--topo-order", "--no-merges", "--right-only", "--cherry-pick", "-z", "--format=%H%x00%s%x00%an", onto + "...HEAD"])
    }

    public static func parse(_ data: Data) -> [RebaseStep] {
        ParseSupport.records(data, fieldCount: 3).compactMap { fields in
            guard let commit = OID(fields[0]) else { return nil }
            return RebaseStep(commit: commit, subject: fields[1], author: fields[2])
        }
    }
}
