import Foundation

public enum RepoState: Sendable, Hashable {
    public enum StopReason: String, Sendable, Hashable {
        case conflict
        case edit
        case other
    }

    case clean
    case merging(source: String?)
    case rebasing(step: Int, total: Int, stoppedAt: OID?, reason: StopReason, branch: String?, onto: OID?)
    case cherryPicking(OID?)
    case reverting(OID?)
    case applyingPatches(step: Int, total: Int)
    case bisecting(good: [OID], bad: OID?, current: OID?, remaining: Int?)
    case detached(OID, nearestTag: String?)

    public var isOperationInProgress: Bool {
        switch self {
        case .clean, .detached: false
        default: true
        }
    }
}
