import SwiftUI
import VraiCore
import VraiGit

struct SubmodulesView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var showDetail = false

    var body: some View {
        let modules = store.snapshot?.submodules ?? []
        Group {
            if modules.isEmpty {
                PlacesEmpty(icon: "shippingbox", title: String(localized: "No submodules", bundle: .module), message: String(localized: "Submodules pin another repository at an exact commit inside this one.", bundle: .module)) {
                    VraiButton(title: String(localized: "Add submodule\u{2026}", bundle: .module), icon: "plus") {
                        PlacesActions.openAddSubmodule(window)
                    }
                    .accessibilityIdentifier("submodule-add-empty")
                }
            } else {
                let selected = selection(in: modules)
                PlacesPane(showDetail: showDetail, backLabel: String(localized: "Submodules", bundle: .module), back: { showDetail = false }) {
                    VStack(spacing: 0) {
                        PlacesListHeader(title: String(localized: "Submodules", bundle: .module), caption: n(modules.count, "submodule")) {
                            IconButton(icon: "plus", label: String(localized: "Add submodule", bundle: .module)) {
                                PlacesActions.openAddSubmodule(window)
                            }
                            .accessibilityIdentifier("submodule-add")
                        }
                        PlacesList(label: String(localized: "Submodules", bundle: .module)) {
                            ForEach(modules) { module in
                                PlacesRow(
                                    icon: "shippingbox",
                                    title: module.path,
                                    subtitle: module.url.map(Self.shortURL),
                                    selected: module.path == selected?.path,
                                    identifier: "submodule-row-" + module.path,
                                    action: {
                                        store.sidebarSelection = PlacesActions.submoduleKey(module.path)
                                        showDetail = true
                                    },
                                    trailing: { SubmoduleBadge(module: module) }
                                )
                                .contextMenu { SubmoduleMenu(module: module, window: window, opener: PlacesOpener(app: app, openWindow: openWindow)) }
                            }
                        }
                    }
                } detail: {
                    if let selected {
                        SubmoduleDetail(module: selected, opener: PlacesOpener(app: app, openWindow: openWindow))
                            .id(selected.path)
                    }
                }
            }
        }
        .accessibilityIdentifier("submodules-view")
    }

    func selection(in modules: [Submodule]) -> Submodule? {
        if let key = store.sidebarSelection, key.hasPrefix("submodule:") {
            let path = String(key.dropFirst("submodule:".count))
            if let match = modules.first(where: { $0.path == path }) { return match }
        }
        return modules.first
    }

    static func shortURL(_ url: String) -> String {
        var value = url
        for prefix in ["https://", "http://"] where value.hasPrefix(prefix) { value.removeFirst(prefix.count) }
        return value
    }
}

struct SubmoduleBadge: View {
    let module: Submodule

    var body: some View {
        switch module.state {
        case .ahead:
            Badge(text: String(localized: "\(module.ahead) new", bundle: .module), tone: .warning)
        case .uninitialized:
            Badge(text: String(localized: "Off", bundle: .module), outline: true)
        case .behind:
            Badge(text: String(localized: "\(abs(module.ahead)) behind", bundle: .module), tone: .warning)
        case .modified:
            Badge(text: String(localized: "Changed", bundle: .module), tone: .warning)
        case .conflicted:
            Badge(text: String(localized: "Conflict", bundle: .module), tone: .danger)
        case .clean:
            EmptyView()
        }
    }
}

struct SubmoduleDetail: View {
    let module: Submodule
    let opener: PlacesOpener
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(\.expert) private var expert

