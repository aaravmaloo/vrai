import Combine
import Foundation
import Sparkle
import VraiCore
import VraiUI

@MainActor
final class SoftwareUpdater {
    let check = UpdateCheck()
    private var controller: SPUStandardUpdaterController?
    private var availability: AnyCancellable?

    init(bundle: Bundle = .main, arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard Self.isReleaseBuild, UpdateFeed(info: bundle.infoDictionary ?? [:], arguments: arguments) != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        let check = check
        check.managed = true
        check.perform = { [weak controller] in controller?.checkForUpdates(nil) }
        availability = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { value in
                MainActor.assumeIsolated { check.canCheck = value }
            }
    }

    // Started after launch so Sparkle's first prompt can't open while SwiftUI builds its scenes.
    func start() {
        controller?.startUpdater()
    }

    static var isReleaseBuild: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }
}
