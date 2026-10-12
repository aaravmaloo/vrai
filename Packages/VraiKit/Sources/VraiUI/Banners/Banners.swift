import SwiftUI
import VraiCore
import VraiGit

struct BannerAction: Identifiable {
    var title: String
    var primary = false
    var enabled = false
    var perform: (@MainActor () -> Void)?
    var busy = false

    var id: String { title }
}

struct BannerSteps: Hashable {
    var current: Int
    var total: Int
    var stopped = false
}

struct BannerModel: Identifiable {
    var id: String
    var tone: Tone
    var icon: String
    var title: String
    var detail: String?
    var steps: BannerSteps?
    var actions: [BannerAction] = []
}

struct BannerView: View {
    let model: BannerModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Vrai.Space.s12) {
                icon
                text(lines: 2)
                    .frame(minWidth: Metrics.bannerText, idealWidth: Metrics.bannerText, maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(-1)
                steps
                actions
            }
            VStack(alignment: .leading, spacing: Vrai.Space.s8) {
                HStack(alignment: .top, spacing: Vrai.Space.s12) {
                    icon
                    text(lines: 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    steps
                }
                if !model.actions.isEmpty {
                    FlowLayout(spacing: Vrai.Space.s8, lineSpacing: Vrai.Space.s8) { buttons }
                        .padding(.leading, Vrai.Size.icon + Vrai.Space.s12)
                }
            }
        }
        .padding(.vertical, Vrai.Space.s8)
        .padding(.leading, Vrai.Space.s16)
        .padding(.trailing, Vrai.Space.s12)
        .frame(minHeight: Metrics.bannerHeight)
        .glassEffect(.regular.tint(model.tone.soft), in: .rect(cornerRadius: Vrai.Radius.lg))
        .padding(.horizontal, Vrai.Space.s8)
        .padding(.vertical, Vrai.Space.s4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.title)
    }

    var icon: some View {
        Symbol(model.icon, font: Font.Vrai.title3)
            .foregroundStyle(model.tone.color)
            .frame(width: Vrai.Size.icon)
    }

    func text(lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.title)
                .font(Font.Vrai.headline)
                .foregroundStyle(Color.Vrai.text)
                .lineLimit(lines == 2 ? 1 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: Metrics.headlineLine)
            if let detail = model.detail {
                Text(detail)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.textSecondary)
                    .lineLimit(lines)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: Metrics.calloutLine)
            }
        }
    }

    @ViewBuilder var steps: some View {
        if let steps = model.steps {
            HStack(spacing: Vrai.Space.s8) {
                Text("\(steps.current) of \(steps.total)", bundle: .module)
                    .font(Font.Vrai.caption)
                    .monospacedDigit()
                HStack(spacing: Vrai.Space.s4) {
                    ForEach(0..<max(0, steps.total), id: \.self) { index in
                        StepDot(state: index < steps.current - 1 ? .done : index == steps.current - 1 ? (steps.stopped ? .stopped : .now) : .todo, tone: model.tone)
                    }
                }
            }
            .foregroundStyle(Color.Vrai.textSecondary)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Step \(steps.current) of \(steps.total)", bundle: .module))
            .accessibilityAddTraits(.isStaticText)
        }
    }

    @ViewBuilder var actions: some View {
        if !model.actions.isEmpty {
            HStack(spacing: Vrai.Space.s8) { buttons }
                .fixedSize()
        }
    }

    var buttons: some View {
        ForEach(model.actions) { action in
            Button {
                action.perform?()
            } label: {
                HStack(spacing: Vrai.Space.s4) {
                    if action.busy { Spinner() }
                    Text(action.title)
                }
            }
            .buttonStyle(VraiButtonStyle(variant: action.primary ? .primary : .secondary, size: .small))
            .disabled(!action.enabled)
            .fixedSize()
        }
    }
}

