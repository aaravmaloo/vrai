import SwiftUI
import VraiCore
import VraiGit

struct DetailPane: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(\.widthClass) private var widthClass

    var body: some View {
        VStack(spacing: 0) {
            if widthClass == .compact {
                HStack {
                    VraiButton(title: String(localized: "Commits", bundle: .module), icon: "chevron.left", variant: .plain, size: .small) {
                        window.pane = .list
                    }
                    .accessibilityIdentifier("history-back")
                    Spacer()
                }
                .padding(.leading, Vrai.Space.s12)
                .padding(.trailing, Vrai.Space.s8)
                .frame(height: Metrics.paneBarHeight)
                Divider()
            }
            switch store.selection {
            case .wip:
                WipDetailView()
            case .commit(let id):
                CommitDetailView(id: id)
            case nil:
                EmptyStateView(icon: "clock.arrow.circlepath", title: String(localized: "Select a commit", bundle: .module), small: true)
                    .help(String(localized: "Its message, files and diff appear here.", bundle: .module))
            }
        }
        .background(Color.Vrai.bg)
    }
}

struct CommitDetailView: View {
    let id: OID
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window

    var body: some View {
        let commit = store.detail?.commit.id == id ? store.detail?.commit : window.selectedCommit
        if let commit {
            VStack(spacing: 0) {
                CommitHeaderView(commit: commit, signer: store.detail?.signer)
                Divider()
                if case .failed(let error) = store.detailState {
                    EmptyStateView(icon: "exclamationmark.triangle", title: String(localized: "This commit didn't load", bundle: .module), message: ErrorCopy(error).message, small: true)
                } else {
                    DiffPanel(files: (store.detail?.commit.id == id ? store.detail?.files ?? [] : []).map(FileEntry.init), loading: store.detailState == .loading) { file in
                        CommitFileMenu(id: id, path: file.path, window: window)
                    } filesHeader: {
                        if commit.parents.count > 1 { ParentPicker(commit: commit) }
                    }
                    .perfEnd("select-commit", when: store.detail?.commit.id == id && store.detailState == .loaded, detail: "\(store.detail?.files.count ?? 0)")
                }
            }
        } else if case .failed(let error) = store.detailState {
            EmptyStateView(icon: "exclamationmark.triangle", title: String(localized: "This commit didn't load", bundle: .module), message: ErrorCopy(error).message, small: true)
        } else {
            Spinner().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ParentPicker: View {
    let commit: Commit
    @Environment(RepositoryStore.self) private var store

    var body: some View {
        Menu {
            Picker(selection: Binding(get: { store.diffParent }, set: { store.selectParent($0) })) {
                ForEach(Array(commit.parents.enumerated()), id: \.offset) { index, parent in
                    Text("Against \(parent.short)", bundle: .module).tag(index)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            Text("Parent \(store.diffParent + 1)", bundle: .module)
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .fixedSize()
        .help(String(localized: "Show the diff against another parent", bundle: .module))
    }
}

struct CommitHeaderView: View {
    let commit: Commit
    let signer: String?
    @Environment(RepositoryStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(WindowModel.self) private var window
    @Environment(\.expert) private var expert
    @Environment(\.vraiNow) private var now

    var body: some View {
        let refs = store.snapshot.map { RefPills.byCommit($0, only: commit.id)[commit.id] ?? [] } ?? []
        let signature = store.detail?.commit.id == commit.id ? store.detail?.commit.signature ?? .unchecked : store.signature(of: commit)
        VStack(alignment: .leading, spacing: Vrai.Space.s6) {
            HStack(alignment: .top, spacing: Vrai.Space.s8) {
                Text(commit.subject)
                    .font(Font.Vrai.title2)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                IconMenu(icon: "ellipsis.circle", label: String(localized: "Commit actions", bundle: .module)) {
                    CommitMenu(id: commit.id, window: window)
                }
            }
            if let body = store.detail?.commit.id == commit.id ? store.detail?.commit.body : nil {
                ScrollView {
                    Text(body)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: Metrics.bodyMaxHeight)
                .fixedSize(horizontal: false, vertical: true)
            }
            FlowLayout(spacing: Vrai.Space.s12, lineSpacing: Vrai.Space.s6) {
                HStack(spacing: Vrai.Space.s6) {
                    Avatar(name: commit.authorName, size: Vrai.Space.s16 + Vrai.Space.s2)
                    Text(commit.authorName).lineLimit(1)
                }
                .help(commit.authorEmail)
                Text(RelativeDate.text(commit.authorDate, now: now))
                    .help(RelativeDate.full(commit.authorDate))
                HashButton(id: commit.id, length: expert ? 10 : 7)
                if commit.parents.count > 1 {
                    HStack(spacing: Vrai.Space.s6) {
                        Text("Merge of", bundle: .module)
                        ForEach(commit.parents, id: \.self) { parent in
                            Button(parent.short) {
                                store.selectCommit(parent, scroll: true)
                            }
                            .buttonStyle(.link)
                            .font(Font.Vrai.codeSmall)
                            .foregroundStyle(Color(nsColor: .linkColor))
                        }
                    }
                }
                if expert || signature == .bad {
                    SignatureCheck(target: .commit(commit.id), state: signature, signer: signer ?? commit.authorName)
                }
                if preferences.checks {
                    ChecksPill(id: commit.id, branch: ChecksActions.label(for: commit.id, in: store.snapshot))
                }
                if !refs.isEmpty {
                    PillRow {
                        ForEach(refs) { RefPill(model: $0) }
                    }
                }
            }
            .font(Font.Vrai.callout)
            .foregroundStyle(.secondary)
        }
        .padding(.top, Vrai.Space.s12)
        .padding(.horizontal, Vrai.Space.s16)
        .padding(.bottom, Vrai.Space.s10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WipDetailView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window

    var body: some View {
        let working = store.snapshot?.working ?? []
        let staged = working.filter { $0.staged != .none }.count
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Vrai.Space.s6) {
                HStack(alignment: .top, spacing: Vrai.Space.s8) {
                    Text("Uncommitted changes", bundle: .module)
                        .font(Font.Vrai.title2)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VraiButton(title: String(localized: "Open Changes", bundle: .module), icon: "square.and.pencil", variant: .primary, size: .small, shortcut: "\u{2318}2") {
                        window.show(.changes)
                    }
                }
                Text("\(n(working.count, "changed file")), \(staged) staged, on \(window.headName)", bundle: .module)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, Vrai.Space.s12)
            .padding(.horizontal, Vrai.Space.s16)
            .padding(.bottom, Vrai.Space.s10)
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            DiffPanel(files: store.wipFiles.map(FileEntry.init)) { file in
                if let working = working.first(where: { $0.path == file.path }) {
                    WorkingFileMenu(file: working, window: window)
                }
            } filesHeader: {
                EmptyView()
            }
        }
    }
}
