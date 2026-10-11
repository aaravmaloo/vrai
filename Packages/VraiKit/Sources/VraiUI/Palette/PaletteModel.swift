import Observation
import SwiftUI

public enum PaletteMode: Sendable, Hashable {
    case everything
    case branches
}

@MainActor
@Observable
public final class PaletteModel {
    public var open = false
    public var mode: PaletteMode = .everything
    public var query = ""
    public private(set) var session = 0
    @ObservationIgnored var cachedFiles: [String]?
    @ObservationIgnored var cachedFilesKey: String?

    public init() {}

    public func present(_ mode: PaletteMode = .everything, query: String = "") {
        self.mode = mode
        self.query = query
        session += 1
        open = true
    }

    public func dismiss() {
        open = false
    }
}
