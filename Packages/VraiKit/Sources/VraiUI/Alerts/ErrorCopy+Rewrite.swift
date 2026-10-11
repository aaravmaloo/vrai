import VraiCore
import VraiGit

extension ErrorCopy {
    static func rewrite(_ error: GitError) -> ErrorCopy? {
        switch error.code {
        case .conflicts(let paths):
            let what = paths.count == 1 ? PathParts.split(paths[0]).name : n(paths.count, "file")
            return ErrorCopy(
                title: paths.isEmpty ? String(localized: "Stopped on conflicts", bundle: .module) : String(localized: "Conflicts in \(what)", bundle: .module),
                message: String(localized: "Both sides changed the same lines. Pick a side for each conflict in Changes, mark the files resolved, then continue.", bundle: .module)
            )
        case .unresolvedConflicts:
            return ErrorCopy(
                title: String(localized: "Some conflicts aren't resolved yet", bundle: .module),
                message: String(localized: "git can't continue while files still have conflicts. Resolve each one and mark the file resolved, then continue.", bundle: .module)
            )
        case .conflictMarkersRemain:
            return ErrorCopy(
                title: String(localized: "Conflict markers are still in the file", bundle: .module),
                message: String(localized: "Pick a side for each conflict that's left, or remove the markers in your editor, then mark it resolved.", bundle: .module)
            )
        case .notFastForward:
            return ErrorCopy(
                title: String(localized: "Can't fast-forward", bundle: .module),
                message: String(localized: "The branches have diverged. Merge with a merge commit instead.", bundle: .module)
            )
        case .stoppedForEdit:
            return ErrorCopy(
                title: String(localized: "Rebase stopped to let you edit", bundle: .module),
                message: String(localized: "Change what you need, then continue.", bundle: .module)
            )
        case .emptyCommit:
            return ErrorCopy(
                title: String(localized: "Nothing left to commit", bundle: .module),
                message: String(localized: "Its changes are already on this branch. Skip it to go on, or abort to go back.", bundle: .module)
            )
        case .nothingToStash:
            return ErrorCopy(
                title: String(localized: "No local changes to save", bundle: .module),
                message: String(localized: "The working tree is clean, so there's nothing to stash.", bundle: .module)
            )
        case .localChangesWouldBeOverwritten(let paths):
            let what = paths.count == 1 ? PathParts.split(paths[0]).name : (paths.isEmpty ? String(localized: "some files", bundle: .module) : n(paths.count, "file"))
            return ErrorCopy(
                title: String(localized: "Your changes would be overwritten", bundle: .module),
                message: String(localized: "You have uncommitted changes to \(what) that this would replace. Commit or stash them, then try again.", bundle: .module)
            )
        default:
            return nil
        }
    }
}
