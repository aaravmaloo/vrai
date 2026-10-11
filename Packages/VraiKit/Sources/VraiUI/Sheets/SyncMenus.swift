import SwiftUI
import VraiCore
import VraiGit

extension SyncModel {
    func busyLabel(_ kind: SyncKind) -> String? {
        guard let run = running[kind] else { return nil }
        let verb: String = switch kind {
        case .fetch: String(localized: "Fetching", bundle: .module)
        case .pull: String(localized: "Pulling", bundle: .module)
        case .push: String(localized: "Pushing", bundle: .module)
        }
        guard let progress = run.progress else { return verb }
        if let percent = progress.percent { return verb + ": " + progress.phase + " " + String(percent) + "%" }
        return verb + ": " + progress.phase
    }
}

struct SyncMenuItems: View {
    let window: WindowModel
    let labels: SyncLabels

    var body: some View {
        let sync = window.sync
        let branch = window.store.snapshot?.currentBranch
        let behind = branch?.behind ?? 0
        Button {
            sync.fetch()
        } label: {
            Label(String(localized: "Fetch", bundle: .module), systemImage: "arrow.triangle.2.circlepath")
        }
        .modifierKeyAlternate(.option) {
            Button {
                sync.fetch(all: true)
            } label: {
                Label(String(localized: "Fetch all remotes and prune", bundle: .module), systemImage: "arrow.triangle.2.circlepath")
            }
        }
        Button {
            sync.pull()
        } label: {
            Label(behind > 0 ? String(localized: "Pull \(n(behind, "commit"))", bundle: .module) : String(localized: "Pull", bundle: .module), systemImage: "arrow.down.to.line")
        }
        .disabled(branch == nil)
        .modifierKeyAlternate(.option) {
            Button {
                sync.pull(mode: .rebase)
            } label: {
                Label(String(localized: "Pull with rebase", bundle: .module), systemImage: "arrow.down.to.line")
            }
            .disabled(branch == nil)
        }
        Button {
            sync.push()
        } label: {
            Label(SyncMenuItems.pushLabel(branch), systemImage: "arrow.up.to.line")
        }
        .disabled(branch == nil)
        .modifierKeyAlternate(.option) {
            Button(role: .destructive) {
                sync.push(force: .withLease)
            } label: {
                Label(String(localized: "Force push with lease", bundle: .module), systemImage: "arrow.up.to.line")
            }
            .disabled(branch == nil)
        }
    }

    static func pushLabel(_ branch: Branch?) -> String {
        guard let branch else { return String(localized: "Push", bundle: .module) }
        if branch.ahead > 0 { return String(localized: "Push \(n(branch.ahead, "commit"))", bundle: .module) }
        if branch.upstream == nil { return String(localized: "Publish \(branch.name)", bundle: .module) }
        return String(localized: "Push", bundle: .module)
    }
}

enum SyncBanners {
    @MainActor static func wire(_ banners: [BannerModel], window: WindowModel) -> [BannerModel] {
        let sync = window.sync
        let store = window.store
        return banners.compactMap { banner in
            var banner = banner
            switch banner.id {
            case "detached":
                guard let head = store.snapshot?.headOID else { return banner }
                let back = store.stateDetails.previousBranch
                banner.actions = banner.actions.enumerated().map { index, action in
                    var action = action
                    action.enabled = true
                    if index == 0 {
                        action.perform = { sync.newBranch(from: head.rawValue, checkout: true) }
                    } else if let back {
                        action.perform = { sync.switchTo(back) }
                    }
                    return action
                }
            case "auth":
                guard sync.surfaced else { return nil }
                banner.actions = banner.actions.map { action in
                    var action = action
                    action.enabled = true
                    action.perform = { sync.signIn(nil, retry: nil) }
                    return action
                }
            case "offline":
                guard sync.surfaced else { return nil }
            case "gone":
                guard let branch = store.snapshot?.currentBranch else { return banner }
                banner.actions = banner.actions.enumerated().map { index, action in
                    var action = action
                    action.enabled = true
                    let name = branch.name
                    if index == 0 {
                        action.perform = { sync.push() }
                    } else {
                        action.perform = { sync.stopTracking(name) }
                    }
                    return action
                }
            default:
                break
            }
            return banner
        }
    }
}

enum SyncSidebar {
    @MainActor static func badge(for remote: Remote, snapshot: RepositorySnapshot) -> AnyView? {
        let host = RemoteURL(remote.pushURL ?? remote.fetchURL)?.host
        switch snapshot.network {
        case .authFailed(let failing) where failing == nil || failing == host:
            return AnyView(Symbol("key", font: Font.Vrai.callout)
                .foregroundStyle(Color.Vrai.textTertiary)
                .help(String(localized: "\(host ?? remote.name) didn't accept your credentials. Fetch \(remote.name) to sign in again.", bundle: .module))
                .accessibilityLabel(String(localized: "Sign in needed", bundle: .module)))
        case .offline(let failing) where failing == nil || failing == host:
            return AnyView(Symbol("wifi.slash", font: Font.Vrai.callout)
                .foregroundStyle(Color.Vrai.textTertiary)
                .help(String(localized: "Couldn't reach \(host ?? remote.name) on the last fetch.", bundle: .module))
                .accessibilityLabel(String(localized: "Offline", bundle: .module)))
        default:
            return nil
        }
    }
}
