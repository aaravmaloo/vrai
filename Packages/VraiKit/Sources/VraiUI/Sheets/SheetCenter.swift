import Observation
import SwiftUI

public struct SheetRequest: Identifiable {
    public let id = UUID()
    public var content: AnyView

    public init<Content: View>(@ViewBuilder _ content: () -> Content) {
        self.content = AnyView(content())
    }
}

@MainActor
@Observable
public final class SheetCenter {
    public var current: SheetRequest?

    public init() {}

    public func present(_ request: SheetRequest) {
        current = request
    }

    public func present<Content: View>(@ViewBuilder _ content: () -> Content) {
        current = SheetRequest(content)
    }

    public func dismiss() {
        current = nil
    }
}

struct SheetHost: ViewModifier {
    @Bindable var center: SheetCenter

    func body(content: Content) -> some View {
        content.sheet(item: $center.current) { request in
            request.content
        }
    }
}
