import Foundation
import VraiGit

public struct PullDefaults: Sendable, Hashable {
    public var mode: PullMode
    public var autostash: Bool

    public init(mode: PullMode = .merge, autostash: Bool = false) {
        self.mode = mode
        self.autostash = autostash
    }
}

extension RepositoryStore {
    public func pullDefaults() async -> PullDefaults {
        async let rebase = configValue("pull.rebase")
        async let fastForward = configValue("pull.ff")
        async let rebaseStash = configValue("rebase.autoStash")
        async let mergeStash = configValue("merge.autoStash")
        let pullRebase = await rebase?.lowercased()
        let mode: PullMode
        if let pullRebase, ["true", "merges", "interactive", "i", "m", "yes", "on", "1"].contains(pullRebase) {
            mode = .rebase
        } else if await fastForward?.lowercased() == "only" {
            mode = .fastForwardOnly
        } else {
            mode = .merge
        }
        let stash = mode == .rebase ? await rebaseStash : await mergeStash
        return PullDefaults(mode: mode, autostash: ["true", "yes", "on", "1"].contains(stash?.lowercased() ?? ""))
    }

    public func signsTagsByDefault() async -> Bool {
        async let tag = configValue("tag.gpgSign")
        async let commit = configValue("commit.gpgSign")
        let yes = ["true", "yes", "on", "1"]
        if let tag = await tag?.lowercased() { return yes.contains(tag) }
        return yes.contains(await commit?.lowercased() ?? "")
    }

    func configValue(_ key: String) async -> String? {
        guard let result = try? await git.runAllowingFailure(.read(["config", "--get", key]), background: true), result.exitCode == 0 else { return nil }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
