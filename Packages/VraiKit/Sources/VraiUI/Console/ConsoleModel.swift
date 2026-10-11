import Observation
import SwiftUI

@MainActor
@Observable
public final class ConsoleModel {
    public var open = false

    public init() {}

    public func toggle() {
        open.toggle()
    }
}
