import VraiGit

extension CoverageSamples {
    static var places: [GitCommand] {
        [
            PlacesCommands.addWorktree(path: "/tmp/vrai-sync-fix", branch: "fix/sync", createBranch: true),
            PlacesCommands.removeWorktree(path: "/tmp/vrai-sync-fix", force: false),
            PlacesCommands.lockWorktree(path: "/tmp/vrai-sync-fix", reason: "On a USB drive"),
            PlacesCommands.unlockWorktree(path: "/tmp/vrai-sync-fix"),
            PlacesCommands.pruneWorktrees(),
            PlacesCommands.listWorktrees,
            PlacesCommands.submodule(path: "Vendor/libgit2", action: .initUpdate),
            PlacesCommands.submodule(path: "Vendor/libgit2", action: .update),
            PlacesCommands.submodule(path: "Vendor/libgit2", action: .updateRemote),
            PlacesCommands.submodule(path: "Vendor/libgit2", action: .sync),
            PlacesCommands.submodule(path: "Vendor/libgit2", action: .record),
            PlacesCommands.submodule(path: "Vendor/libgit2", action: .deinit),
            PlacesCommands.addSubmodule(url: "https://github.com/apple/swift-argument-parser.git", path: "Vendor/swift-argument-parser"),
            PlacesCommands.reflog(),
            PlacesCommands.restoreReflog("HEAD@{1}"),
            PlacesCommands.blame(path: "README.md", at: "HEAD"),
            PlacesCommands.fileHistory(path: "README.md"),
            PlacesCommands.showFile(path: "README.md", at: "HEAD"),
            PlacesCommands.refs,
            PlacesCommands.listRefs,
            PlacesCommands.pseudoRef("ORIG_HEAD"),
            PlacesCommands.symbolicHead,
            PlacesCommands.removeReplacement("9eb0cce32029dc11166a4d37091afbef9d50d9bc")
        ]
    }
}
