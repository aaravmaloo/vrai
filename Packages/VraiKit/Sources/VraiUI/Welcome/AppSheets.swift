import AppKit
import Observation
import SwiftUI
import VraiCore
import VraiGit

public enum AppSheetKind: Identifiable, Hashable {
    case clone(url: String?)
    case open
    case newRepository(folder: String?)
    case reference(String)
    case bugReport

    public var id: String {
        switch self {
        case .clone: "clone"
        case .open: "open"
        case .newRepository: "init"
        case .reference(let command): "reference:" + command
        case .bugReport: "bugreport"
        }
    }
}

@MainActor
struct AppSheetContext {
    var dismiss: @MainActor () -> Void
    var opened: @MainActor (RepositoryReference) -> Void
    var switchTo: @MainActor (AppSheetKind) -> Void
    var toasts: ToastCenter?
    var store: RepositoryStore?
}

@MainActor
@Observable
public final class WelcomeModel {
    public static let shared = WelcomeModel()

    public var sheet: AppSheetKind?
    public var statuses: [String: RecentStatus] = [:]
    public var selected = 0
    public var missing: RecentRepository?
    public var closeAfterSheet = false

    public init() {}
}

struct AppSheetView: View {
    let kind: AppSheetKind
    let context: AppSheetContext

    var body: some View {
        switch kind {
        case .clone(let url):
            CloneSheet(initialURL: url, context: context)
        case .open:
            OpenSheet(context: context)
        case .newRepository(let folder):
            InitSheet(initialFolder: folder, context: context)
        case .reference(let command):
            GitReferenceSheet(command: command, context: context)
        case .bugReport:
            BugReportSheet(context: context)
        }
    }
}

@MainActor
enum AppSheets {
    private(set) static var app: AppModel?
    private(set) static var openWindow: OpenWindowAction?

    static func register(app: AppModel, openWindow: OpenWindowAction) {
        self.app = app
        self.openWindow = openWindow
    }

    static func present(_ kind: AppSheetKind, window: WindowModel?) {
        guard let app, let openWindow else { return }
        present(kind, window: window, app: app, openWindow: openWindow)
    }

    static func present(_ kind: AppSheetKind, window: WindowModel?, app: AppModel, openWindow: OpenWindowAction) {
        guard let window else {
            WelcomeModel.shared.sheet = kind
            openWindow(id: "welcome")
            return
        }
        let context = AppSheetContext(
            dismiss: { window.sheets.dismiss() },
            opened: { reference in openWindow(value: app.request(reference)) },
            switchTo: { next in
                window.sheets.dismiss()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    present(next, window: window, app: app, openWindow: openWindow)
                }
            },
            toasts: window.toasts,
            store: window.store
        )
        window.sheets.present { AppSheetView(kind: kind, context: context) }
    }

    static func closeWelcome(_ dismissWindow: DismissWindowAction) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            dismissWindow(id: "welcome")
            try? await Task.sleep(for: .milliseconds(300))
            for window in NSApp.windows where window.identifier?.rawValue.hasPrefix("welcome") == true && window.isVisible {
                window.close()
            }
        }
    }

    static func welcomeContext(openWindow: OpenWindowAction, dismissWindow: DismissWindowAction, app: AppModel) -> AppSheetContext {
        AppSheetContext(
            dismiss: { WelcomeModel.shared.sheet = nil },
            opened: { reference in
                openWindow(value: app.request(reference))
                let model = WelcomeModel.shared
                guard model.sheet != nil else {
                    closeWelcome(dismissWindow)
                    return
                }
                model.closeAfterSheet = true
                model.sheet = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    guard model.closeAfterSheet else { return }
                    model.closeAfterSheet = false
                    closeWelcome(dismissWindow)
                }
            },
            switchTo: { next in
                WelcomeModel.shared.sheet = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    WelcomeModel.shared.sheet = next
                }
            },
            toasts: nil,
            store: nil
        )
    }
}
