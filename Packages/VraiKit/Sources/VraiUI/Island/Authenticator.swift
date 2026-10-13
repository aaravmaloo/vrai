import AppKit
import LocalAuthentication
import SwiftUI
import VraiCore

public struct SensitiveRequest {
    public var title: String
    public var detail: String
    public var reason: String
    public var icon: String

    public init(title: String, detail: String, reason: String, icon: String) {
        self.title = title
        self.detail = detail
        self.reason = reason
        self.icon = icon
    }
}

@MainActor
public enum Authenticator {
    public enum Outcome: Sendable, Equatable {
        case approved
        case cancelled
        case fallback
    }

    public static var stub: String?
    public static var sandboxed = false

    public static func configure(launch: LaunchOptions) {
        sandboxed = launch.isSandboxed
        stub = launch.auth
    }

    public static var biometricsAvailable: Bool {
        if sandboxed { return stub == "approve" || stub == "deny" }
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    static func evaluate(_ context: LAContext, policy: LAPolicy, reason: String) async -> Outcome {
        await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, error in
                if success {
                    continuation.resume(returning: .approved)
                    return
                }
                switch (error as? LAError)?.code {
                case .userCancel?, .appCancel?, .systemCancel?:
                    continuation.resume(returning: .cancelled)
                default:
                    continuation.resume(returning: .fallback)
                }
            }
        }
    }

    static func stubbed(_ delay: Duration = .milliseconds(700)) async -> Outcome {
        try? await Task.sleep(for: delay)
        return stub == "approve" ? .approved : .cancelled
    }

    public static func system(reason: String) async -> Bool {
        if sandboxed { return await stubbed(.milliseconds(50)) == .approved }
        return await evaluate(LAContext(), policy: .deviceOwnerAuthentication, reason: reason) == .approved
    }
}

extension IslandCenter {
    public func authenticate(_ request: SensitiveRequest, source: String?) async -> Bool {
        let context = Authenticator.sandboxed ? nil : LAContext()
        context?.localizedFallbackTitle = ""
        var activity = IslandActivity(phase: .authenticating, title: request.title, detail: request.detail, icon: request.icon, source: source, tint: .danger)
        activity.context = context
        activity.actions = [IslandAction(title: String(localized: "Cancel", bundle: .module), activates: false) { [weak self] in
            if let context { context.invalidate() } else { self?.stubCancelled = true }
        }]
        let id = show(activity)
        let outcome: Authenticator.Outcome
        if let context {
            try? await Task.sleep(for: .milliseconds(240))
            outcome = await Authenticator.evaluate(context, policy: .deviceOwnerAuthenticationWithBiometrics, reason: request.reason)
        } else {
            stubCancelled = false
            let stubbed = await Authenticator.stubbed()
            outcome = stubCancelled ? .cancelled : stubbed
        }
        switch outcome {
        case .approved:
            finish(id) { activity in
                activity.phase = .authenticated
                activity.title = String(localized: "Confirmed", bundle: .module)
                activity.detail = request.title
                activity.actions = []
                activity.context = nil
            }
            return true
        case .cancelled:
            dismiss(id, after: 0.1)
            return false
        case .fallback:
            dismiss(id, after: 0.1)
            return await Authenticator.system(reason: request.reason)
        }
    }
}

@MainActor
public enum Sensitive {
    public static func confirm(_ request: SensitiveRequest, preferences: Preferences, source: String?, alert: @escaping @MainActor () -> Void, perform: @escaping @MainActor () -> Void) {
        guard preferences.touchID, Authenticator.biometricsAvailable else {
            alert()
            return
        }
        Task { @MainActor in
            let island = IslandCenter.shared
            let approved = island.allows(.auth) ? await island.authenticate(request, source: source) : await Authenticator.system(reason: request.reason)
            if approved { perform() }
        }
    }
}
