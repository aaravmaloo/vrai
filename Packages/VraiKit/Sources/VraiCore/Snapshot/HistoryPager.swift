import Foundation
import VraiGit

public enum HistoryScope: Sendable, Hashable {
    case all
    case current
    case ref(String)

    public var arguments: [String] {
        switch self {
        case .all: ["--branches", "--remotes", "--tags", "HEAD"]
        case .current: ["HEAD"]
        case .ref(let name): [name]
        }
    }

    var unbornArguments: [String]? {
        switch self {
        case .all: ["--branches", "--remotes", "--tags"]
        case .current, .ref: nil
        }
    }

    var usesHead: Bool {
        switch self {
        case .all, .current: true
        case .ref: false
        }
    }
}

public struct HistoryFilter: Sendable, Hashable {
    public var text: String?
    public var author: String?
    public var paths: [String]

    public init(text: String? = nil, author: String? = nil, paths: [String] = []) {
        self.text = text
        self.author = author
        self.paths = paths
    }

    public var isEmpty: Bool { (text ?? "").isEmpty && (author ?? "").isEmpty && paths.isEmpty }

    public var arguments: [String] {
        var args: [String] = []
        if let text, !text.isEmpty, OID.looksLikeHashPrefix(text) == false {
            args += ["--grep=" + text, "-i", "--fixed-strings"]
        }
        if let author, !author.isEmpty { args.append("--author=" + author) }
        if !paths.isEmpty { args.append("--parents") }
        return args
    }
}

public struct HistoryPage: Sendable {
    public var commits: [Commit]
    public var rows: [GraphRow]
    public var lanes: Int
    public var isLast: Bool
    public var offset: Int
    public var wipRow: GraphRow? = nil
}

public actor HistoryPager {
    public let pageSize: Int
    public private(set) var command: GitCommand
    private let git: GitProcess
    private let scope: HistoryScope
    private let filter: HistoryFilter
    private var layout: LaneLayout
    private var colors: [OID: Int]
    private var head: OID?
    private var wip: LayoutCommit?
    private var iterator: AsyncThrowingStream<Data, Error>.AsyncIterator?
    private var buffer = Data()
    private var nulsInBuffer = 0
    private var finished = false
    private var reading = false
    private var delivered = 0
    private var fellBack = false
    private let fieldCount = LogParser.historyFields.count

    public init(git: GitProcess, scope: HistoryScope = .all, filter: HistoryFilter = HistoryFilter(), colors: [OID: Int] = [:], head: OID? = nil, pageSize: Int = 2000, wip: LayoutCommit? = nil) {
        self.git = git
        self.wip = wip
        self.scope = scope
        self.filter = filter
        self.pageSize = pageSize
        self.colors = colors
        self.head = head
        self.layout = LaneLayout(keepMissing: filter.isEmpty)
        self.command = .read(LogParser.historyArguments(scope: scope.arguments, extra: filter.arguments, paths: filter.paths))
    }

    public func start() {
        guard iterator == nil, !finished, delivered == 0 else { return }
        iterator = git.stream(command).makeAsyncIterator()
    }

    public func configure(colors: [OID: Int], head: OID?, wip: LayoutCommit?) {
        guard delivered == 0 else { return }
        self.colors = colors
        self.head = head
        self.wip = wip
    }

    public func nextPage() async throws -> HistoryPage? {
        if finished && buffer.isEmpty { return nil }
        guard !reading else { throw GitError(.cancelled) }
        reading = true
        defer { reading = false }
        var source = iterator ?? git.stream(command).makeAsyncIterator()
        iterator = nil
        defer { if !finished { iterator = source } }
        let wanted = pageSize * fieldCount
        while nulsInBuffer < wanted, !finished {
            do {
                guard let chunk = try await source.next(isolation: #isolation) else {
                    finished = true
                    break
                }
                buffer.append(chunk)
                nulsInBuffer += chunk.reduce(0) { $1 == 0 ? $0 + 1 : $0 }
            } catch let error as GitError {
                finished = true
                guard error.code == .refNotFound, scope.usesHead, !fellBack, delivered == 0, buffer.isEmpty else { throw error }
                fellBack = true
                guard let fallback = scope.unbornArguments else {
                    return HistoryPage(commits: [], rows: [], lanes: 0, isLast: true, offset: 0)
                }
                command = .read(LogParser.historyArguments(scope: fallback, extra: filter.arguments, paths: filter.paths))
                source = git.stream(command).makeAsyncIterator()
                finished = false
            }
        }
        let take = min(nulsInBuffer, wanted)
        let records = take / fieldCount
        guard records > 0 || finished else { return nil }
        var cut = buffer.startIndex
        var seen = 0
        if records > 0 {
            for index in buffer.indices where buffer[index] == 0 {
                seen += 1
                if seen == records * fieldCount {
                    cut = buffer.index(after: index)
                    break
                }
            }
        }
        let pageData = buffer[buffer.startIndex..<cut]
        let commits = records > 0 ? LogParser.history(Data(pageData)) : []
        buffer.removeSubrange(buffer.startIndex..<cut)
        nulsInBuffer -= records * fieldCount
        let colors = self.colors
        var wipRow: GraphRow?
        if let pending = wip {
            wip = nil
            wipRow = layout.append([pending], colorOf: { colors[$0] }).first
        }
        let rows = layout.append(commits.map { LayoutCommit(id: $0.id, parents: $0.parents, color: colors[$0.id]) }, head: head, colorOf: { colors[$0] })
        let offset = delivered
        delivered += commits.count
        let isLast = finished && nulsInBuffer < fieldCount
        if isLast { buffer.removeAll() }
        return HistoryPage(commits: commits, rows: rows, lanes: layout.maxWidth, isLast: isLast, offset: offset, wipRow: wipRow)
    }

    public func cancel() {
        iterator = nil
        finished = true
        buffer.removeAll()
    }
}

extension OID {
    public static func looksLikeHashPrefix(_ text: String) -> Bool {
        text.count >= 4 && text.count <= 64 && text.allSatisfy { $0.isHexDigit && $0.isASCII && !$0.isUppercase }
    }
}
