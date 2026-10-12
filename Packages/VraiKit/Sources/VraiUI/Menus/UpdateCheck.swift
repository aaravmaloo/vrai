import Observation

@MainActor
@Observable
public final class UpdateCheck {
    public var canCheck = false
    @ObservationIgnored public var perform: @MainActor () -> Void = {}

    public init() {}

    public func check() {
        guard canCheck else { return }
        perform()
    }
}
