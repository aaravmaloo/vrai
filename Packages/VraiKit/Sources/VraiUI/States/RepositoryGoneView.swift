import SwiftUI
import VraiCore
import VraiGit

enum RepositoryGone {
    static func check(_ path: String) -> Bool {
        var folder: ObjCBool = false
        return !FileManager.default.fileExists(atPath: path, isDirectory: &folder) || !folder.boolValue
    }
}

struct RepositoryGoneView: View {
    let name: String
    let path: String
    let retry: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        EmptyStateView(
            icon: "folder",
            title: String(localized: "\(name) isn't where it used to be", bundle: .module),
            message: String(localized: "Vrai can't find a repository at \(app.displayPath(URL(filePath: path))). It may have been moved, renamed or deleted. Locate it, or try again once it's back.", bundle: .module)
        ) {
            VraiButton(title: String(localized: "Locate\u{2026}", bundle: .module), icon: "folder", variant: .primary) {
                OpenPanel.choose(app: app) { reference in
                    openWindow(value: reference)
                    dismissWindow()
                }
            }
            .accessibilityIdentifier("repository-gone-locate")
            VraiButton(title: String(localized: "Try again", bundle: .module), icon: "arrow.clockwise", action: retry)
                .accessibilityIdentifier("repository-gone-retry")
        }
        .background(Color.Vrai.bg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("repository-gone")
    }
}
