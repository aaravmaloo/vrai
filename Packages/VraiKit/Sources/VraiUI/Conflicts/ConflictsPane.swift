import SwiftUI
import VraiCore
import VraiGit

struct ConflictsPane: View {
    var path: String?
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(\.expert) private var expert
    @State private var session = ConflictSession()
    @State private var replayed: Set<String> = []

    init(path: String? = nil) {
        self.path = path
    }

    var conflicted: [WorkingFile] {
        store.snapshot?.working.filter { $0.status == .conflicted } ?? []
    }

    var currentPath: String? {
        let paths = conflicted.map(\.path)
        if let path, paths.contains(path) { return path }
        if let selected = store.selectedPath, paths.contains(selected) { return selected }
        if let chosen = session.chosen, paths.contains(chosen) { return chosen }
        return paths.first
    }

    var body: some View {
        if let current = currentPath {
            let kind = store.snapshot?.conflicts.first { $0.path == current }?.kind ?? .bothModified
            VStack(spacing: 0) {
                bar(current)
                head(current, kind: kind)
                if replayed.contains(current) {
                    ReplayedResolutionNote()
                }
                content(current, kind: kind)
            }
            .background(Color.Vrai.bg)
            .task(id: ReloadKey(path: current, working: store.snapshot?.working ?? [], expert: expert)) {
                await session.load(path: current, store: store, expert: expert)
                replayed = await store.replayedResolutions()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("conflicts-pane")
        } else {
            EmptyStateView(icon: "checkmark.circle", title: String(localized: "No conflicts", bundle: .module), message: String(localized: "Every file merged cleanly.", bundle: .module), small: true)
                .background(Color.Vrai.bg)
        }
    }

    struct ReloadKey: Hashable {
        var path: String
        var working: [WorkingFile]
        var expert: Bool
    }

    func bar(_ path: String) -> some View {
        HStack(spacing: Vrai.Space.s8) {
            PathBar(path: path)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            FileStatusTile(status: .conflicted)
            IconMenu(icon: "ellipsis.circle", label: String(localized: "File actions", bundle: .module)) {
                Button(String(localized: "Accept current for the whole file", bundle: .module), systemImage: "checkmark.circle") {
                    session.resolveFile(path, with: .ours, window: window)
                }
                Button(String(localized: "Accept incoming for the whole file", bundle: .module), systemImage: "checkmark.circle") {
                    session.resolveFile(path, with: .theirs, window: window)
                }
                Button(String(localized: "Start over", bundle: .module), systemImage: "arrow.counterclockwise") {
                    CoverageActions.confirmStartOver(window, path: path, everyFile: false) { session.startOver(path, everyFile: false, window: window) }
                }
                .disabled(!(store.snapshot?.conflicts.first { $0.path == path }?.kind ?? .bothModified).hasMarkers)
                .modifierKeyAlternate(.option) {
                    Button(String(localized: "Start over with every file", bundle: .module), systemImage: "arrow.counterclockwise") {
                        CoverageActions.confirmStartOver(window, path: path, everyFile: true) { session.startOver(path, everyFile: true, window: window) }
                    }
                }
                Divider()
                Button(String(localized: "Open in merge tool", bundle: .module), systemImage: "arrow.triangle.merge") {
                    RewriteActions.openMergeTool(window, path: path)
                }
                Button(String(localized: "Reveal in Finder", bundle: .module), systemImage: "folder") {
                    window.reveal(path)
                }
                Button(String(localized: "Copy path", bundle: .module), systemImage: "doc.on.doc") {
                    window.copy(path, label: String(localized: "path", bundle: .module))
                }
            }
        }
        .padding(.leading, Vrai.Space.s12)
        .padding(.trailing, Vrai.Space.s8)
        .frame(height: Metrics.paneBarHeight)
        .hairline(.bottom)
    }

    func head(_ path: String, kind: ConflictFile.Kind) -> some View {
        let name = PathParts.split(path).name
        let left = session.path == path ? session.left : 0
        let structural = !kind.hasMarkers
        let busy = store.busy.contains("markResolved")
        return HStack(spacing: Vrai.Space.s8) {
            Symbol(left > 0 || structural ? "exclamationmark.triangle.fill" : "checkmark.circle.fill", font: Font.Vrai.title3)
                .foregroundStyle(left > 0 || structural ? Color.Vrai.danger : Color.Vrai.success)
            Text(structural ? Self.structuralText(kind, name: name) : left > 0 ? String(localized: "\(n(left, "conflict")) left in \(name). Pick a side for each, or open it in your merge tool.", bundle: .module) : String(localized: "Every conflict in \(name) has a resolution. Mark it resolved to stage it.", bundle: .module))
                .font(Font.Vrai.callout)
                .foregroundStyle(Color.Vrai.textSecondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("conflict-summary")
            VraiButton(title: String(localized: "Merge tool", bundle: .module), icon: "arrow.triangle.merge", size: .small) {
                RewriteActions.openMergeTool(window, path: path)
            }
            .disabled(structural)
            Button {
                RewriteActions.markResolved(window, path: path) { done in
                    if done { session.advance(after: path, store: store) }
                }
            } label: {
                HStack(spacing: Vrai.Space.s4) {
                    if busy { Spinner() } else { Symbol("checkmark", font: Font.Vrai.callout) }
                    Text("Mark as resolved", bundle: .module)
                }
            }
            .buttonStyle(VraiButtonStyle(variant: .primary, size: .small))
            .disabled(left > 0 || structural || busy || session.path != path || session.working != nil)
            .accessibilityIdentifier("mark-resolved")
        }
        .padding(.vertical, Vrai.Space.s8)
        .padding(.horizontal, Vrai.Space.s12)
        .background(Color.Vrai.bgSubtle)
        .hairline(.bottom)
    }

    @ViewBuilder func content(_ path: String, kind: ConflictFile.Kind) -> some View {
        if !kind.hasMarkers {
            ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Vrai.Space.s12) {
                RewriteCallout(tone: .warning, title: Self.structuralTitle(kind, name: PathParts.split(path).name), message: String(localized: "Keep the current version or take the incoming one. Taking the side that deleted it removes the file.", bundle: .module))
                HStack(spacing: Vrai.Space.s8) {
                    VraiButton(title: String(localized: "Accept current", bundle: .module), size: .small) {
                        session.resolveFile(path, with: .ours, window: window)
                    }
                    VraiButton(title: String(localized: "Accept incoming", bundle: .module), size: .small) {
                        session.resolveFile(path, with: .theirs, window: window)
                    }
                }
            }
            .padding(Vrai.Space.s16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else if session.path == path {
            ConflictBlocksView(session: session, path: path, oursLabel: oursLabel, window: window)
        } else {
            Spinner().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    var oursLabel: (String) -> String {
        let branch = store.snapshot?.head.branchName
        let merging: Bool = {
            if case .merging? = store.snapshot?.state { return true }
            return false
        }()
        return { label in
            if label == "HEAD", merging, let branch { return "HEAD, " + branch }
            return label
        }
    }

    static func structuralTitle(_ kind: ConflictFile.Kind, name: String) -> String {
        switch kind {
        case .deletedByThem: String(localized: "The incoming side deleted \(name)", bundle: .module)
        case .deletedByUs: String(localized: "The current side deleted \(name)", bundle: .module)
        case .addedByUs: String(localized: "Only the current side added \(name)", bundle: .module)
        case .addedByThem: String(localized: "Only the incoming side added \(name)", bundle: .module)
        case .bothDeleted: String(localized: "Both sides deleted \(name)", bundle: .module)
        case .bothModified, .bothAdded: String(localized: "Both sides changed \(name)", bundle: .module)
        }
    }

    static func structuralText(_ kind: ConflictFile.Kind, name: String) -> String {
        switch kind {
        case .deletedByThem: String(localized: "\(name) was deleted on the incoming side and changed on the current one.", bundle: .module)
        case .deletedByUs: String(localized: "\(name) was deleted on the current side and changed on the incoming one.", bundle: .module)
        case .bothDeleted: String(localized: "Both sides deleted \(name). Take either side to remove it.", bundle: .module)
        default: String(localized: "\(name) needs a decision about the whole file.", bundle: .module)
        }
    }
}

extension ConflictFile.Kind {
    var hasMarkers: Bool {
        self == .bothModified || self == .bothAdded
    }
}

@MainActor
@Observable
final class ConflictSession {
    var path: String?
    var chosen: String?
    var original = ""
    var blocks: [ConflictBlock] = []
    var choices: [Int: ConflictChoice] = [:]
    var expected: String?
    var bases: [Int: [String]] = [:]
    var working: Int?
    var language = "text"
    @ObservationIgnored var store: RepositoryStore?

    var conflicts: [ConflictBlock.Conflict] {
        blocks.compactMap { if case .conflict(let conflict) = $0 { conflict } else { nil } }
    }

    var left: Int {
        conflicts.filter { choices[$0.index] == nil }.count
    }

    func load(path: String, store: RepositoryStore, expert: Bool) async {
        self.store = store
        guard working == nil else { return }
        guard let text = await store.conflictText(path: path) else { return }
        guard working == nil else { return }
        if path == self.path, text == expected {
            if expert, bases.isEmpty, choices.isEmpty, !conflicts.isEmpty { bases = await store.conflictBases(path: path) }
            return
        }
        self.path = path
        chosen = path
        original = text
        expected = text
        blocks = ConflictParser.blocks(in: text)
        choices = [:]
        language = SyntaxHighlighter.language(for: path)
        bases = expert && !conflicts.isEmpty ? await store.conflictBases(path: path) : [:]
    }

    func currentIndex(of index: Int, resolved: [Int: ConflictChoice]) -> Int {
        1 + conflicts.filter { $0.index < index && resolved[$0.index] == nil }.count
    }

    func resolve(_ index: Int, with choice: ConflictChoice, window: WindowModel) {
        guard let path, working == nil, choices[index] == nil else { return }
        let store = window.store
        working = index
        Task {
            defer { working = nil }
            do {
                try await store.resolve(path: path, block: currentIndex(of: index, resolved: choices), with: choice)
                choices[index] = choice
                expected = await store.conflictText(path: path)
            } catch {
                expected = await store.conflictText(path: path)
                RewriteActions.report(error, window, failure: String(localized: "That conflict wasn't resolved", bundle: .module))
            }
        }
    }

    func undo(_ index: Int, window: WindowModel) {
        guard let path, working == nil, choices[index] != nil else { return }
        let store = window.store
        working = index
        var remaining = choices
        remaining[index] = nil
        let text = original
        Task {
            defer { working = nil }
            do {
                try await store.restoreConflictText(path: path, text: text)
                var applied: [Int: ConflictChoice] = [:]
                choices = [:]
                for (block, choice) in remaining.sorted(by: { $0.key < $1.key }) {
                    try await store.resolve(path: path, block: currentIndex(of: block, resolved: applied), with: choice)
                    applied[block] = choice
                }
                choices = applied
                expected = await store.conflictText(path: path)
            } catch {
                expected = await store.conflictText(path: path)
                RewriteActions.report(error, window, failure: String(localized: "The conflict didn't come back", bundle: .module))
            }
        }
    }

    func resolveFile(_ path: String, with choice: ConflictChoice, window: WindowModel) {
        guard working == nil else { return }
        let store = window.store
        working = 0
        Task {
            defer { working = nil }
            do {
                try await store.resolve(path: path, block: nil, with: choice)
                if self.path == path {
                    for conflict in conflicts where choices[conflict.index] == nil { choices[conflict.index] = choice }
                    expected = await store.conflictText(path: path)
                }
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "The file wasn't resolved", bundle: .module))
            }
        }
    }

    func startOver(_ path: String, everyFile: Bool, window: WindowModel) {
        guard working == nil else { return }
        let store = window.store
        let expert = window.preferences.expert
        let name = PathParts.split(path).name
        working = 0
        Task {
            var failure: Error?
            var conflicted = true
            var count = 1
            do {
                if everyFile {
                    count = try await store.startOverEveryFile().count
                } else {
                    conflicted = try await store.startOver(path: path)
                }
            } catch {
                failure = error
            }
            working = nil
            expected = nil
            await load(path: path, store: store, expert: expert)
            if let failure {
                RewriteActions.report(failure, window, failure: String(localized: "The conflict didn't come back", bundle: .module))
            } else if everyFile {
                window.toasts.show(Toast(message: String(localized: "Started over with \(n(count, "file"))", bundle: .module), detail: String(localized: "Every conflict is back as the merge left it.", bundle: .module), icon: "arrow.counterclockwise"))
            } else if conflicted {
                window.toasts.show(Toast(message: String(localized: "Started over with \(name)", bundle: .module), detail: String(localized: "Every conflict is back as the merge left it.", bundle: .module), icon: "arrow.counterclockwise"))
            } else {
                window.toasts.show(Toast(tone: .success, message: String(localized: "\(name) merged cleanly this time", bundle: .module), detail: String(localized: "git staged the merged file.", bundle: .module), icon: "checkmark.circle"))
            }
        }
    }

    func advance(after path: String, store: RepositoryStore) {
        let remaining = store.snapshot?.working.filter { $0.status == .conflicted }.map(\.path) ?? []
        chosen = remaining.first { $0 != path }
        if store.selectedPath == path, let next = chosen { store.selectFile(next) }
    }
}

struct ConflictBlocksView: View {
    let session: ConflictSession
    let path: String
    let oursLabel: (String) -> String
    let window: WindowModel
    @Environment(\.expert) private var expert
    @Environment(Preferences.self) private var preferences

    var body: some View {
        let metrics = DiffMetrics(codeSize: preferences.codeSize)
        let rows = ConflictRows.build(session.blocks, choices: session.choices, bases: session.bases)
        GeometryReader { geometry in
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    switch row.kind {
                    case .context(let lines):
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(lines) { line in
                                CodeLine(number: line.number, text: line.text, language: session.language, metrics: metrics, wrap: preferences.wrap)
                            }
                        }
                    case .conflict(let conflict, let ours, let base, let theirs):
                        ConflictCard(
                            conflict: conflict,
                            ours: ours,
                            base: expert ? base : nil,
                            theirs: theirs,
                            oursLabel: oursLabel(conflict.oursLabel),
                            language: session.language,
                            metrics: metrics,
                            wrap: preferences.wrap,
                            working: session.working == conflict.index,
                            disabled: session.working != nil,
                            expert: expert
                        ) { choice in
                            session.resolve(conflict.index, with: choice, window: window)
                        }
                    case .resolved(let conflict, let choice, let kept):
                        ResolvedCard(conflict: conflict, choice: choice, kept: kept, language: session.language, metrics: metrics, wrap: preferences.wrap, disabled: session.working != nil) {
                            session.undo(conflict.index, window: window)
                        }
                    }
                }
            }
            .padding(.vertical, Vrai.Space.s8)
            .frame(width: geometry.size.width, alignment: .leading)
            .clipped()
        }
        }
        .background(Color.Vrai.bg)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Conflicts", bundle: .module))
    }
}

