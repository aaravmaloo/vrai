import AppKit
import VraiCore
import VraiGit

public enum NotificationFocus {
    static let key = "focusAlertsOnly"

    public static var alertsOnly: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

@MainActor
enum DockBadge {
    static func label(behind: [Int], failing: Int) -> String? {
        let total = behind.reduce(0, +) + failing
        return total > 0 ? String(total) : nil
    }

    static func refresh() {
        guard let app = SyncHub.shared.app, let dock = NSApp?.dockTile else { return }
        guard app.preferences.dockBadge else {
            dock.badgeLabel = nil
            return
        }
        var seen = Set<String>()
        let models = SyncHub.shared.allModels.filter { seen.insert(SyncModel.normalized($0.window.reference.path)).inserted }
        let behind = models.map { model in model.currentBranch.map { $0.upstream == nil ? 0 : $0.behind } ?? 0 }
        let failing = models.count { model in model.snapshot?.headOID.flatMap { model.window.checks.state(of: $0) } == .failed }
        dock.badgeLabel = label(behind: behind, failing: failing)
    }
}
