import Observation
import SwiftUI

@MainActor
@Observable
public final class SwitcherModel {
    public var open = false
    public var query = ""
    public private(set) var session = 0

    public init() {}

    public func present() {
        query = ""
        session += 1
        open = true
    }

    public func dismiss() {
        open = false
    }
}
