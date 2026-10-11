import Observation
import SwiftUI
import VraiCore
import VraiGit

public struct AlertAction: Identifiable {
    public enum Role {
        case standard
        case cancel
        case destructive
    }

    public let id = UUID()
    public var title: String
    public var role: Role = .standard
    public var enabled = true
    public var action: (@MainActor () -> Void)?

    public init(title: String, role: Role = .standard, enabled: Bool = true, action: (@MainActor () -> Void)? = nil) {
        self.title = title
        self.role = role
        self.enabled = enabled
        self.action = action
    }
}

public struct AlertRequest: Identifiable {
    public let id = UUID()
    public var title: String
    public var message: String?
    public var actions: [AlertAction]

    public init(title: String, message: String? = nil, actions: [AlertAction]) {
        self.title = title
        self.message = message
        self.actions = actions
    }
}

@MainActor
@Observable
public final class AlertCenter {
    public var current: AlertRequest?

    public init() {}

    public func present(_ request: AlertRequest) {
        current = request
    }

    public func present(_ error: GitError, retry: (@MainActor () -> Void)? = nil) {
        let copy = ErrorCopy(error)
        var actions: [AlertAction] = []
        if let retry { actions.append(AlertAction(title: String(localized: "Try again", bundle: .module), action: retry)) }
        actions.append(AlertAction(title: String(localized: "Close", bundle: .module), role: .cancel))
        current = AlertRequest(title: copy.title, message: copy.message, actions: actions)
    }
}

struct AlertHost: ViewModifier {
    @Bindable var center: AlertCenter

    func body(content: Content) -> some View {
        content.alert(
            center.current?.title ?? "",
            isPresented: Binding(get: { center.current != nil }, set: { if !$0 { center.current = nil } }),
            presenting: center.current
        ) { request in
            ForEach(request.actions) { action in
                Button(role: action.role.buttonRole) {
                    center.current = nil
                    action.action?()
                } label: {
                    Text(action.title)
                }
                .disabled(!action.enabled)
            }
        } message: { request in
            if let message = request.message { Text(message) }
        }
    }
}

extension AlertAction.Role {
    var buttonRole: ButtonRole? {
        switch self {
        case .standard: nil
        case .cancel: .cancel
        case .destructive: .destructive
        }
    }
}

struct ErrorCopy {
    var title: String
    var message: String

    init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    init(_ error: GitError) {
        if let copy = Self.changes(error) ?? Self.sync(error) ?? Self.rewrite(error) {
            self = copy
            return
        }
        switch error.code {
        case .gitNotFound:
            title = String(localized: "Git isn't installed", bundle: .module)
            message = String(localized: "Vrai runs the git you already have. Install the command line tools, then open the repository again.", bundle: .module)
        case .gitTooOld(let found, let needed):
            title = String(localized: "Git \(found.description) is too old", bundle: .module)
            message = String(localized: "Vrai needs git \(needed.description) or later. Update git, then open the repository again.", bundle: .module)
        case .notARepository:
            title = String(localized: "This folder isn't a git repository", bundle: .module)
            message = String(localized: "git can't find a repository here. Open the folder that holds the .git folder, or create a repository in it.", bundle: .module)
        case .lockFileExists(let path):
            title = String(localized: "Another git process is running", bundle: .module)
            message = String(localized: "git left a lock file at \(path ?? ".git/index.lock"). Wait for the other process to finish, then try again.", bundle: .module)
        default:
            title = String(localized: "git couldn't read this repository", bundle: .module)
            let detail = error.result?.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            message = detail.isEmpty ? String(localized: "Try again. If it keeps failing, check the repository in Terminal.", bundle: .module) : detail
        }
    }
}