struct StepDot: View {
    enum State {
        case todo
        case done
        case now
        case stopped
    }

    let state: State
    let tone: Tone

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: Vrai.Space.s6, height: Vrai.Space.s6)
            .background {
                if state == .now || state == .stopped {
                    Circle()
                        .fill(halo)
                        .frame(width: Vrai.Space.s6 + Vrai.Space.s4, height: Vrai.Space.s6 + Vrai.Space.s4)
                }
            }
    }

    var fill: Color {
        switch state {
        case .todo: Color.Vrai.fillStrong
        case .done: Color.Vrai.accentText
        case .now: tone == .danger ? Color.Vrai.danger : Color.Vrai.accentText
        case .stopped: Color.Vrai.warning
        }
    }

    var halo: Color {
        switch state {
        case .stopped: Color.Vrai.warningSoft
        case .now: tone == .danger ? Color.Vrai.dangerSoft : Color.Vrai.accentSoftStrong
        default: Color.clear
        }
    }
}

enum BannerBuilder {
    @MainActor static func banners(store: RepositoryStore) -> [BannerModel] {
        guard let snapshot = store.snapshot else { return [] }
        let details = store.stateDetails
        var out: [BannerModel] = []
        let head = headName(snapshot)
        switch snapshot.state {
        case .merging(let source):
            let left = snapshot.conflicts.count
            let name = source ?? String(localized: "the other branch", bundle: .module)
            if left > 0 {
                out.append(BannerModel(
                    id: "merge", tone: .warning, icon: "arrow.triangle.merge",
                    title: String(localized: "Merging \(name) into \(head): \(n(left, "conflict")) left", bundle: .module),
                    detail: String(localized: "Pick a side for each conflict or combine them, then mark the file resolved.", bundle: .module),
                    actions: (store.view != .changes ? [BannerAction(title: String(localized: "Resolve conflicts", bundle: .module), primary: true)] : []) + [BannerAction(title: String(localized: "Abort merge", bundle: .module))]
                ))
            } else {
                out.append(BannerModel(
                    id: "merge", tone: .success, icon: "arrow.triangle.merge",
                    title: String(localized: "Conflicts resolved", bundle: .module),
                    detail: String(localized: "Commit to finish merging \(name) into \(head).", bundle: .module),
                    actions: [BannerAction(title: String(localized: "Commit merge", bundle: .module), primary: true), BannerAction(title: String(localized: "Abort merge", bundle: .module))]
                ))
            }
        case .rebasing(let step, let total, let stopped, let reason, let branch, let onto):
            let branchName = branch ?? head
            let ontoName = details.ontoName ?? onto?.short ?? String(localized: "its base", bundle: .module)
            let at = stopped.map { $0.short + (details.subject.map { " " + $0 } ?? "") } ?? ""
            let detail: String
            switch reason {
            case .edit: detail = String(localized: "Stopped at \(at) so you can edit it. Amend the commit, then continue.", bundle: .module)
            case .conflict: detail = String(localized: "Stopped at \(at) because of conflicts. Resolve them, then continue.", bundle: .module)
            case .other: detail = String(localized: "Stopped at \(at). Continue when you're ready.", bundle: .module)
            }
            var actions = [BannerAction(title: String(localized: "Continue", bundle: .module), primary: true)]
            actions.append(BannerAction(title: reason == .conflict ? String(localized: "Resolve conflicts", bundle: .module) : String(localized: "Amend\u{2026}", bundle: .module)))
            actions.append(BannerAction(title: String(localized: "Skip", bundle: .module)))
            actions.append(BannerAction(title: String(localized: "Abort", bundle: .module)))
            out.append(BannerModel(
                id: "rebase", tone: reason == .conflict ? .danger : .warning, icon: "arrow.triangle.swap",
                title: String(localized: "Rebasing \(branchName) onto \(ontoName)", bundle: .module),
                detail: detail,
                steps: total > 0 ? BannerSteps(current: max(1, step), total: total, stopped: true) : nil,
                actions: actions
            ))
        case .cherryPicking(let id):
            let left = snapshot.conflicts.count
            let what = id.map { $0.short + (details.subject.map { " " + $0 } ?? "") } ?? String(localized: "a commit", bundle: .module)
            out.append(BannerModel(
                id: "cherry", tone: left > 0 ? .warning : .info, icon: "arrow.turn.down.right",
                title: String(localized: "Cherry-picking \(what)", bundle: .module),
                detail: left > 0 ? String(localized: "\(n(left, "conflict")) left. Resolve them, then continue.", bundle: .module) : String(localized: "Continue to commit it, or abort to go back.", bundle: .module),
                actions: [BannerAction(title: String(localized: "Continue", bundle: .module), primary: true), BannerAction(title: String(localized: "Skip", bundle: .module)), BannerAction(title: String(localized: "Abort", bundle: .module))]
            ))
        case .reverting(let id):
            let left = snapshot.conflicts.count
            let what = id.map { $0.short + (details.subject.map { " " + $0 } ?? "") } ?? String(localized: "a commit", bundle: .module)
            out.append(BannerModel(
                id: "revert", tone: left > 0 ? .warning : .info, icon: "arrow.uturn.backward",
                title: String(localized: "Reverting \(what)", bundle: .module),
                detail: left > 0 ? String(localized: "\(n(left, "conflict")) left. Resolve them, then continue.", bundle: .module) : String(localized: "Continue to commit the revert, or abort to go back.", bundle: .module),
                actions: [BannerAction(title: String(localized: "Continue", bundle: .module), primary: true), BannerAction(title: String(localized: "Skip", bundle: .module)), BannerAction(title: String(localized: "Abort", bundle: .module))]
            ))
        case .applyingPatches(let step, let total):
            out.append(BannerModel(
                id: "am", tone: .warning, icon: "bandage",
                title: String(localized: "Applying patches", bundle: .module),
                detail: String(localized: "Stopped at patch \(step) of \(total). Fix it, then continue.", bundle: .module),
                steps: total > 0 ? BannerSteps(current: max(1, step), total: total, stopped: true) : nil,
                actions: [BannerAction(title: String(localized: "Continue", bundle: .module), primary: true), BannerAction(title: String(localized: "Skip", bundle: .module)), BannerAction(title: String(localized: "Abort", bundle: .module))]
            ))
        case .bisecting(_, _, let current, _):
            let progress = details.bisect ?? BisectProgress()
            if let found = progress.found {
                out.append(BannerModel(
                    id: "bisect", tone: .success, icon: "scope",
                    title: String(localized: "\(found.short) is the first bad commit", bundle: .module),
                    detail: details.foundSubject.map { subject in
                        store.history.index[found].map { String(localized: "\(subject), by \(store.history.commits[$0].authorName).", bundle: .module) } ?? String(localized: "\(subject).", bundle: .module)
                    },
                    actions: [BannerAction(title: String(localized: "Show", bundle: .module), enabled: true, perform: { store.showRef(found.rawValue) }), BannerAction(title: String(localized: "End bisect", bundle: .module), primary: true)]
                ))
            } else {
                let steps = max(1, progress.steps)
                let at = current.map { $0.short + (details.subject.map { " " + $0 } ?? "") } ?? ""
                out.append(BannerModel(
                    id: "bisect", tone: .info, icon: "scope",
                    title: String(localized: "Finding the first bad commit, about \(n(steps, "step")) left", bundle: .module),
                    detail: String(localized: "Testing \(at). Build and try it, then mark it.", bundle: .module),
                    steps: BannerSteps(current: progress.done + 1, total: progress.done + steps),
                    actions: [BannerAction(title: String(localized: "Good", bundle: .module)), BannerAction(title: String(localized: "Bad", bundle: .module)), BannerAction(title: String(localized: "Skip", bundle: .module)), BannerAction(title: String(localized: "End", bundle: .module))]
                ))
            }
        case .detached(let id, _):
            let tag = snapshot.tags.first { $0.target == id }?.name
            var actions = [BannerAction(title: String(localized: "New branch here\u{2026}", bundle: .module))]
            if let back = details.previousBranch {
                actions.append(BannerAction(title: String(localized: "Back to \(back)", bundle: .module), primary: true))
            }
            out.append(BannerModel(
                id: "detached", tone: .info, icon: "mappin.and.ellipse",
                title: String(localized: "Looking at \(tag ?? id.short), not on a branch", bundle: .module),
                detail: String(localized: "Commits you make here won't belong to any branch. Create a branch to keep them.", bundle: .module),
                actions: actions
            ))
        case .clean:
            break
        }
        switch snapshot.network {
        case .authFailed(let host):
            let name = host ?? String(localized: "The remote", bundle: .module)
            out.append(BannerModel(
                id: "auth", tone: .danger, icon: "key",
                title: String(localized: "\(name) rejected your credentials", bundle: .module),
                detail: String(localized: "Sign in again to fetch, pull and push.", bundle: .module),
                actions: [BannerAction(title: String(localized: "Sign in again\u{2026}", bundle: .module), primary: true)]
            ))
        case .offline(let host):
            out.append(BannerModel(
                id: "offline", tone: .neutral, icon: "wifi.slash",
                title: String(localized: "Offline", bundle: .module),
                detail: String(localized: "Fetch, pull and push wait until \(host ?? String(localized: "the remote", bundle: .module)) is reachable. Everything else works.", bundle: .module)
            ))
        case .ok, .unknown:
            break
        }
        if let branch = snapshot.currentBranch, branch.upstreamGone, let upstream = branch.upstream {
            let remote = upstream.split(separator: "/").first.map(String.init) ?? upstream
            out.append(BannerModel(
                id: "gone", tone: .warning, icon: "cloud",
                title: String(localized: "\(upstream) is gone", bundle: .module),
                detail: String(localized: "It was deleted on \(remote). Push \(branch.name) to publish it again, or stop tracking it.", bundle: .module),
                actions: [BannerAction(title: String(localized: "Push \(branch.name)", bundle: .module), primary: true), BannerAction(title: String(localized: "Stop tracking", bundle: .module))]
            ))
        }
        let behind = snapshot.submodules.filter { $0.state == .behind }
        if !behind.isEmpty {
            out.append(BannerModel(
                id: "submodules", tone: .warning, icon: "cube",
                title: behind.count == 1 ? String(localized: "\(behind[0].path) is out of date", bundle: .module) : String(localized: "\(n(behind.count, "submodule")) are out of date", bundle: .module),
                detail: String(localized: "HEAD records newer commits than the ones checked out. Update to match.", bundle: .module),
                actions: [BannerAction(title: String(localized: "Update submodules", bundle: .module), primary: true)]
            ))
        }
        return out
    }

    static func headName(_ snapshot: RepositorySnapshot) -> String {
        switch snapshot.head {
        case .branch(let name), .unborn(let name): name
        case .detached(let id): id.short
        }
    }
}

struct BannerStack: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window

    var body: some View {
        let banners = SyncBanners.wire(BannerBuilder.banners(store: store).map { RewriteBanners.wire($0, window: window) }, window: window)
        if !banners.isEmpty {
            VStack(spacing: 0) {
                ForEach(banners) { BannerView(model: $0) }
            }
            .onChange(of: banners.map(\.id), initial: true) { old, new in
                let fresh = old == new ? new : new.filter { !old.contains($0) }
                for banner in banners where fresh.contains(banner.id) {
                    AccessibilityNotification.Announcement(banner.detail.map { banner.title + ". " + $0 } ?? banner.title).post()
                }
            }
        }
    }
}
