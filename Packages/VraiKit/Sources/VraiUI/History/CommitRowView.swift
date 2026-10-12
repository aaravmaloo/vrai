import SwiftUI
import VraiCore
import VraiGit

@MainActor
final class RefPillsCache {
    struct Key: Equatable {
        var head: Head
        var branches: [Branch]
        var remoteBranches: [RemoteBranch]
        var remotes: [Remote]
        var tags: [Tag]
        var state: RepoState
        var skipped: [OID]
    }

    private var key: Key?
    private var value: [OID: [RefPillModel]] = [:]

    func pills(_ snapshot: RepositorySnapshot, skipped: [OID]) -> [OID: [RefPillModel]] {
        let next = Key(head: snapshot.head, branches: snapshot.branches, remoteBranches: snapshot.remoteBranches, remotes: snapshot.remotes, tags: snapshot.tags, state: snapshot.state, skipped: skipped)
        if next != key {
            value = RefPills.byCommit(snapshot, skipped: skipped)
            key = next
        }
        return value
    }
}

enum RefPills {
    static func byCommit(_ snapshot: RepositorySnapshot, skipped: [OID] = [], only: OID? = nil) -> [OID: [RefPillModel]] {
        var map: [OID: [RefPillModel]] = [:]
        func add(_ id: OID?, _ pill: @autoclosure () -> RefPillModel) {
            guard let id, only == nil || id == only else { return }
            map[id, default: []].append(pill())
        }
        if case .detached(let id) = snapshot.head { add(id, RefPillModel(kind: .head, name: "HEAD")) }
        let current = snapshot.head.branchName
        let branches = snapshot.branches.sorted { a, b in
            if a.name == current { return true }
            if b.name == current { return false }
            if a.name == "main" { return true }
            if b.name == "main" { return false }
            return a.name < b.name
        }
        var inSync: Set<String> = []
        let remoteTips = Dictionary(snapshot.remoteBranches.map { ($0.fullName, $0.tip) }, uniquingKeysWith: { first, _ in first })
        for branch in branches {
            let sync = branch.upstream.flatMap { remoteTips[$0] } == branch.tip
            if sync, let upstream = branch.upstream { inSync.insert(upstream) }
            add(branch.tip, RefPillModel(kind: .branch, name: branch.name, lane: branch.colorIndex, current: branch.name == current && snapshot.head == .branch(branch.name), upstream: sync ? branch.upstream : nil))
        }
        let order = Dictionary(snapshot.remotes.enumerated().map { ($0.element.name, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let remotes = snapshot.remoteBranches.sorted { a, b in
            let left = order[a.remote] ?? Int.max
            let right = order[b.remote] ?? Int.max
            return left != right ? left < right : a.name < b.name
        }
        for remote in remotes where !inSync.contains(remote.fullName) {
            add(remote.tip, RefPillModel(kind: .remote, name: remote.fullName, lane: remote.colorIndex))
        }
        for tag in snapshot.tags {
            add(tag.target, RefPillModel(kind: .tag, name: tag.name))
        }
        if case .bisecting(let good, let bad, _, _) = snapshot.state {
            add(bad, RefPillModel(kind: .bad, name: "bisect/bad"))
            for id in good { add(id, RefPillModel(kind: .good, name: "bisect/good")) }
            for id in skipped { add(id, RefPillModel(kind: .skip, name: "bisect/skip")) }
        }
        return map
    }
}

struct CommitColumns: OptionSet {
    let rawValue: Int
    static let author = CommitColumns(rawValue: 1)
    static let date = CommitColumns(rawValue: 2)
    static let hash = CommitColumns(rawValue: 4)
    static let all: CommitColumns = [.author, .date, .hash]
}

struct CommitRowView: View {
    let commit: Commit
    let row: GraphRow
    let lanes: Int
    let height: CGFloat
    let refs: [RefPillModel]
    let selected: Bool
    let focused: Bool
    let dim: Bool
    let query: String
    let columns: CommitColumns
    let signature: SignatureState
    var layout: CommitColumnLayout?
    @Environment(\.expert) private var expert
    @Environment(\.vraiNow) private var now

    var body: some View {
        let emphasized = selected && focused
        let metrics = layout ?? .standalone(lanes: lanes)
        HStack(spacing: 0) {
            CommitGraphCell(row: row, lanes: lanes, height: height, dim: dim, emphasized: emphasized)
                .frame(width: metrics.graph, alignment: .leading)
            SubjectLayout(share: columns == [.date] ? Metrics.refsShareNarrow : Metrics.refsShare) {
                if !refs.isEmpty {
                    PillRow {
                        ForEach(refs) { RefPill(model: $0).modifier(SelectedRowPill(emphasized: emphasized)) }
                    }
                    .layoutValue(key: SubjectRole.self, value: 0)
                }
                SubjectText(subject: commit.subject, query: query)
                    .layoutValue(key: SubjectRole.self, value: 1)
                if expert, signature != .unchecked {
                    SignatureBadge(state: signature, compact: true)
                        .layoutValue(key: SubjectRole.self, value: 2)
                }
            }
            .padding(.horizontal, CommitColumnLayout.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            if columns.contains(.author) {
                Text(commit.authorName)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, CommitColumnLayout.inset)
                    .frame(width: metrics.author, alignment: .leading)
            }
            if columns.contains(.date) {
                Text(RelativeDate.text(commit.authorDate, now: now))
                    .font(Font.Vrai.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, CommitColumnLayout.inset)
                    .frame(width: metrics.date, alignment: .leading)
                    .help(RelativeDate.full(commit.authorDate))
            }
            if columns.contains(.hash) {
                Text(commit.id.display(expert: expert))
                    .font(Font.Vrai.codeSmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, CommitColumnLayout.inset)
                    .frame(width: metrics.hash, alignment: .leading)
            }
        }
        .padding(.horizontal, metrics.leading)
        .frame(height: height)
        .opacity(dim ? 0.4 : 1)
        .background { StandaloneSelection(shown: layout == nil && selected, focused: focused) }
        .contentShape(Rectangle())
        .environment(\.backgroundProminence, emphasized ? .increased : .standard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    var accessibilityText: String {
        var parts = [commit.subject, commit.authorName, RelativeDate.text(commit.authorDate, now: now)]
        parts.append(contentsOf: refs.map(\.accessibilityText))
        return parts.joined(separator: ", ")
    }
}

struct CommitGraphCell: View {
    let row: GraphRow
    let lanes: Int
    let height: CGFloat
    var isWip = false
    var dim = false
    let emphasized: Bool

    var body: some View {
        if emphasized {
            Color(nsColor: .alternateSelectedControlTextColor)
                .frame(width: GraphCell.width(lanes: lanes), height: height)
                .mask { GraphCell(row: row, lanes: lanes, height: height, isWip: isWip, dim: dim) }
                .accessibilityHidden(true)
        } else {
            GraphCell(row: row, lanes: lanes, height: height, isWip: isWip, dim: dim)
        }
    }
}

struct SelectedRowPill: ViewModifier {
    let emphasized: Bool

    func body(content: Content) -> some View {
        if emphasized {
            content
                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                .environment(\.backgroundProminence, .standard)
        } else {
            content
        }
    }
}

struct StandaloneSelection: View {
    let shown: Bool
    let focused: Bool

    var body: some View {
        if shown {
            RoundedRectangle(cornerRadius: Vrai.Radius.sm, style: .continuous)
                .fill(Color(nsColor: focused ? .selectedContentBackgroundColor : .unemphasizedSelectedContentBackgroundColor))
        }
    }
}

struct SubjectText: View {
    let subject: String
    let query: String
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Text(attributed)
            .font(Font.Vrai.body)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    var attributed: AttributedString {
        var text = AttributedString(subject)
        guard !query.isEmpty, let range = subject.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { return text }
        let lower = subject.distance(from: subject.startIndex, to: range.lowerBound)
        let length = subject.distance(from: range.lowerBound, to: range.upperBound)
        let start = text.index(text.startIndex, offsetByCharacters: lower)
        let end = text.index(start, offsetByCharacters: length)
        text[start..<end].backgroundColor = prominence == .increased ? Color(nsColor: .alternateSelectedControlTextColor).opacity(0.25) : Color.Vrai.warningSoft
        return text
    }
}

struct WipRowView: View {
    let row: GraphRow
    let lanes: Int
    let height: CGFloat
    let files: Int
    let selected: Bool
    let focused: Bool
    let columns: CommitColumns
    var layout: CommitColumnLayout?

    var body: some View {
        let emphasized = selected && focused
        let metrics = layout ?? .standalone(lanes: lanes)
        HStack(spacing: 0) {
            CommitGraphCell(row: row, lanes: lanes, height: height, isWip: true, emphasized: emphasized)
                .frame(width: metrics.graph, alignment: .leading)
            Text("Uncommitted changes", bundle: .module)
                .font(Font.Vrai.headline)
                .italic()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, CommitColumnLayout.inset)
                .frame(maxWidth: .infinity, alignment: .leading)
            if columns.contains(.author) { Color.clear.frame(width: metrics.author) }
            if columns.contains(.date) { Color.clear.frame(width: metrics.date) }
            if columns.contains(.hash) {
                Text(n(files, "file"))
                    .font(Font.Vrai.caption)
                    .foregroundStyle(emphasized ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.Vrai.warning))
                    .lineLimit(1)
                    .padding(.horizontal, CommitColumnLayout.inset)
                    .frame(width: metrics.hash, alignment: .leading)
            }
        }
        .padding(.horizontal, metrics.leading)
        .frame(height: height)
        .background { StandaloneSelection(shown: layout == nil && selected, focused: focused) }
        .contentShape(Rectangle())
        .environment(\.backgroundProminence, emphasized ? .increased : .standard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Uncommitted changes, \(n(files, "file"))", bundle: .module))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}
