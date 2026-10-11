import SwiftUI
import VraiCore
import VraiGit

struct BlameView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(\.expert) private var expert
    @Environment(\.widthClass) private var widthClass
    @State private var lines: PlacesLoad<[BlameLine]> = .loading
    @State private var selected: OID?
    @State private var attempt = 0

    struct LoadKey: Hashable {
        var focus: FileFocus?
        var head: OID?
        var attempt: Int
    }

    var body: some View {
        ChangesFittedFrame {
            VStack(spacing: 0) {
                bar
                content
            }
        }
        .background(Color.Vrai.bg)
        .task(id: LoadKey(focus: store.fileFocus, head: store.fileFocus?.revision == nil ? store.snapshot?.headOID : nil, attempt: attempt)) { await load() }
        .accessibilityIdentifier("blame-view")
    }

    func load() async {
        guard let focus = store.fileFocus else { return }
        lines = .loading
        selected = nil
        do {
            lines = .loaded(try await store.blame(path: focus.path, at: focus.revision))
        } catch let error as GitError {
            lines = .failed(error)
        } catch {
            lines = .failed(GitError(.unknown(exit: -1, stderr: String(describing: error))))
        }
    }

    var revisionLabel: String {
        guard let revision = store.fileFocus?.revision, revision != "HEAD" else { return String(localized: "Blame at HEAD", bundle: .module) }
        return String(localized: "Blame at \(OID(revision)?.short(expert: expert) ?? revision)", bundle: .module)
    }

    var previous: BlameLine? {
        guard let selected, let items = lines.value else { return nil }
        return items.first { $0.commit == selected && $0.previous != nil }
    }

    var bar: some View {
        HStack(spacing: Vrai.Space.s8) {
            Button {
                window.show(.history)
            } label: {
                HStack(spacing: Vrai.Space.s4) {
                    Symbol("chevron.left", font: Font.Vrai.callout)
                    if widthClass > .compact { Text("History", bundle: .module) }
                }
            }
            .buttonStyle(VraiButtonStyle(variant: .plain, size: .small))
            .help(String(localized: "Back to history", bundle: .module))
            .accessibilityLabel(String(localized: "Back to history", bundle: .module))
            .accessibilityIdentifier("blame-back")
            if let focus = store.fileFocus {
                PathBar(path: focus.path)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                if widthClass > .narrow {
                    Text(revisionLabel)
                        .font(Font.Vrai.caption)
                        .foregroundStyle(Color.Vrai.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityIdentifier("blame-revision")
                }
            } else {
                Spacer(minLength: 0)
            }
            Button {
                stepBack()
            } label: {
                HStack(spacing: Vrai.Space.s4) {
                    Symbol("arrow.uturn.backward", font: Font.Vrai.callout)
                    if widthClass > .compact { Text("Blame before this change", bundle: .module) }
                }
            }
            .buttonStyle(VraiButtonStyle(variant: .secondary, size: .small))
            .disabled(previous == nil)
            .help(String(localized: "Blame before this change", bundle: .module))
            .accessibilityLabel(String(localized: "Blame before this change", bundle: .module))
            .accessibilityIdentifier("blame-before")
        }
        .padding(.leading, Vrai.Space.s8)
        .padding(.trailing, Vrai.Space.s8)
        .frame(height: Metrics.paneBarHeight)
        .hairline(.bottom)
    }

    func stepBack() {
        guard let line = previous, let parent = line.previous, let focus = store.fileFocus else { return }
        let short = line.commit.short(expert: expert)
        window.openBlame(path: line.previousPath ?? focus.path, revision: parent.rawValue)
        window.toasts.show(Toast(message: String(localized: "Blaming the commit before \(short)", bundle: .module), detail: String(localized: "Lines changed later show their earlier history.", bundle: .module), timeout: Toast.brief))
    }

    @ViewBuilder var content: some View {
        if let focus = store.fileFocus {
            switch lines {
            case .loading:
                Spinner().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let error):
                PlacesLoadFailed(title: String(localized: "No blame for \(PathParts.split(focus.path).name)", bundle: .module), error: error) { attempt += 1 }
            case .loaded(let items):
                if items.isEmpty {
                    PlacesEmpty(icon: "person.text.rectangle", title: String(localized: "\(PathParts.split(focus.path).name) is empty", bundle: .module), message: String(localized: "There are no lines to blame at this commit.", bundle: .module), small: true)
                } else {
                    BlameLines(lines: items, path: focus.path, selected: $selected)
                }
            }
        } else {
            PlacesEmpty(icon: "person.text.rectangle", title: String(localized: "Blame", bundle: .module), message: String(localized: "Choose Blame from a file's menu in Changes or in a commit to see who last changed each line.", bundle: .module), small: true)
        }
    }
}

struct BlameLines: View {
    let lines: [BlameLine]
    let path: String
    @Binding var selected: OID?
    @Environment(WindowModel.self) private var window
    @Environment(Preferences.self) private var preferences
    @Environment(\.vraiNow) private var now
    @Environment(\.widthClass) private var widthClass

