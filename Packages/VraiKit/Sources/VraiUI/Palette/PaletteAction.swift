import SwiftUI
import VraiCore
import VraiGit

struct PaletteAction: Identifiable {
    var id: String
    var title: String
    var icon: String
    var shortcut: String?
    var keywords: [String]
    var enabled: Bool
    var expertOnly: Bool
    var detail: String?
    var danger: Bool
    var alternate: (@MainActor () -> Void)?
    var perform: @MainActor () -> Void

    init(id: String, title: String, icon: String, shortcut: String? = nil, keywords: [String] = [], enabled: Bool = true, expertOnly: Bool = false, detail: String? = nil, danger: Bool = false, alternate: (@MainActor () -> Void)? = nil, perform: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.icon = icon
        self.shortcut = shortcut
        self.keywords = keywords
        self.enabled = enabled
        self.expertOnly = expertOnly
        self.detail = detail
        self.danger = danger
        self.alternate = alternate
        self.perform = perform
    }
}

enum PaletteCatalog {
    @MainActor static func actions(_ window: WindowModel) -> [PaletteAction] {
        PlacesPaletteActions.actions(window) + LongTailPaletteActions.actions(window) + SettingsPaletteActions.actions(window)
    }
}
