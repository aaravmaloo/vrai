import SwiftUI
import VraiCore
import VraiGit

struct MaintenanceEverywhereRow: View {
    let context: SettingsContext
    let store: RepositoryStore
    var registered: Bool?
    @State private var count: Int?
    @State private var running = false

    var body: some View {
        SettingsRow(String(localized: "Run for every registered repository", bundle: .module), description: description) {
            if running {
                Spinner()
            } else {
                VraiButton(title: String(localized: "Run all", bundle: .module), icon: "wrench.and.screwdriver", size: .small, action: run)
                    .disabled(count == 0)
                    .accessibilityIdentifier("settings.maintenance.everywhere")
            }
        }
        .task(id: registered) { count = await store.registeredRepositories().count }
    }

    var description: String {
        guard let count else { return String(localized: "Runs git maintenance in each repository listed in maintenance.repo.", bundle: .module) }
        if count == 0 { return String(localized: "No repository is registered yet. Turn on Background maintenance to add this one.", bundle: .module) }
        return String(localized: "Runs git maintenance in the \(n(count, "repository")) listed in maintenance.repo.", bundle: .module)
    }

    func run() {
        running = true
        context.run {
            defer { running = false }
            let summary = try await store.runMaintenanceEverywhere()
            count = summary.repositories
            if summary.unreachable.isEmpty {
                context.toast(String(localized: "Maintenance finished in \(n(summary.ran, "repository"))", bundle: .module), detail: String(localized: "git for-each-repo ran it in every registered repository.", bundle: .module), icon: "wrench.and.screwdriver")
            } else {
                let missing = summary.unreachable.map { URL(filePath: $0).lastPathComponent }.joined(separator: ", ")
                context.toast(String(localized: "Maintenance ran in \(summary.ran) of \(n(summary.repositories, "repository"))", bundle: .module), detail: String(localized: "git couldn't open \(missing). Remove it from maintenance.repo if it's gone.", bundle: .module), icon: "wrench.and.screwdriver", tone: .warning)
            }
        }
    }
}
