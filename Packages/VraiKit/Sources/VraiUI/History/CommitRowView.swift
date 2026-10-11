import SwiftUI
import VraiCore
import VraiGit

enum RefPills {
    static func byCommit(_ snapshot: RepositorySnapshot) -> [OID: [RefPillModel]] {
        var map: [OID: [RefPillModel]] = [:]
        func add(_ id: OID?, _ pill: RefPillModel) {
            guard let id else { return }
            map[id, default: []].append(pill)
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
    @Environment(\.expert) private var expert
    @Environment(\.vraiNow) private var now

    var body: some View {
        HStack(spacing: Vrai.Space.s12) {
            GraphCell(row: row, lanes: lanes, height: height, dim: dim)
            SubjectLayout(share: columns == [.date] ? Metrics.refsShareNarrow : Metrics.refsShare) {
                if !refs.isEmpty {
                    PillRow {
                        ForEach(refs) { RefPill(model: $0) }
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
            .frame(maxWidth: .infinity, alignment: .leading)
            if columns.contains(.author) {
                HStack(spacing: Vrai.Space.s6) {
                    Avatar(name: commit.authorName, size: Vrai.Space.s16)
                    Text(commit.authorName)
                        .lineLimit(1)
                }
                .font(Font.Vrai.callout)
                .foregroundStyle(Color.Vrai.textSecondary)
                .frame(width: Vrai.Size.colAuthor, alignment: .leading)
            }
            if columns.contains(.date) {
                Text(RelativeDate.text(commit.authorDate, now: now))
                    .font(Font.Vrai.callout)
                    .monospacedDigit()
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .lineLimit(1)
                    .frame(width: Vrai.Size.colDate, alignment: .leading)
                    .help(RelativeDate.full(commit.authorDate))
            }
            if columns.contains(.hash) {
                Text(commit.id.display(expert: expert))
                    .font(Font.Vrai.codeSmall)
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .frame(width: Vrai.Size.colHash, alignment: .trailing)
            }
        }
        .padding(.trailing, Vrai.Space.s12)
        .frame(height: height)
        .opacity(dim ? 0.4 : 1)
        .contentShape(Rectangle())
        .hoverHighlight(radius: Vrai.Radius.sm, selected: selected, selectedFill: focused ? Color.Vrai.accentSoft : Color.Vrai.fillActive)
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

struct SubjectText: View {
    let subject: String
    let query: String

    var body: some View {
        Text(attributed)
            .font(Font.Vrai.body)
            .foregroundStyle(Color.Vrai.text)
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
        text[start..<end].backgroundColor = Color.Vrai.warningSoft
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

    var body: some View {
        HStack(spacing: Vrai.Space.s12) {
            GraphCell(row: row, lanes: lanes, height: height, isWip: true)
            Text("Uncommitted changes", bundle: .module)
                .font(Font.Vrai.headline)
                .italic()
                .foregroundStyle(Color.Vrai.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if columns.contains(.author) { Color.clear.frame(width: Vrai.Size.colAuthor) }
            if columns.contains(.date) { Color.clear.frame(width: Vrai.Size.colDate) }
            if columns.contains(.hash) {
                Text(n(files, "file"))
                    .font(Font.Vrai.caption)
                    .foregroundStyle(Color.Vrai.warning)
                    .lineLimit(1)
                    .frame(width: Vrai.Size.colHash, alignment: .trailing)
            }
        }
        .padding(.trailing, Vrai.Space.s12)
        .frame(height: height)
        .contentShape(Rectangle())
        .hoverHighlight(radius: Vrai.Radius.sm, selected: selected, selectedFill: focused ? Color.Vrai.accentSoft : Color.Vrai.fillActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Uncommitted changes, \(n(files, "file"))", bundle: .module))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

struct HistoryHeader: View {
    let graphWidth: CGFloat
    let columns: CommitColumns

    var body: some View {
        HStack(spacing: Vrai.Space.s12) {
            Text("Graph", bundle: .module)
                .fixedSize()
                .frame(minWidth: graphWidth, alignment: .leading)
            Text("Description", bundle: .module)
                .frame(maxWidth: .infinity, alignment: .leading)
            if columns.contains(.author) { Text("Author", bundle: .module).frame(width: Vrai.Size.colAuthor, alignment: .leading) }
            if columns.contains(.date) { Text("Date", bundle: .module).frame(width: Vrai.Size.colDate, alignment: .leading) }
            if columns.contains(.hash) { Text("Commit", bundle: .module).frame(width: Vrai.Size.colHash, alignment: .trailing) }
        }
        .font(Font.Vrai.captionStrong)
        .foregroundStyle(Color.Vrai.textTertiary)
        .lineLimit(1)
        .padding(.leading, Vrai.Space.s4)
        .padding(.trailing, Vrai.Space.s12)
        .frame(height: Vrai.Space.s24)
        .background(Color.Vrai.bg)
        .hairline(.bottom)
    }
}