struct NumberedLine: Identifiable, Hashable {
    var id: Int
    var number: Int?
    var text: String
}

struct ConflictRows {
    enum Kind {
        case context([NumberedLine])
        case conflict(ConflictBlock.Conflict, ours: [NumberedLine], base: [NumberedLine]?, theirs: [NumberedLine])
        case resolved(ConflictBlock.Conflict, ConflictChoice, [NumberedLine])
    }

    struct Row: Identifiable {
        var id: Int
        var kind: Kind
    }

    static func build(_ blocks: [ConflictBlock], choices: [Int: ConflictChoice], bases: [Int: [String]]) -> [Row] {
        var rows: [Row] = []
        var number = 1
        var serial = 0
        func numbered(_ lines: [String], counting: Bool) -> [NumberedLine] {
            lines.map { text in
                serial += 1
                defer { if counting { number += 1 } }
                return NumberedLine(id: serial, number: counting ? number : nil, text: text)
            }
        }
        for (offset, block) in blocks.enumerated() {
            switch block {
            case .context(let lines, _):
                rows.append(Row(id: offset, kind: .context(numbered(lines, counting: true))))
            case .conflict(let conflict):
                if let choice = choices[conflict.index] {
                    let kept: [String]
                    switch choice {
                    case .ours: kept = conflict.ours
                    case .theirs: kept = conflict.theirs
                    case .both: kept = conflict.ours + conflict.theirs
                    case .base: kept = conflict.base ?? bases[conflict.index] ?? []
                    }
                    rows.append(Row(id: offset, kind: .resolved(conflict, choice, numbered(kept, counting: true))))
                } else {
                    let ours = numbered(conflict.ours, counting: true)
                    let base = (conflict.base ?? bases[conflict.index]).map { numbered($0, counting: false) }
                    let theirs = numbered(conflict.theirs, counting: false)
                    rows.append(Row(id: offset, kind: .conflict(conflict, ours: ours, base: base, theirs: theirs)))
                }
            }
        }
        return rows
    }
}

