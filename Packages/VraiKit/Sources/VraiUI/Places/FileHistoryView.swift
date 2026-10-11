import SwiftUI
import VraiCore
import VraiGit

struct FileHistoryView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(\.vraiNow) private var now
    @State private var entries: PlacesLoad<[FileHistoryEntry]> = .loading
    @State private var selected: OID?
    @State private var showDetail = false
    @State private var attempt = 0

    struct LoadKey: Hashable {
        var path: String?
        var head: OID?
        var attempt: Int
    }

    var body: some View {
        Group {
            if let focus = store.fileFocus {
                PlacesPane(showDetail: showDetail, backLabel: PathParts.split(focus.path).name, back: { showDetail = false }) {
                    list(focus)
                } detail: {
                    detail(focus)
                }
            } else {
                PlacesEmpty(icon: "clock", title: String(localized: "File history", bundle: .module), message: String(localized: "Choose File history from a file's menu in Changes or in a commit to see every commit that changed it.", bundle: .module), small: true)
            }
        }
        .task(id: LoadKey(path: store.fileFocus?.path, head: store.snapshot?.headOID, attempt: attempt)) { await load() }
        .accessibilityIdentifier("file-history-view")
    }

    func load() async {
        guard let focus = store.fileFocus else { return }
        do {
            let loaded = try await store.fileHistory(path: focus.path)
            entries = .loaded(loaded)
            if let revision = focus.revision, let match = loaded.first(where: { $0.commit.id.rawValue.hasPrefix(revision.lowercased()) }) {
                selected = match.commit.id
            } else if !loaded.contains(where: { $0.commit.id == selected }) {
                selected = loaded.first?.commit.id
            }
        } catch let error as GitError {
            entries = .failed(error)
        } catch {
            entries = .failed(GitError(.unknown(exit: -1, stderr: String(describing: error))))
        }
    }

    func list(_ focus: FileFocus) -> some View {
        VStack(spacing: 0) {
            PlacesListHeader(
                title: PathParts.split(focus.path).name,
                caption: entries.value.map { String(localized: "\(n($0.count, "commit")) changed it", bundle: .module) },
                leading: {
                    IconButton(icon: "chevron.left", label: String(localized: "Back to history", bundle: .module)) {
                        window.show(.history)
                    }
                    .accessibilityIdentifier("file-history-back")
                },
                trailing: {
                    IconMenu(icon: "ellipsis.circle", label: String(localized: "File actions", bundle: .module)) {
                        MenuItem(title: String(localized: "Blame", bundle: .module), icon: "person.text.rectangle", enabled: true) {
                            window.openBlame(path: focus.path)
                        }
                        MenuItem(title: String(localized: "Copy path", bundle: .module), icon: "doc.on.doc", enabled: true) {
                            window.copy(focus.path, label: String(localized: "path", bundle: .module))
                        }
                    }
                }
            )
            switch entries {
            case .loading:
                Spinner().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let error):
                PlacesLoadFailed(title: String(localized: "The history didn't load", bundle: .module), error: error) { attempt += 1 }
            case .loaded(let items):
                if items.isEmpty {
                    Text("No commits touched this file.", bundle: .module)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textTertiary)
                        .padding(Vrai.Space.s12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    PlacesList(label: String(localized: "Commits", bundle: .module)) {
                        ForEach(items) { entry in
                            PlacesRow(
                                title: entry.commit.subject,
                                subtitle: entry.commit.authorName + ", " + RelativeDate.text(entry.commit.authorDate, now: now),
                                selected: entry.commit.id == (selected ?? items.first?.commit.id),
                                identifier: "file-history-" + entry.commit.id.short,
                                action: {
                                    selected = entry.commit.id
                                    showDetail = true
                                },
                                leading: { Avatar(name: entry.commit.authorName, size: Vrai.Space.s20) },
                                trailing: { DiffStat(additions: entry.file.additions, deletions: entry.file.deletions) }
                            )
                            .simultaneousGesture(TapGesture(count: 2).onEnded { PlacesActions.showInHistory(window, id: entry.commit.id) })
                            .contextMenu { CommitFileMenu(id: entry.commit.id, path: entry.file.path, window: window) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder func detail(_ focus: FileFocus) -> some View {
        if let items = entries.value, let entry = items.first(where: { $0.commit.id == selected }) ?? items.first {
            FileHistoryDetail(entry: entry)
                .id(entry.commit.id)
        } else if case .loading = entries {
            Spinner().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PlacesEmpty(icon: "clock", title: String(localized: "No history for this file", bundle: .module), small: true)
        }
    }
}

struct FileHistoryDetail: View {
    let entry: FileHistoryEntry
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(Preferences.self) private var preferences
    @Environment(\.vraiNow) private var now
    @Environment(\.expert) private var expert
    @Environment(\.widthClass) private var widthClass
    @State private var patch: FileDiff?
    @State private var failed: GitError?
    @State private var loading = true
    @State private var context = RepositoryStore.defaultContext

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Vrai.Space.s6) {
                HStack(alignment: .top, spacing: Vrai.Space.s8) {
                    Text(entry.commit.subject)
                        .font(Font.Vrai.title2)
                        .foregroundStyle(Color.Vrai.text)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    VraiButton(title: String(localized: "Show commit", bundle: .module), icon: "clock.arrow.circlepath", size: .small) {
                        PlacesActions.showInHistory(window, id: entry.commit.id)
                    }
                    .accessibilityIdentifier("file-history-show")
                }
                HStack(spacing: Vrai.Space.s12) {
                    HStack(spacing: Vrai.Space.s6) {
                        Avatar(name: entry.commit.authorName, size: Vrai.Space.s16 + Vrai.Space.s2)
                        Text(entry.commit.authorName).lineLimit(1)
                    }
                    HashButton(id: entry.commit.id, length: expert ? 10 : 7)
                    Text(RelativeDate.text(entry.commit.authorDate, now: now))
                        .foregroundStyle(Color.Vrai.textTertiary)
                        .lineLimit(1)
                        .help(RelativeDate.full(entry.commit.authorDate))
                }
                .font(Font.Vrai.callout)
                .foregroundStyle(Color.Vrai.textSecondary)
            }
            .padding(.top, Vrai.Space.s12)
            .padding(.horizontal, Vrai.Space.s16)
            .padding(.bottom, Vrai.Space.s10)
            .background(Color.Vrai.bgSubtle)
            .hairline(.bottom)
            HStack(spacing: Vrai.Space.s8) {
                FileStatusTile(status: entry.file.status)
                PathBar(path: entry.file.path)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                if !widthClass.isNarrow {
                    DiffStat(additions: entry.file.additions, deletions: entry.file.deletions)
                    SegmentedControl(selection: Binding(get: { preferences.diffMode }, set: { preferences.diffMode = $0 }), items: [
                        SegmentItem(value: Preferences.DiffMode.unified, icon: "text.alignleft", label: String(localized: "Unified", bundle: .module)),
                        SegmentItem(value: Preferences.DiffMode.split, icon: "rectangle.split.2x1", label: String(localized: "Side by side", bundle: .module))
                    ])
                }
                IconMenu(icon: "ellipsis.circle", label: String(localized: "File actions", bundle: .module)) {
                    CommitFileMenu(id: entry.commit.id, path: entry.file.path, window: window)
                }
            }
            .padding(.leading, Vrai.Space.s12)
            .padding(.trailing, Vrai.Space.s8)
            .frame(height: Metrics.paneBarHeight)
            .hairline(.bottom)
            diffBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: context) { await load() }
    }

    @ViewBuilder var diffBody: some View {
        if let patch, !patch.hunks.isEmpty {
            DiffView(diff: patch, mode: widthClass.isNarrow ? .unified : preferences.diffMode, wrap: preferences.wrap, whitespace: preferences.whitespace, codeSize: preferences.codeSize) {
                context += RepositoryStore.contextStep
            }
        } else if let failed {
            PlacesEmpty(icon: "exclamationmark.triangle", title: String(localized: "This diff didn't load", bundle: .module), message: PlacesCopy.message(for: failed), small: true)
        } else if loading {
            Spinner().frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.Vrai.bg)
        } else {
            Text(entry.file.isBinary || patch?.isBinary == true ? String(localized: "Binary file, not shown.", bundle: .module) : (entry.file.status == .renamed ? String(localized: "Renamed without changes.", bundle: .module) : String(localized: "No text changes.", bundle: .module)))
                .font(Font.Vrai.callout)
                .foregroundStyle(Color.Vrai.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.Vrai.bg)
        }
    }

    func load() async {
        do {
            let loaded = try await store.diff(for: entry.file.path, in: entry.commit.id, oldPath: entry.file.oldPath, context: context)
            patch = loaded
            failed = nil
        } catch let error as GitError {
            failed = error
        } catch {
            failed = GitError(.unknown(exit: -1, stderr: String(describing: error)))
        }
        loading = false
    }
}
