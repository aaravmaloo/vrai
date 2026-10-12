import AppKit
import Observation
import SwiftUI
import VraiCore
import VraiGit

@MainActor
@Observable
public final class WindowModel {
    public enum Pane: Sendable {
        case list
        case detail
    }

    public let reference: RepositoryReference
    public let store: RepositoryStore
    public let preferences: Preferences
    public let toasts = ToastCenter()
    public let alerts = AlertCenter()
    public let sheets = SheetCenter()
    public let changes = ChangesModel()
    public let console = ConsoleModel()
    public let palette = PaletteModel()
    public let switcher = SwitcherModel()
    public let now: Date?
    public var pane: Pane = .list
    public var columns: NavigationSplitViewVisibility = .all
    public var query = ""
    public var author: String?
    public var widthClass: WidthClass = .wide
    public var expandedFolders: [String: Bool] = [:]
    public var expandedSections: [String: Bool] = [:]
    public var listFocused = false
    public var optionDown = false
    public var focusFilter = false
    public var switchRequest: RepositoryReference?

    public init(reference: RepositoryReference, store: RepositoryStore, preferences: Preferences, now: Date?) {
        self.reference = reference
        self.store = store
        self.preferences = preferences
        self.now = now
    }

    public var repositoryName: String { reference.name }

    public var sidebarShown: Bool {
        columns != .detailOnly
    }

    public func toggleSidebar() {
        columns = sidebarShown ? .detailOnly : .all
    }

    public func toggleSwitcher() {
        if switcher.open {
            switcher.dismiss()
            return
        }
        palette.dismiss()
        switcher.present()
    }

    func inherit(_ previous: WindowModel) {
        columns = previous.columns
        widthClass = previous.widthClass
    }

    public func copy(_ text: String, label: String? = nil) {
        Clipboard.copy(text)
        toasts.show(Toast(message: String(localized: "Copied \(label ?? text)", bundle: .module), icon: "doc.on.doc", timeout: Toast.brief))
    }

    public func reveal(_ path: String) {
        guard let root = store.snapshot?.root else { return }
        NSWorkspace.shared.activateFileViewerSelecting([root.appending(path: path)])
    }

    public func show(_ view: RepositoryView) {
        store.view = view
        store.sidebarSelection = nil
        pane = .list
    }

    public func select(_ selection: CommitSelection) {
        store.select(selection)
        if widthClass == .compact { pane = .detail }
    }

    public func toggleExpert() {
        preferences.expert.toggle()
        let on = preferences.expert
        toasts.show(Toast(
            message: on ? String(localized: "Expert mode is on", bundle: .module) : String(localized: "Expert mode is off", bundle: .module),
            detail: on ? String(localized: "Command previews, the console prompt, Reflog and Refs are now available.", bundle: .module) : String(localized: "Everything stays one step away in menus and the palette.", bundle: .module),
            icon: "terminal"
        ))
    }

    public var headName: String {
        guard let snapshot = store.snapshot else { return "" }
        return BannerBuilder.headName(snapshot)
    }

    public var selectedCommit: Commit? {
        guard let id = store.selection?.commitID else { return nil }
        if let detail = store.detail, detail.commit.id == id { return detail.commit }
        if let index = store.history.index[id] { return store.history.commits[index] }
        return nil
    }
}

struct WindowModelKey: FocusedValueKey {
    typealias Value = WindowModel
}

extension FocusedValues {
    var windowModel: WindowModel? {
        get { self[WindowModelKey.self] }
        set { self[WindowModelKey.self] = newValue }
    }
}
