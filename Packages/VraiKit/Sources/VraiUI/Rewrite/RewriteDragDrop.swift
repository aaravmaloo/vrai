import SwiftUI
import VraiCore
import VraiGit

enum RewriteDrag {
    static let branchPrefix = "vrai-branch:"
    static let commitPrefix = "vrai-commit:"

    static func branch(_ name: String) -> String { branchPrefix + name }
    static func commit(_ id: OID) -> String { commitPrefix + id.rawValue }
}

struct RewriteBranchDrop: ViewModifier {
    let branch: Branch
    let current: Bool
    let window: WindowModel
    @State private var targeted = false

    func body(content: Content) -> some View {
        if current {
            content
                .overlay {
                    if targeted {
                        RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous)
                            .strokeBorder(Color.Vrai.accent, lineWidth: Vrai.Size.line)
                            .allowsHitTesting(false)
                    }
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let item = items.first else { return false }
                    return RewriteDrop.handle(item, window: window)
                } isTargeted: { targeted = $0 }
        } else {
            content
                .draggable(RewriteDrag.branch(branch.name)) {
                    RefPill(model: RefPillModel(kind: .branch, name: branch.name, lane: branch.colorIndex))
                }
        }
    }
}

struct RewriteCommitDrag: ViewModifier {
    let commit: Commit

    func body(content: Content) -> some View {
        content.draggable(RewriteDrag.commit(commit.id)) {
            HStack(spacing: Vrai.Space.s6) {
                Text(commit.id.short)
                    .font(Font.Vrai.codeSmall)
                    .foregroundStyle(Color.Vrai.textTertiary)
                Text(commit.subject)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, Vrai.Space.s8)
            .frame(height: Vrai.Size.controlSm)
            .background(Color.Vrai.surfaceRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.Vrai.border, lineWidth: Metrics.hairline))
        }
    }
}

@MainActor
enum RewriteDrop {
    static func handle(_ item: String, window: WindowModel) -> Bool {
        if item.hasPrefix(RewriteDrag.branchPrefix) {
            let name = String(item.dropFirst(RewriteDrag.branchPrefix.count))
            guard window.store.snapshot?.branches.contains(where: { $0.name == name }) == true else { return false }
            RewriteActions.confirmDropBranch(window, name: name)
            return true
        }
        if item.hasPrefix(RewriteDrag.commitPrefix), let id = OID(String(item.dropFirst(RewriteDrag.commitPrefix.count))) {
            RewriteActions.confirmDropCommit(window, id: id)
            return true
        }
        return false
    }
}

struct RewriteMenuState {
    let inHead: Bool
    let isTip: Bool
    let isMerge: Bool
    let bisecting: Bool
    let onBranch: Bool
    let inProgress: Bool

    @MainActor init(window: WindowModel, id: OID?) {
        let store = window.store
        let snapshot = store.snapshot
        if let id {
            inHead = HeadReach.reachable(store).contains(id)
            isTip = snapshot?.headOID == id
            let commit = store.history.index[id].map { store.history.commits[$0] } ?? (store.detail?.commit.id == id ? store.detail?.commit : nil)
            isMerge = (commit?.parents.count ?? 1) > 1
        } else {
            inHead = false
            isTip = false
            isMerge = false
        }
        if case .bisecting? = snapshot?.state { bisecting = true } else { bisecting = false }
        onBranch = snapshot?.head.branchName != nil
        inProgress = snapshot?.state.isOperationInProgress ?? false
    }
}
