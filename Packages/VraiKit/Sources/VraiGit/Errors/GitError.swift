import Foundation

public enum GitErrorCode: Sendable, Hashable {
    case gitNotFound
    case gitTooOld(found: GitVersion, needed: GitVersion)
    case notARepository
    case authFailed(host: String?)
    case networkUnreachable(host: String?)
    case remoteNotFound
    case pushRejected(behind: Int?)
    case protectedBranch
    case noUpstream
    case divergentBranches
    case conflicts(paths: [String])
    case unresolvedConflicts
    case conflictMarkersRemain
    case localChangesWouldBeOverwritten(paths: [String])
    case nothingToCommit
    case nothingToStash
    case emptyMessage
    case emptyCommit
    case hookFailed(name: String, output: String)
    case signingFailed(detail: String)
    case invalidRefName
    case refExists
    case refNotFound
    case branchNotMerged(count: Int?)
    case isCurrentBranch
    case branchCheckedOutElsewhere(path: String?)
    case notFastForward
    case patchDoesNotApply
    case stoppedForEdit
    case lockFileExists(path: String?)
    case pathExists
    case worktreeDirty
    case worktreeLocked
    case invalidURL
    case undoNoLongerApplies
    case cancelled
    case unknown(exit: Int32, stderr: String)

    public var name: String {
        switch self {
        case .gitNotFound: "gitNotFound"
        case .gitTooOld: "gitTooOld"
        case .notARepository: "notARepository"
        case .authFailed: "authFailed"
        case .networkUnreachable: "networkUnreachable"
        case .remoteNotFound: "remoteNotFound"
        case .pushRejected: "pushRejected"
        case .protectedBranch: "protectedBranch"
        case .noUpstream: "noUpstream"
        case .divergentBranches: "divergentBranches"
        case .conflicts: "conflicts"
        case .unresolvedConflicts: "unresolvedConflicts"
        case .conflictMarkersRemain: "conflictMarkersRemain"
        case .localChangesWouldBeOverwritten: "localChangesWouldBeOverwritten"
        case .nothingToCommit: "nothingToCommit"
        case .nothingToStash: "nothingToStash"
        case .emptyMessage: "emptyMessage"
        case .emptyCommit: "emptyCommit"
        case .hookFailed: "hookFailed"
        case .signingFailed: "signingFailed"
        case .invalidRefName: "invalidRefName"
        case .refExists: "refExists"
        case .refNotFound: "refNotFound"
        case .branchNotMerged: "branchNotMerged"
        case .isCurrentBranch: "isCurrentBranch"
        case .branchCheckedOutElsewhere: "branchCheckedOutElsewhere"
        case .notFastForward: "notFastForward"
        case .patchDoesNotApply: "patchDoesNotApply"
        case .stoppedForEdit: "stoppedForEdit"
        case .lockFileExists: "lockFileExists"
        case .pathExists: "pathExists"
        case .worktreeDirty: "worktreeDirty"
        case .worktreeLocked: "worktreeLocked"
        case .invalidURL: "invalidURL"
        case .undoNoLongerApplies: "undoNoLongerApplies"
        case .cancelled: "cancelled"
        case .unknown: "unknown"
        }
    }
}

public struct GitError: Error, Sendable, Hashable, CustomStringConvertible {
    public var code: GitErrorCode
    public var result: GitResult?

    public init(_ code: GitErrorCode, result: GitResult? = nil) {
        self.code = code
        self.result = result
    }

    public var description: String {
        var text = "GitError.\(code.name)"
        if let result { text += " from `\(result.command.display)` (exit \(result.exitCode)): \(result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))" }
        return text
    }
}
