import SwiftUI
import VraiCore
import VraiGit

struct InspectorView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(\.expert) private var expert

    var body: some View {
        Group {
            if let commit = window.selectedCommit {
                content(commit)
            } else {
                EmptyStateView(icon: "info.circle", title: String(localized: "No commit selected", bundle: .module), small: true)
                    .help(String(localized: "Select a commit to see its author, dates, parents, branches and signature.", bundle: .module))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Inspector", bundle: .module))
    }

    func content(_ commit: Commit) -> some View {
        let info = store.inspectorInfo?.id == commit.id ? store.inspectorInfo : nil
        let detail = store.detail?.commit.id == commit.id ? store.detail : nil
        let tags = store.snapshot?.tags.filter { $0.target == commit.id } ?? []
        let branches = info?.branches ?? []
        let rewrite = RewriteMenuState(window: window, id: commit.id)
        return Form {
            Section {
                LabeledContent(String(localized: "Hash", bundle: .module)) {
                    HashButton(id: commit.id, length: 10, full: expert)
                }
                LabeledContent(String(localized: "Describe", bundle: .module)) {
                    Text(info?.describe ?? commit.id.short)
                        .font(Font.Vrai.codeSmall)
                        .textSelection(.enabled)
                }
                LabeledContent(commit.parents.count > 1 ? String(localized: "Parents", bundle: .module) : String(localized: "Parent", bundle: .module)) {
                    if commit.parents.isEmpty {
                        Text("Root commit", bundle: .module)
                    } else {
                        HStack(spacing: Vrai.Space.s8) {
                            ForEach(commit.parents, id: \.self) { parent in
                                Button(parent.short) {
                                    store.selectCommit(parent, scroll: true)
                                }
                                .buttonStyle(.link)
                                .font(Font.Vrai.codeSmall)
                            }
                        }
                    }
                }
            }
            Section(String(localized: "People", bundle: .module)) {
                LabeledContent(String(localized: "Author", bundle: .module)) {
                    Text(commit.authorName)
                }
                LabeledContent(String(localized: "Email", bundle: .module)) {
                    Text(commit.authorEmail)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                LabeledContent(String(localized: "Authored", bundle: .module)) {
                    Text(Self.fullDate(commit.authorDate))
                        .help(RelativeDate.full(commit.authorDate))
                }
                LabeledContent(String(localized: "Committer", bundle: .module)) {
                    Text(commit.committerName.isEmpty ? commit.authorName : commit.committerName)
                }
                if expert, commit.committerDate != commit.authorDate, !commit.committerName.isEmpty {
                    LabeledContent(String(localized: "Committed", bundle: .module)) {
                        Text(Self.fullDate(commit.committerDate))
                    }
                }
                LabeledContent(String(localized: "Signature", bundle: .module)) {
                    if let detail {
                        SignatureCheck(target: .commit(commit.id), state: detail.commit.signature, signer: detail.signer ?? commit.authorName)
                    } else {
                        Spinner()
                    }
                }
            }
            Section(String(localized: "On branches", bundle: .module)) {
                if info == nil {
                    Spinner()
                } else if branches.isEmpty {
                    Text("None", bundle: .module)
                        .foregroundStyle(.secondary)
                        .help(String(localized: "Only reachable from remote branches or tags.", bundle: .module))
                } else {
                    FlowLayout(spacing: Vrai.Space.s4, lineSpacing: Vrai.Space.s4) {
                        ForEach(branches, id: \.self) { name in
                            Button {
                                store.showRef(name)
                            } label: {
                                RefPill(model: RefPillModel(kind: .branch, name: name, lane: store.snapshot?.branches.first { $0.name == name }?.colorIndex ?? 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !tags.isEmpty {
                    FlowLayout(spacing: Vrai.Space.s4, lineSpacing: Vrai.Space.s4) {
                        ForEach(tags) { tag in RefPill(model: RefPillModel(kind: .tag, name: tag.name)) }
                    }
                }
            }
            if expert {
                Section(String(localized: "Note", bundle: .module)) {
                    CommitNoteEditor(id: commit.id)
                }
            }
            Section(String(localized: "Actions", bundle: .module)) {
                FlowLayout(spacing: Vrai.Space.s6, lineSpacing: Vrai.Space.s6) {
                    VraiButton(title: String(localized: "Branch", bundle: .module), icon: "arrow.triangle.branch", size: .small) {
                        window.sync.newBranch(from: commit.id.rawValue)
                    }
                    VraiButton(title: String(localized: "Tag", bundle: .module), icon: "tag", size: .small) {
                        window.sync.newTag(target: commit.id.rawValue)
                    }
                    .accessibilityIdentifier("inspector-tag")
                    VraiButton(title: String(localized: "Cherry-pick", bundle: .module), icon: "arrow.turn.down.right", size: .small) {
                        RewriteActions.cherryPick(window, ids: [commit.id])
                    }
                    .disabled(rewrite.inHead)
                    VraiButton(title: String(localized: "Revert", bundle: .module), icon: "arrow.uturn.backward", size: .small) {
                        RewriteActions.revert(window, id: commit.id)
                    }
                    .disabled(!rewrite.inHead || rewrite.isMerge)
                    VraiButton(title: String(localized: "Reset to here", bundle: .module), icon: "arrow.counterclockwise", size: .small) {
                        RewriteActions.openReset(window, target: commit.id)
                    }
                    .disabled(rewrite.isTip)
                    VraiButton(title: String(localized: "Check out", bundle: .module), icon: "mappin.and.ellipse", size: .small) {
                        window.sync.confirmDetach(commit.id, subject: commit.subject)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    static func fullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEE, MMM d, y, h:mm a"
        return formatter.string(from: date)
    }
}

struct KeyValueGrid<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Vrai.Space.s12, verticalSpacing: Vrai.Space.s6) {
            content()
        }
    }
}

struct KeyValueRow<Value: View>: View {
    let key: String
    @ViewBuilder let value: () -> Value
    @Environment(\.widthClass) private var widthClass

    var body: some View {
        GridRow {
            Text(key)
                .foregroundStyle(Color.Vrai.textTertiary)
                .frame(width: widthClass.isNarrow ? Metrics.kvKeyNarrow : Metrics.kvKey, alignment: .leading)
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(Font.Vrai.callout)
    }
}
