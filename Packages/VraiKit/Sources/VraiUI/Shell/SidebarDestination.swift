import Foundation

public enum SidebarDestination: String, Hashable, Sendable, CaseIterable {
    case history
    case changes
    case stashes

    public var systemImage: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .changes: "square.and.pencil"
        case .stashes: "tray.full"
        }
    }

    public var title: String {
        switch self {
        case .history: String(localized: "History", bundle: .module)
        case .changes: String(localized: "Changes", bundle: .module)
        case .stashes: String(localized: "Stashes", bundle: .module)
        }
    }
}