    var body: some View {
        let busy = store.busy.contains("submodule")
        let state = Self.state(module)
        PlacesDetail(identifier: "submodule-detail") {
            PlacesTitle(title: module.path) {
                Badge(text: state.label, tone: state.tone)
            }
            KeyValueGrid {
                KeyValueRow(key: String(localized: "URL", bundle: .module)) {
                    Text(module.url ?? String(localized: "Not set", bundle: .module))
                        .font(Font.Vrai.codeSmall)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                KeyValueRow(key: String(localized: "Tracks", bundle: .module)) {
                    Text(module.branch ?? String(localized: "The remote's default branch", bundle: .module))
                }
                KeyValueRow(key: String(localized: "Recorded", bundle: .module)) {
                    Text(module.recorded.map { String($0.rawValue.prefix(10)) } ?? String(localized: "Nothing yet", bundle: .module))
                        .font(Font.Vrai.codeSmall)
                }
                KeyValueRow(key: String(localized: "Checked out", bundle: .module)) {
                    Text(module.checkedOut.map { String($0.rawValue.prefix(10)) } ?? String(localized: "Nothing yet", bundle: .module))
                        .font(Font.Vrai.codeSmall)
                }
            }
            if module.state == .ahead {
                RewriteCallout(tone: .warning, title: String(localized: "The checkout is \(n(module.ahead, "commit")) past what \(window.repositoryName) records", bundle: .module), message: String(localized: "Record the new commit to share it, or update to put the recorded one back.", bundle: .module))
            } else if module.state == .behind {
                RewriteCallout(tone: .warning, title: String(localized: "The checkout is \(n(abs(module.ahead), "commit")) behind what \(window.repositoryName) records", bundle: .module), message: String(localized: "Update to check out the recorded commit.", bundle: .module))
            }
            PlacesActionsRow {
                if module.state == .uninitialized {
                    PlacesBusyButton(title: String(localized: "Initialize and check out", bundle: .module), icon: "square.and.arrow.down", variant: .primary, busy: busy, identifier: "submodule-init") {
                        PlacesActions.submodule(window, path: module.path, action: .initUpdate)
                    }
                } else {
                    PlacesBusyButton(title: String(localized: "Update", bundle: .module), icon: "arrow.triangle.2.circlepath", variant: .primary, busy: busy, identifier: "submodule-update") {
                        PlacesActions.submodule(window, path: module.path, action: .update)
                    }
                }
                if module.state == .ahead || module.state == .behind {
                    VraiButton(title: String(localized: "Record new commit", bundle: .module), icon: "checkmark.circle") {
                        PlacesActions.submodule(window, path: module.path, action: .record)
                    }
                    .disabled(busy)
                    .accessibilityIdentifier("submodule-record")
                }
                VraiButton(title: String(localized: "Sync URL", bundle: .module), icon: "arrow.triangle.2.circlepath") {
                    PlacesActions.submodule(window, path: module.path, action: .sync)
                }
                .disabled(busy)
                .accessibilityIdentifier("submodule-sync")
                if module.state != .uninitialized {
                    VraiButton(title: String(localized: "Open in Vrai", bundle: .module), icon: "macwindow") {
                        if let root = store.snapshot?.root { opener.open(root.appending(path: module.path).path(percentEncoded: false), window: window) }
                    }
                    .accessibilityIdentifier("submodule-open")
                }
                VraiButton(title: String(localized: "Deinitialize\u{2026}", bundle: .module), icon: "trash", variant: .plain) {
                    PlacesActions.confirmDeinit(window, module: module)
                }
                .disabled(busy || module.state == .uninitialized)
                .accessibilityIdentifier("submodule-deinit")
            }
            if expert {
                RewriteCommandPreview(command: store.submoduleCommand(path: module.path, action: module.state == .uninitialized ? .initUpdate : .update))
            }
        }
    }

    static func state(_ module: Submodule) -> (label: String, tone: Tone) {
        switch module.state {
        case .clean: (String(localized: "Up to date", bundle: .module), .success)
        case .ahead: (String(localized: "\(n(module.ahead, "commit")) past the recorded one", bundle: .module), .warning)
        case .behind: (String(localized: "\(n(abs(module.ahead), "commit")) behind the recorded one", bundle: .module), .warning)
        case .modified: (String(localized: "Changed inside", bundle: .module), .warning)
        case .uninitialized: (String(localized: "Not initialized", bundle: .module), .neutral)
        case .conflicted: (String(localized: "In conflict", bundle: .module), .danger)
        }
    }
}

struct SubmoduleMenu: View {
    let module: Submodule
    let window: WindowModel
    let opener: PlacesOpener?

    var body: some View {
        if module.state == .uninitialized {
            MenuItem(title: String(localized: "Initialize and check out", bundle: .module), icon: "square.and.arrow.down", enabled: true) {
                PlacesActions.submodule(window, path: module.path, action: .initUpdate)
            }
        } else {
            MenuItem(title: String(localized: "Update", bundle: .module), icon: "arrow.triangle.2.circlepath", enabled: true) {
                PlacesActions.submodule(window, path: module.path, action: .update)
            }
        }
        if window.preferences.expert {
            MenuItem(title: String(localized: "Update from \(module.branch ?? String(localized: "the remote", bundle: .module))", bundle: .module), icon: "arrow.down.to.line", enabled: true) {
                PlacesActions.submodule(window, path: module.path, action: .updateRemote)
            }
        }
        if module.state == .ahead || module.state == .behind {
            MenuItem(title: String(localized: "Record new commit", bundle: .module), icon: "checkmark.circle", enabled: true) {
                PlacesActions.submodule(window, path: module.path, action: .record)
            }
        }
        MenuItem(title: String(localized: "Sync URL", bundle: .module), icon: "arrow.triangle.2.circlepath", enabled: true) {
            PlacesActions.submodule(window, path: module.path, action: .sync)
        }
        Divider()
        MenuItem(title: String(localized: "Open in Vrai", bundle: .module), icon: "macwindow", enabled: module.state != .uninitialized && opener != nil) {
            if let root = window.store.snapshot?.root { opener?.open(root.appending(path: module.path).path(percentEncoded: false), window: window) }
        }
        MenuItem(title: String(localized: "Reveal in Finder", bundle: .module), icon: "folder", enabled: true) {
            window.reveal(module.path)
        }
        MenuItem(title: String(localized: "Show details", bundle: .module), icon: "info.circle", enabled: true) {
            PlacesActions.showSubmodule(window, path: module.path)
        }
        Divider()
        MenuItem(title: String(localized: "Copy URL", bundle: .module), icon: "doc.on.doc", enabled: module.url != nil) {
            if let url = module.url { window.copy(url, label: String(localized: "URL", bundle: .module)) }
        }
        MenuItem(title: String(localized: "Deinitialize\u{2026}", bundle: .module), icon: "trash", enabled: module.state != .uninitialized, destructive: true) {
            PlacesActions.confirmDeinit(window, module: module)
        }
    }
}