    var body: some View {
        let language = SyntaxHighlighter.language(for: path)
        let metrics = DiffMetrics(codeSize: preferences.codeSize)
        let dates = lines.map(\.authorDate.timeIntervalSince1970)
        let oldest = dates.min() ?? 0
        let newest = dates.max() ?? 0
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    let first = index == 0 || lines[index - 1].commit != line.commit
                    let heat = newest == oldest ? 1 : 0.15 + 0.85 * (line.authorDate.timeIntervalSince1970 - oldest) / (newest - oldest)
                    BlameRowView(line: line, first: first, heat: heat, selected: line.commit == selected, language: language, metrics: metrics, wrap: preferences.wrap, compact: widthClass == .compact, now: now)
                        .onTapGesture(count: 2) { PlacesActions.showInHistory(window, id: line.commit) }
                        .onTapGesture { selected = line.commit }
                        .contextMenu { BlameLineMenu(line: line, path: path, window: window, select: { selected = line.commit }) }
                        .accessibilityAction { selected = line.commit }
                }
            }
            .padding(.top, Vrai.Space.s4)
            .padding(.bottom, Vrai.Space.s16)
        }
        .background(Color.Vrai.bg)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Blame", bundle: .module))
    }
}

struct BlameRowView: View {
    let line: BlameLine
    let first: Bool
    let heat: Double
    let selected: Bool
    let language: String
    let metrics: DiffMetrics
    let wrap: Bool
    let compact: Bool
    let now: Date?
    @Environment(\.expert) private var expert
    @Environment(\.captureMode) private var capture
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(Color.Vrai.accent.opacity(heat))
                .frame(width: Vrai.Space.s4)
                .accessibilityHidden(true)
            HStack(spacing: Vrai.Space.s8) {
                if first {
                    Text(line.commit.short(expert: expert))
                        .font(Font.Vrai.codeSmall)
                        .foregroundStyle(Color.Vrai.accentText)
                        .fixedSize()
                    if !compact {
                        Text(line.authorName)
                            .font(Font.Vrai.callout)
                            .foregroundStyle(Color.Vrai.textSecondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(RelativeDate.text(line.authorDate, now: now))
                            .font(Font.Vrai.caption)
                            .monospacedDigit()
                            .foregroundStyle(Color.Vrai.textTertiary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, Vrai.Space.s8)
            .padding(.trailing, Vrai.Space.s12)
            .frame(width: compact ? Vrai.Size.colHash : Vrai.Size.colBlame, alignment: .leading)
            .frame(minHeight: metrics.lineHeight)
            .background(Color.Vrai.bgSubtle)
            LineNumber(number: line.number, font: metrics.numberFont)
                .frame(minHeight: metrics.lineHeight)
            Text(CodeRenderer.attributed(line.text, language: language))
                .font(metrics.codeFont)
                .foregroundStyle(Color.Vrai.text)
                .lineLimit(wrap ? nil : 1)
                .fixedSize(horizontal: !wrap, vertical: true)
                .padding(.trailing, Vrai.Space.s16)
                .frame(maxWidth: .infinity, minHeight: metrics.lineHeight, alignment: .leading)
                .clipped()
        }
        .background(selected || (hovering && !capture) ? Color.Vrai.accentSoft : Color.clear)
        .overlay(alignment: .top) {
            if first { Rectangle().fill(Color.Vrai.separator).frame(height: Metrics.hairline) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(line.summary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Line \(line.number), \(line.text). \(line.authorName), \(RelativeDate.text(line.authorDate, now: now)), \(line.summary)", bundle: .module))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct BlameLineMenu: View {
    let line: BlameLine
    let path: String
    let window: WindowModel
    let select: () -> Void

    var body: some View {
        let short = line.commit.short(expert: window.preferences.expert)
        MenuItem(title: String(localized: "Show \(short) in history", bundle: .module), icon: "clock.arrow.circlepath", enabled: true) {
            PlacesActions.showInHistory(window, id: line.commit)
        }
        MenuItem(title: String(localized: "Blame before this change", bundle: .module), icon: "arrow.uturn.backward", enabled: line.previous != nil) {
            guard let parent = line.previous else { return }
            select()
            window.openBlame(path: line.previousPath ?? path, revision: parent.rawValue)
        }
        MenuItem(title: String(localized: "File history", bundle: .module), icon: "clock", enabled: true) {
            window.openFileHistory(path: path)
        }
        Divider()
        AlternateMenuItem(
            primary: MenuItem(title: String(localized: "Copy hash", bundle: .module), icon: "doc.on.doc", enabled: true) { window.copy(short) },
            alternate: MenuItem(title: String(localized: "Copy full hash", bundle: .module), icon: "doc.on.doc", enabled: true) { window.copy(line.commit.rawValue, label: String(localized: "full hash", bundle: .module)) }
        )
    }
}
