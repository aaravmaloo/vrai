import AppKit
import Observation

@MainActor
@Observable
public final class UpdateCheck {
    public var canCheck = false
    // Set when Sparkle runs. Debug builds and local releases have no update
    // feed, so the menu item explains that instead of sitting greyed out.
    public var managed = false
    @ObservationIgnored public var perform: @MainActor () -> Void = {}

    public init() {}

    public var disabled: Bool { managed && !canCheck }

    public func check() {
        guard managed else {
            explain()
            return
        }
        guard canCheck else { return }
        perform()
    }

    private func explain() {
        let alert = NSAlert()
        alert.messageText = String(localized: "This copy of Vrai doesn't update itself", bundle: .module)
        alert.informativeText = String(localized: "Only releases downloaded from GitHub check for updates. Development builds and releases built on this Mac don't.", bundle: .module)
        alert.addButton(withTitle: String(localized: "Open releases", bundle: .module))
        alert.addButton(withTitle: String(localized: "Close", bundle: .module))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(AppInfo.releases)
        }
    }
}
