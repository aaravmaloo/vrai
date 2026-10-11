import Foundation

public enum SharedCommands {
    public static func describe(_ id: String) -> GitCommand {
        .read(["describe", "--tags", "--always", id])
    }

    public static func nearestTag(_ id: String) -> GitCommand {
        .read(["describe", "--tags", "--abbrev=0", id])
    }

    public static func exactTag(_ revision: String = "HEAD") -> GitCommand {
        .read(["describe", "--tags", "--exact-match", revision], acceptedExitCodes: [0, 128])
    }

    public static func mergeTree(_ head: String, _ target: String) -> GitCommand {
        .read(["merge-tree", "--write-tree", "-z", "--name-only", "--no-messages", head, target], acceptedExitCodes: [0, 1])
    }

    public static func mergeTool(path: String) -> GitCommand {
        GitCommand(["mergetool", "--tool=opendiff", "--no-prompt", "--", path], access: .write)
    }

    public static func diffTool(path: String, staged: Bool = false) -> GitCommand {
        .read(["difftool", "--tool=opendiff", "--no-prompt"] + (staged ? ["--cached"] : []) + ["--", path])
    }

    public static func blob(_ id: String) -> GitCommand {
        .read(["cat-file", "blob", id])
    }

    public static func verifyCommit(_ id: String) -> GitCommand {
        .read(["verify-commit", id], acceptedExitCodes: [0, 1])
    }

    public static func verifyTag(_ name: String) -> GitCommand {
        .read(["verify-tag", name], acceptedExitCodes: [0, 1])
    }
}