struct CodeLine: View {
    let number: Int?
    let text: String
    let language: String
    let metrics: DiffMetrics
    let wrap: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            LineNumber(number: number, font: metrics.numberFont)
                .frame(minHeight: metrics.lineHeight)
            Text(CodeRenderer.attributed(text, language: language))
                .font(metrics.codeFont)
                .foregroundStyle(Color.Vrai.text)
                .lineLimit(wrap ? nil : 1)
                .fixedSize(horizontal: !wrap, vertical: true)
                .padding(.trailing, Vrai.Space.s16)
                .frame(maxWidth: .infinity, minHeight: metrics.lineHeight, alignment: .leading)
                .clipped()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

struct ConflictCard: View {
    let conflict: ConflictBlock.Conflict
    let ours: [NumberedLine]
    let base: [NumberedLine]?
    let theirs: [NumberedLine]
    let oursLabel: String
    let language: String
    let metrics: DiffMetrics
    let wrap: Bool
    let working: Bool
    let disabled: Bool
    let expert: Bool
    let resolve: (ConflictChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Vrai.Space.s8) {
                if working {
                    Spinner()
                } else {
                    Symbol("exclamationmark.triangle.fill", font: Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.danger)
                }
                Text("Conflict \(conflict.index)", bundle: .module)
                    .font(Font.Vrai.captionStrong)
                    .foregroundStyle(Color.Vrai.text)
                Spacer(minLength: Vrai.Space.s8)
                HStack(spacing: Vrai.Space.s4) {
                    choiceButton(String(localized: "Accept current", bundle: .module), .ours, variant: .secondary, id: "accept-current")
                    choiceButton(String(localized: "Accept incoming", bundle: .module), .theirs, variant: .secondary, id: "accept-incoming")
                    choiceButton(String(localized: "Accept both", bundle: .module), .both, variant: .plain, id: "accept-both")
                    if expert, base != nil {
                        choiceButton(String(localized: "Accept base", bundle: .module), .base, variant: .plain, id: "accept-base")
                    }
                }
                .fixedSize()
            }
            .padding(.vertical, Vrai.Space.s4)
            .padding(.leading, Vrai.Space.s12)
            .padding(.trailing, Vrai.Space.s6)
            .frame(minHeight: Vrai.Size.control + Vrai.Space.s6)
            .background(Color.Vrai.bgSubtle)
            .hairline(.bottom)
            side(String(localized: "Current \u{00B7} \(oursLabel)", bundle: .module), lines: ours, tint: Color.Vrai.conflictOurs, background: Color.Vrai.conflictOursBg, dashed: false)
            if let base {
                side(String(localized: "Base \u{00B7} \(conflict.baseLabel ?? String(localized: "common ancestor", bundle: .module))", bundle: .module), lines: base, tint: Color.Vrai.textSecondary, background: Color.Vrai.bgSubtle, dashed: true)
            }
            side(String(localized: "Incoming \u{00B7} \(conflict.theirsLabel)", bundle: .module), lines: theirs, tint: Color.Vrai.conflictTheirs, background: Color.Vrai.conflictTheirsBg, dashed: true)
        }
        .clipShape(RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous).strokeBorder(Color.Vrai.border, lineWidth: Metrics.hairline))
        .padding(.vertical, Vrai.Space.s6)
        .padding(.horizontal, Vrai.Space.s8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conflict-\(conflict.index)")
    }

    func choiceButton(_ title: String, _ choice: ConflictChoice, variant: ButtonVariant, id: String) -> some View {
        Button {
            resolve(choice)
        } label: {
            Text(title)
        }
        .buttonStyle(VraiButtonStyle(variant: variant, size: .small))
        .disabled(disabled)
        .accessibilityIdentifier("\(id)-\(conflict.index)")
    }

    func side(_ label: String, lines: [NumberedLine], tint: Color, background: Color, dashed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(Font.Vrai.captionStrong)
                .foregroundStyle(tint)
                .padding(.top, Vrai.Space.s6)
                .padding(.bottom, Vrai.Space.s2)
                .padding(.horizontal, Vrai.Space.s12)
            ForEach(lines) { line in
                CodeLine(number: line.number, text: line.text, language: language, metrics: metrics, wrap: wrap)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(alignment: .top) {
            if dashed {
                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: Metrics.hairline, dash: [Vrai.Space.s4, Vrai.Space.s4]))
                    .foregroundStyle(Color.Vrai.borderStrong)
                    .frame(height: Metrics.hairline)
            }
        }
    }
}

