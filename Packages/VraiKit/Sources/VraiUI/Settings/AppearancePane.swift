import SwiftUI
import VraiCore
import VraiGit

struct AppearancePane: View {
    let context: SettingsContext
    @Environment(Preferences.self) private var preferences
    @Environment(\.settingsNarrow) private var narrow

    var rowHeight: CGFloat {
        switch preferences.density {
        case .compact: Vrai.Size.rowCompact
        case .regular: Vrai.Size.row
        case .comfortable: Vrai.Size.rowComfortable
        }
    }

    var body: some View {
        SettingsForm {
            SettingsSection(String(localized: "Look", bundle: .module)) {
                SettingsRow(String(localized: "Appearance", bundle: .module), stacked: narrow) {
                    SettingsSegments(
                        label: String(localized: "Appearance", bundle: .module),
                        items: [
                            SegmentItem(value: Preferences.Theme.system, icon: "circle.lefthalf.filled", title: String(localized: "System", bundle: .module), label: String(localized: "System", bundle: .module)),
                            SegmentItem(value: Preferences.Theme.light, icon: "sun.max", title: String(localized: "Light", bundle: .module), label: String(localized: "Light", bundle: .module)),
                            SegmentItem(value: Preferences.Theme.dark, icon: "moon", title: String(localized: "Dark", bundle: .module), label: String(localized: "Dark", bundle: .module))
                        ],
                        selection: preferences.theme,
                        id: "settings.theme"
                    ) { preferences.theme = $0 }
                }
                SettingsRow(String(localized: "Density", bundle: .module), description: String(localized: "History rows are \(Int(rowHeight)) points tall.", bundle: .module), stacked: narrow) {
                    SettingsSegments(
                        label: String(localized: "Density", bundle: .module),
                        items: [
                            SegmentItem(value: Preferences.Density.compact, title: String(localized: "Compact", bundle: .module), label: String(localized: "Compact", bundle: .module)),
                            SegmentItem(value: Preferences.Density.regular, title: String(localized: "Regular", bundle: .module), label: String(localized: "Regular", bundle: .module)),
                            SegmentItem(value: Preferences.Density.comfortable, title: String(localized: "Comfortable", bundle: .module), label: String(localized: "Comfortable", bundle: .module))
                        ],
                        selection: preferences.density,
                        id: "settings.density"
                    ) { preferences.density = $0 }
                }
            }
            SettingsSection(String(localized: "Diffs and code", bundle: .module), footer: String(localized: "Vrai settings. git diff in Terminal is unaffected.", bundle: .module)) {
                SettingsRow(String(localized: "Layout", bundle: .module), stacked: narrow) {
                    SettingsSegments(
                        label: String(localized: "Diff layout", bundle: .module),
                        items: [
                            SegmentItem(value: Preferences.DiffMode.unified, icon: "rectangle", title: String(localized: "Unified", bundle: .module), label: String(localized: "Unified", bundle: .module)),
                            SegmentItem(value: Preferences.DiffMode.split, icon: "rectangle.split.2x1", title: String(localized: "Split", bundle: .module), label: String(localized: "Split", bundle: .module))
                        ],
                        selection: preferences.diffMode,
                        id: "settings.diffMode"
                    ) { preferences.diffMode = $0 }
                }
                SettingsRow(String(localized: "Code size", bundle: .module), stacked: true) {
                    SettingsSlider(label: String(localized: "Code size", bundle: .module), value: preferences.codeSize, range: 11...15, step: 1, format: { String(localized: "\($0) pt", bundle: .module) }, id: "settings.codeSize") { preferences.codeSize = $0 }
                }
                SettingsRow(String(localized: "Show whitespace", bundle: .module), description: String(localized: "Marks spaces and tabs in changed lines.", bundle: .module)) {
                    SettingsSwitch(label: String(localized: "Show whitespace", bundle: .module), isOn: preferences.whitespace, id: "settings.whitespace") { preferences.whitespace = $0 }
                }
                SettingsRow(String(localized: "Wrap long lines", bundle: .module)) {
                    SettingsSwitch(label: String(localized: "Wrap long lines", bundle: .module), isOn: preferences.wrap, id: "settings.wrap") { preferences.wrap = $0 }
                }
                SettingsRow(String(localized: "Preview", bundle: .module), stacked: true) {
                    AppearancePreview(rowHeight: rowHeight, narrow: narrow, now: context.app.now)
                }
            }
            SettingsSection(String(localized: "Windows", bundle: .module)) {
                SettingsRow(String(localized: "Show remote branches in the sidebar", bundle: .module), description: String(localized: "Under Remotes, grouped by remote.", bundle: .module)) {
                    SettingsSwitch(label: String(localized: "Show remote branches in the sidebar", bundle: .module), isOn: preferences.showRemotes, id: "settings.showRemotes") { preferences.showRemotes = $0 }
                }
                SettingsRow(String(localized: "Show the inspector", bundle: .module), description: String(localized: "Commit details beside history.", bundle: .module)) {
                    SettingsSwitch(label: String(localized: "Show the inspector", bundle: .module), isOn: preferences.inspector, id: "settings.inspector") { preferences.inspector = $0 }
                }
            }
        }
    }
}

