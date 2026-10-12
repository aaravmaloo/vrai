import SwiftUI
import VraiCore
import VraiGit

struct FileEntry: Identifiable, Hashable {
    var path: String
    var oldPath: String?
    var status: FileStatus
    var additions: Int
    var deletions: Int
    var binary: Bool

    var id: String { path }

    init(_ file: ChangedFile) {
        path = file.path
        oldPath = file.oldPath
        status = file.status
        additions = file.additions
        deletions = file.deletions
        binary = file.isBinary
    }

    init(_ file: WorkingFile) {
        path = file.path
        oldPath = file.oldPath
        status = file.status
        additions = file.additions
        deletions = file.deletions
        binary = file.isBinary
    }
}

struct DiffPanel<FileMenu: View, Header: View>: View {
    let files: [FileEntry]
    var loading = false
    var title: String?
    @ViewBuilder let fileMenu: (FileEntry) -> FileMenu
    @ViewBuilder let filesHeader: () -> Header
    @Environment(RepositoryStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(\.widthClass) private var widthClass
    @FocusState private var filesFocused: Bool

    var body: some View {
        let stacked = widthClass.isNarrow
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            filesPane
                .frame(width: stacked ? nil : (widthClass == .medium ? Metrics.mediumFiles : Vrai.Size.filelist))
                .frame(maxHeight: stacked ? Metrics.narrowFiles : .infinity)
                .fixedSize(horizontal: false, vertical: stacked)
                .hairline(stacked ? .bottom : .trailing)
            diffPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    var totals: (Int, Int) {
        files.reduce((0, 0)) { ($0.0 + $1.additions, $0.1 + $1.deletions) }
    }

    var filesPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: Vrai.Space.s8) {
                Text(title ?? String(localized: "\(n(files.count, "file")) changed", bundle: .module))
                    .font(Font.Vrai.captionStrong)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                DiffStat(additions: totals.0, deletions: totals.1, bar: true)
                Spacer(minLength: 0)
                filesHeader()
            }
            .padding(.horizontal, Vrai.Space.s12)
            .frame(height: Metrics.paneBarHeight)
            if loading, files.isEmpty {
                Spinner().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if files.isEmpty {
                Text("No file changes.", bundle: .module)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(.secondary)
                    .padding(Vrai.Space.s12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(files) { file in
                            FileRowView(path: file.path, oldPath: file.oldPath, status: file.status, additions: file.additions, deletions: file.deletions, binary: file.binary, selected: file.path == store.selectedPath, focused: filesFocused)
                                .onTapGesture {
                                    filesFocused = true
                                    store.selectFile(file.path)
                                }
                                .contextMenu { fileMenu(file) }
                                .accessibilityAction { store.selectFile(file.path) }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(Text("Files", bundle: .module))
                    .padding(.horizontal, Vrai.Space.s4)
                    .padding(.bottom, Vrai.Space.s8)
                }
                .focusable()
                .focusEffectDisabled()
                .focused($filesFocused)
                .onKeyPress(keys: [.downArrow, .upArrow], phases: [.down, .repeat]) { press in
                    moveFile(press.key == .downArrow ? 1 : -1)
                }
                .accessibilityLabel(Text("Files", bundle: .module))
            }
        }
    }

    func moveFile(_ delta: Int) -> KeyPress.Result {
        guard !files.isEmpty else { return .ignored }
        let current = files.firstIndex { $0.path == store.selectedPath }
        let next = current.map { max(0, min(files.count - 1, $0 + delta)) } ?? (delta > 0 ? 0 : files.count - 1)
        if next != current { store.selectFile(files[next].path) }
        return .handled
    }

    @ViewBuilder var diffPane: some View {
        if let path = store.selectedPath, let file = files.first(where: { $0.path == path }) {
            VStack(spacing: 0) {
                HStack(spacing: Vrai.Space.s8) {
                    PathBar(path: file.path)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()
                    if !widthClass.isNarrow {
                        SegmentedControl(selection: Binding(get: { preferences.diffMode }, set: { preferences.diffMode = $0 }), items: [
                            SegmentItem(value: Preferences.DiffMode.unified, icon: "text.alignleft", label: String(localized: "Unified", bundle: .module)),
                            SegmentItem(value: Preferences.DiffMode.split, icon: "rectangle.split.2x1", label: String(localized: "Side by side", bundle: .module))
                        ])
                    }
                    IconMenu(icon: "ellipsis.circle", label: String(localized: "File actions", bundle: .module)) {
                        fileMenu(file)
                    }
                }
                .padding(.leading, Vrai.Space.s12)
                .padding(.trailing, Vrai.Space.s8)
                .frame(height: Metrics.paneBarHeight)
                .hairline(.bottom)
                diffBody(file)
            }
        } else if loading {
            Spinner().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyStateView(icon: "doc.text", title: String(localized: "No file selected", bundle: .module), small: true)
        }
    }

    @ViewBuilder func diffBody(_ file: FileEntry) -> some View {
        switch store.patchState {
        case .loading, .idle:
            Spinner().frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.Vrai.bg)
        case .failed(let error):
            EmptyStateView(icon: "exclamationmark.triangle", title: String(localized: "This diff didn't load", bundle: .module), message: ErrorCopy(error).message, small: true)
                .background(Color.Vrai.bg)
        case .loaded:
            if let patch = store.patch, !patch.hunks.isEmpty {
                DiffView(diff: patch, mode: widthClass.isNarrow ? .unified : preferences.diffMode, wrap: preferences.wrap, whitespace: preferences.whitespace, codeSize: preferences.codeSize) {
                    store.showMoreContext()
                }
                .perfEnd("diff", when: patch.path == file.path, detail: "\(patch.hunks.reduce(0) { $0 + $1.lines.count })")
            } else {
                Text(file.binary || store.patch?.isBinary == true ? String(localized: "Binary file, not shown.", bundle: .module) : String(localized: "No text changes.", bundle: .module))
                    .font(Font.Vrai.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.Vrai.bg)
            }
        }
    }
}
