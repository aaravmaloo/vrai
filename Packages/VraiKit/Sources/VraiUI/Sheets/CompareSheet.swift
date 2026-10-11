import SwiftUI
import VraiCore
import VraiGit

struct CompareSheet: View {
    let initialFirst: String?
    let initialSecond: String?
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @State private var first = ""
    @State private var second = ""
    @State private var result: BranchComparison?
    @State private var loading = false
    @State private var failure: String?

    var options: [SyncForm.Option<String>] {
        guard let snapshot = store.snapshot else { return [] }
        var out = snapshot.branches.map { SyncForm.Option(value: $0.name, label: $0.name, icon: "arrow.triangle.branch") }
        out += snapshot.remoteBranches.map { SyncForm.Option(value: $0.fullName, label: $0.fullName, icon: "cloud") }
        out += snapshot.tags.map { SyncForm.Option(value: $0.name, label: $0.name, icon: "tag") }
        return out
    }

    var defaultSecond: String {
        let names = store.snapshot?.branches.map(\.name) ?? []
        let current = store.snapshot?.currentBranch?.name
        if let main = names.first(where: { BranchColors.mainLines.contains($0) && $0 != current }) { return main }
        if let upstream = store.snapshot?.currentBranch?.upstream { return upstream }
        return names.first { $0 != current } ?? "HEAD"
    }

    var body: some View {
        LongTailSheet(
            title: String(localized: "Compare branches", bundle: .module),
            icon: "arrow.left.arrow.right",
            width: Vrai.Size.sheet + Vrai.Space.s64
        ) {
            HStack(alignment: .top, spacing: Vrai.Space.s12) {
                SyncForm.Field(label: String(localized: "Branch", bundle: .module)) {
                    SyncForm.Select(selection: $first, options: options, label: String(localized: "First", bundle: .module))
                }
                SyncForm.Field(label: String(localized: "Compared with", bundle: .module)) {
                    SyncForm.Select(selection: $second, options: options, label: String(localized: "Second", bundle: .module))
                }
            }
            if let failure {
                SyncForm.Callout(tone: .danger, title: String(localized: "git couldn't compare them", bundle: .module), message: failure)
            } else if let result {
                section(count: result.baseCount, commits: result.onlyInBase, on: result.base, missing: result.head)
                section(count: result.headCount, commits: result.onlyInHead, on: result.head, missing: result.base)
                if let base = result.mergeBase {
                    Text("They split at \(base.short)\(result.mergeBaseName.map { " (\($0))" } ?? ""). \(n(result.files.count, "file")) differ since then.", bundle: .module)
                        .font(Font.Vrai.caption)
                        .foregroundStyle(Color.Vrai.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if window.preferences.expert {
                    SyncForm.CommandPreview(command: result.command)
                }
            } else if loading {
                Spinner()
            }
        } actions: {
            Button {
                window.sheets.dismiss()
            } label: {
                Text("Close", bundle: .module)
            }
            .buttonStyle(VraiButtonStyle(variant: .secondary))
            .keyboardShortcut(.cancelAction)
            Button {
                window.sheets.dismiss()
                window.show(.history)
                store.showRef(first)
            } label: {
                Text("Show in history", bundle: .module)
            }
            .buttonStyle(VraiButtonStyle(variant: .primary))
            .keyboardShortcut(.defaultAction)
            .disabled(first.isEmpty)
            .accessibilityIdentifier("compare-show")
        }
        .onAppear {
            if first.isEmpty { first = initialFirst ?? store.snapshot?.currentBranch?.name ?? "HEAD" }
            if second.isEmpty { second = initialSecond ?? defaultSecond }
        }
        .task(id: first + "\u{0}" + second) {
            guard !first.isEmpty, !second.isEmpty else { return }
            loading = true
            failure = nil
            do {
                result = try await store.compare(base: first, head: second)
            } catch let error as GitError {
                result = nil
                failure = error.result?.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines) ?? ErrorCopy(error).message
            } catch {
                result = nil
                failure = error.localizedDescription
            }
            loading = false
        }
    }

    @ViewBuilder func section(count: Int, commits: [ComparedCommit], on: String, missing: String) -> some View {
        Text("\(n(count, "commit")) on \(on) that \(missing) doesn't have", bundle: .module)
            .font(Font.Vrai.callout)
            .foregroundStyle(Color.Vrai.textSecondary)
            .lineLimit(2)
            .truncationMode(.middle)
        if !commits.isEmpty {
            LongTailBox(maxHeight: LongTailMetrics.listMax) {
                ForEach(commits.prefix(50)) { commit in
                    HStack(spacing: Vrai.Space.s8) {
                        Text(commit.id.short(expert: window.preferences.expert))
                            .font(Font.Vrai.codeSmall)
                            .foregroundStyle(Color.Vrai.textTertiary)
                        Text(commit.subject)
                            .font(Font.Vrai.callout)
                            .foregroundStyle(commit.equivalent ? Color.Vrai.textSecondary : Color.Vrai.text)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if commit.equivalent {
                            Badge(text: String(localized: "Also on \(missing)", bundle: .module), outline: true)
                                .help(String(localized: "The same change is on \(missing) as a different commit, usually a cherry-pick.", bundle: .module))
                        }
                    }
                    .padding(.horizontal, Vrai.Space.s4)
                    .frame(minHeight: Vrai.Space.s20)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        window.sheets.dismiss()
                        window.show(.history)
                        store.selectCommit(commit.id, scroll: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                if commits.count < count || commits.count > 50 {
                    Text("and \(n(count - min(commits.count, 50), "more commit"))", bundle: .module)
                        .font(Font.Vrai.caption)
                        .foregroundStyle(Color.Vrai.textTertiary)
                        .padding(.horizontal, Vrai.Space.s4)
                }
            }
        }
    }
}