struct ResolvedCard: View {
    let conflict: ConflictBlock.Conflict
    let choice: ConflictChoice
    let kept: [NumberedLine]
    let language: String
    let metrics: DiffMetrics
    let wrap: Bool
    let disabled: Bool
    let undo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Vrai.Space.s8) {
                Symbol("checkmark.circle.fill", font: Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.success)
                Text(label)
                    .font(Font.Vrai.caption)
                    .foregroundStyle(Color.Vrai.textSecondary)
                Spacer(minLength: Vrai.Space.s8)
                Button(action: undo) {
                    Text("Undo", bundle: .module)
                        .font(Font.Vrai.captionStrong)
                        .foregroundStyle(Color.Vrai.accentText)
                        .padding(.horizontal, Vrai.Space.s6)
                        .frame(height: Vrai.Space.s20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .accessibilityIdentifier("undo-conflict-\(conflict.index)")
            }
            .padding(.vertical, Vrai.Space.s4)
            .padding(.leading, Vrai.Space.s12)
            .padding(.trailing, Vrai.Space.s6)
            .frame(minHeight: Vrai.Size.control + Vrai.Space.s6)
            .background(Color.Vrai.successSoft)
            .hairline(.bottom)
            ForEach(kept) { line in
                CodeLine(number: line.number, text: line.text, language: language, metrics: metrics, wrap: wrap)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous).strokeBorder(Color.Vrai.border, lineWidth: Metrics.hairline))
        .padding(.vertical, Vrai.Space.s6)
        .padding(.horizontal, Vrai.Space.s8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("resolved-\(conflict.index)")
    }

    var label: String {
        switch choice {
        case .ours: String(localized: "Kept current", bundle: .module)
        case .theirs: String(localized: "Kept incoming", bundle: .module)
        case .both: String(localized: "Kept both, current first", bundle: .module)
        case .base: String(localized: "Kept base", bundle: .module)
        }
    }
}
