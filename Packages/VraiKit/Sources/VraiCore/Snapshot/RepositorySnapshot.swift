import Foundation
import VraiGit

public enum NetworkStatus: Sendable, Hashable {
    case unknown
    case ok
    case offline(host: String?)
    case authFailed(host: String?)
}

public struct RepositorySnapshot: Sendable, Hashable {
    public var root: URL?
    public var gitDir: URL
    public var commonDir: URL
    public var isBare: Bool
    public var isShallow: Bool
    public var head: Head
    public var headOID: OID?
    public var upstream: String?
    public var ahead: Int
    public var behind: Int
    public var branches: [Branch]
    public var remoteBranches: [RemoteBranch]
    public var remotes: [Remote]
    public var tags: [Tag]
    public var stashes: [Stash]
    public var worktrees: [Worktree]
    public var submodules: [Submodule]
    public var working: [WorkingFile]
    public var conflicts: [ConflictFile]
    public var state: RepoState
    public var hooks: [Hook]
    public var network: NetworkStatus
    public var lastFetch: Date?
    public var gitVersion: GitVersion
    public var branchColors: BranchColors
    public var hasCommitGraph: Bool

    public var currentBranch: Branch? { branches.first { $0.isCurrent } }

    public var tipColors: [OID: Int] {
        branchColors.tipColors(branches: branches, remoteBranches: remoteBranches, current: head.branchName)
    }
}