struct AppearancePreview: View {
    let rowHeight: CGFloat
    let narrow: Bool
    let now: Date
    @Environment(Preferences.self) private var preferences

    var body: some View {
        let sample = PreviewSample.make(now: now)
        let metrics = DiffMetrics(codeSize: preferences.codeSize)
        VStack(spacing: 0) {
            ForEach(sample.commits.indices, id: \.self) { index in
                CommitRowView(
                    commit: sample.commits[index],
                    row: sample.rows[index],
                    lanes: sample.lanes,
                    height: rowHeight,
                    refs: sample.refs[index],
                    selected: index == 0,
                    focused: false,
                    dim: false,
                    query: "",
                    columns: narrow ? [.date] : .all,
                    signature: sample.commits[index].signature
                )
                .frame(height: rowHeight)
            }
            Rectangle()
                .fill(Color.Vrai.separator)
                .frame(height: Metrics.hairline)
            DiffView(diff: sample.diff, mode: narrow ? .unified : preferences.diffMode, wrap: preferences.wrap, whitespace: preferences.whitespace, codeSize: preferences.codeSize)
                .frame(height: metrics.lineHeight * CGFloat(narrow && preferences.wrap ? 9 : 7) + Metrics.hunkHeight)
        }
        .background(Color.Vrai.bg)
        .clipShape(RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous).strokeBorder(Color.Vrai.separator, lineWidth: Metrics.hairline))
        .environment(\.expert, preferences.expert)
        .environment(\.vraiNow, now)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Preview of the history list and a diff with these settings", bundle: .module))
        .accessibilityIdentifier("settings.preview")
    }
}

struct PreviewSample {
    var commits: [Commit]
    var rows: [GraphRow]
    var lanes: Int
    var refs: [[RefPillModel]]
    var diff: FileDiff

    static let patch = """
    diff --git a/Sources/VraiGit/Graph/LaneLayout.swift b/Sources/VraiGit/Graph/LaneLayout.swift
    index 3f2a1c4..8e2a6c0 100644
    --- a/Sources/VraiGit/Graph/LaneLayout.swift
    +++ b/Sources/VraiGit/Graph/LaneLayout.swift
    @@ -41,4 +41,5 @@ struct LaneLayout {
         func color(for lane: Int) -> Color {
             let palette = Lane.palette
    -        return palette[lane % 8]
    +        let index = (lane % palette.count + palette.count) % palette.count
    +        return palette[index]
         }

    """

    static func oid(_ digit: Character) -> OID {
        OID(String(repeating: digit, count: 40))!
    }

    static func make(now: Date) -> PreviewSample {
        let ids = [oid("a"), oid("b"), oid("c"), oid("d"), oid("e")]
        let parents: [[OID]] = [[ids[1]], [ids[2], ids[3]], [ids[4]], [ids[4]], []]
        let subjects = [
            "Graph: keep lane colors stable when branches merge",
            "Merge branch 'fix/rebase-banner'",
            "Diff: highlight words that changed inside a line",
            "Rebase: show the stopped commit in the banner",
            "Release 0.9.1"
        ]
        let authors = ["Avery Chen", "Avery Chen", "Mira Okafor", "Jonas Berg", "Avery Chen"]
        let hours: [Double] = [1, 5, 26, 30, 72]
        let signatures: [SignatureState] = [.verified, .verified, .unknownKey, .unsigned, .verified]
        let commits = ids.indices.map { index in
            let date = now.addingTimeInterval(-hours[index] * 3600)
            let email = authors[index].lowercased().replacingOccurrences(of: " ", with: ".") + "@vrai.app"
            return Commit(id: ids[index], parents: parents[index], authorName: authors[index], authorEmail: email, authorDate: date, committerName: authors[index], committerEmail: email, committerDate: date, subject: subjects[index], signature: signatures[index])
        }
        let layout = LaneLayout.layout(commits.map { LayoutCommit(id: $0.id, parents: $0.parents) }, head: ids[0])
        let refs: [[RefPillModel]] = [
            [RefPillModel(kind: .branch, name: "feature/graph-renderer", lane: layout.rows.first?.color ?? 0, current: true)],
            [],
            [],
            [RefPillModel(kind: .branch, name: "fix/rebase-banner", lane: layout.rows.count > 3 ? layout.rows[3].color : 1)],
            [RefPillModel(kind: .tag, name: "v0.9.1")]
        ]
        let diff = PatchParser.parse(patch).first ?? FileDiff(path: "Sources/VraiGit/Graph/LaneLayout.swift", status: .modified)
        return PreviewSample(commits: commits, rows: layout.rows, lanes: max(1, layout.lanes), refs: refs, diff: diff)
    }
}
