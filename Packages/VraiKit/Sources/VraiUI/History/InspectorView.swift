import SwiftUI
import VraiCore
import VraiGit

struct InspectorView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(Preferences.self) private var preferences
    @Environment(\.expert) private var expert

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Commit", bundle: .module)
                    .font(Font.Vrai.captionStrong)
                    .foregroundStyle(Color.Vrai.textSecondary)
                Spacer()
                IconButton(icon: "xmark", label: String(localized: "Hide inspector", bundle: .module), small: true) {
                    preferences.inspector = false
                }
            }
            .padding(.leading, Vrai.Space.s16)
            .padding(.trailing, Vrai.Space.s8)
            .frame(height: Metrics.paneBarHeight)
            .hairline(.bottom)
            if let commit = window.selectedCommit {
                ScrollView {
                    content(commit)
                        .padding(.top, Vrai.Space.s12)
                        .padding(.horizontal, Vrai.Space.s16)
                        .padding(.bottom, Vrai.Space.s20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Spacer()
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color.Vrai.bgSubtle, ignoresSafeAreaEdges: [])
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Inspector", bundle: .module))
    }

    @ViewBuilder func content(_ commit: Commit) -> some View {
        let info = store.inspectorInfo?.id == commit.id ? store.inspectorInfo : nil
        let detail = store.detail?.commit.id == commit.id ? store.detail : nil
        let tags = store.snapshot?.tags.filter { $0.target == commit.id } ?? []
        let branches = info?.branches ?? []
        VStack(alignment: .leading, spacing: Vrai.Space.s16) {
            KeyValueGrid {
                KeyValueRow(key: String(localized: "Hash", bundle: .module)) {
                    HashButton(id: commit.id, length: 10, full: expert)
                }
                KeyValueRow(key: String(localized: "Describe", bundle: .module)) {
                    Text(info?.describe ?? commit.id.short)
                        .font(Font.Vrai.codeSmall)
                        .textSelection(.enabled)
                }
                KeyValueRow(key: commit.parents.count > 1 ? String(localized: "Parents", bundle: .module) : String(localized: "Parent", bundle: .module)) {
                    if commit.parents.isEmpty {
                        Text("Root commit", bundle: .module).foregroundStyle(Color.Vrai.textTertiary)
                    } else {
                        HStack(spacing: Vrai.Space.s4) {
                            ForEach(commit.parents, id: \.self) { parent in
                                Button {
                                    store.selectCommit(parent, scroll: true)
                                } label: {
                                    Text(parent.short)
                                        .font(Font.Vrai.codeSmall)
                                        .padding(.horizontal, Vrai.Space.s4)
                                        .frame(height: Vrai.Space.s20)
                                }
                                .buttonStyle(HashButtonStyle())
                            }
                        }
                    }
                }
            }
            InspectorSection(title: String(localized: "People", bundle: .module)) {
                KeyValueGrid {
                    KeyValueRow(key: String(localized: "Author", bundle: .module)) {
                        HStack(spacing: Vrai.Space.s4) {
                            Avatar(name: commit.authorName, size: Vrai.Space.s16)
                            Text(commit.authorName)
                        }
                    }
                    KeyValueRow(key: "") {
                        Text(commit.authorEmail).foregroundStyle(Color.Vrai.textTertiary).textSelection(.enabled)
                    }
                    KeyValueRow(key: String(localized: "Authored", bundle: .module)) {
                        Text(Self.fullDate(commit.authorDate)).help(RelativeDate.full(commit.authorDate))
                    }
                    KeyValueRow(key: String(localized: "Committer", bundle: .module)) {
                        Text(commit.committerName.isEmpty ? commit.authorName : commit.committerName)
                    }
                    if expert, commit.committerDate != commit.authorDate, !commit.committerName.isEmpty {
                        KeyValueRow(key: String(localized: "Committed", bundle: .module)) {
                            Text(Self.fullDate(commit.committerDate))
                        }
                    }
                    KeyValueRow(key: String(localized: "Signature", bundle: .module)) {
                        if let detail {
                            SignatureBadge(state: detail.commit.signature, signer: detail.signer ?? commit.authorName)
                        } else {
                            Spinner()
                        }
                    }
                }
            }
            InspectorSection(title: String(localized: "On branches", bundle: .module)) {
                if info == nil {
                    Spinner()
                } else if branches.isEmpty {
                    Text("Only reachable from remote branches or tags.", bundle: .module)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textTertiary)
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
                InspectorSection(title: String(localized: "Note", bundle: .module)) {
                    CommitNoteEditor(id: commit.id)
                }
            }
            InspectorSection(title: String(localized: "Actions", bundle: .module)) {
                FlowLayout(spacing: Vrai.Space.s6, lineSpacing: Vrai.Space.s6) {
                    PendingButton(title: String(localized: "Branch", bundle: .module), icon: "arrow.triangle.branch")
                    PendingButton(title: String(localized: "Tag", bundle: .module), icon: "tag")
                    PendingButton(title: String(localized: "Cherry-pick", bundle: .module), icon: "arrow.turn.down.right")
                    PendingButton(title: String(localized: "Revert", bundle: .module), icon: "arrow.uturn.backward")
                    PendingButton(title: String(localized: "Reset to here", bundle: .module), icon: "arrow.counterclockwise")
                    PendingButton(title: String(localized: "Check out", bundle: .module), icon: "mappin.and.ellipse")
                }
            }
        }
        .font(Font.Vrai.callout)
        .foregroundStyle(Color.Vrai.text)
    }

    static func fullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEE, MMM d, y, h:mm a"
        return formatter.string(from: date)
    }
}

struct PendingButton: View {
    let title: String
    let icon: String

    var body: some View {
        VraiButton(title: title, icon: icon, size: .small) {}
            .disabled(true)
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Vrai.Space.s8) {
            Text(title)
                .overline()
                .foregroundStyle(Color.Vrai.textTertiary)
            content()
        }
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
