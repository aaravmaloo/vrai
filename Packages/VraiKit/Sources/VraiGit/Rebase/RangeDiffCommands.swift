import Foundation

public enum RangeDiffCommands {
    public static func lastMove(branch: String) -> GitCommand {
        .read(["log", "-g", "-1", "--format=%gs", "refs/heads/" + branch, "--"], acceptedExitCodes: [0, 128])
    }

    public static func previousTip(branch: String) -> GitCommand {
        .read(["rev-parse", "--verify", "--quiet", "refs/heads/" + branch + "@{1}"], acceptedExitCodes: [0, 1, 128])
    }

    public static func beforeRebase(branch: String) -> GitCommand {
        let ref = "refs/heads/" + branch
        return .read(["range-diff", ref + "@{1}..." + ref])
    }

    public static func wasRebase(_ reflogSubject: String) -> Bool {
        reflogSubject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("rebase")
    }
}
