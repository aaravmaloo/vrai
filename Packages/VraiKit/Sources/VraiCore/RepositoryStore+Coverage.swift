import Foundation
import VraiGit

public struct PackSummary: Sendable, Hashable {
    public var looseBefore: Int
    public var looseAfter: Int
    public var packsBefore: Int
    public var packsAfter: Int

    public var packed: Int { max(0, looseBefore - looseAfter) }
}

public struct MaintenanceEverywhere: Sendable, Hashable {
    public var repositories: Int
    public var unreachable: [String]

    public var ran: Int { max(0, repositories - unreachable.count) }
}

extension RepositoryStore {
    public func compareWithBeforeRebase(branch: String) async throws -> GitResult? {
        let last = try await git.run(RangeDiffCommands.lastMove(branch: branch), background: true)
        guard last.exitCode == 0, RangeDiffCommands.wasRebase(last.output) else { return nil }
        let previous = try await git.run(RangeDiffCommands.previousTip(branch: branch), background: true)
        guard previous.exitCode == 0 else { return nil }
        let result = try await git.run(RangeDiffCommands.beforeRebase(branch: branch))
        if let entry = console.entry(for: result) { console.setExpanded(entry.id, true) }
        return result
    }

    @discardableResult
    public func annotate(path: String, at revision: String?) async throws -> GitResult {
        let result = try await git.run(PlacesCommands.annotate(path: path, at: revision))
        if let entry = console.entry(for: result) { console.setExpanded(entry.id, true) }
        return result
    }

    public func openDiffTool(path: String, staged: Bool) async throws {
        try await perform("difftool", refresh: false) {
            _ = try await git.run(SharedCommands.diffTool(path: path, staged: staged))
        }
    }

    public func rerereActive() async -> Bool {
        if let result = try? await git.run(ConflictRestart.rerereEnabled, background: true), result.exitCode == 0, let value = ConfigCommands.value(result.stdout).flatMap(ConfigBool.parse) {
            return value
        }
        guard let snapshot else { return false }
        return FileManager.default.fileExists(atPath: snapshot.commonDir.appending(path: "rr-cache").path(percentEncoded: false))
    }

    public func replayedResolutions() async -> Set<String> {
        guard let snapshot, let root = snapshot.root else { return [] }
        let candidates = snapshot.conflicts.filter { $0.kind == .bothModified || $0.kind == .bothAdded }.map(\.path)
        guard !candidates.isEmpty, await rerereActive() else { return [] }
        guard let result = try? await git.run(ConflictRestart.rerereRemaining, background: true), result.exitCode == 0 else { return [] }
        let remaining = ConflictRestart.remaining(result.output)
        return Set(candidates.filter { path in
            guard !remaining.contains(path), let text = try? ConflictFileText.read(root.appending(path: path)).text else { return false }
            return ConflictResolver.conflicts(in: text).isEmpty
        })
    }

    func conflictLabels(path: String, current: String?) async -> ConflictLabels {
        if let result = try? await git.run(ConflictRestart.mergedBlob(path: path), background: true), result.exitCode == 0, let labels = ConflictLabels.parse(result.output) {
            return labels
        }
        if let current, let labels = ConflictLabels.parse(current) { return labels }
        return .fallback
    }

    func relabelConflict(at url: URL, with labels: ConflictLabels) throws {
        let file = try ConflictFileText.read(url)
        let relabeled = ConflictRestart.relabel(file.text, with: labels)
        if relabeled != file.text { try file.write(relabeled, to: url) }
    }

    @discardableResult
    public func startOver(path: String) async throws -> Bool {
        try await perform("startOver") {
            guard let root = try await rewriteLocation().root else { throw GitError(.notARepository) }
            let url = root.appending(path: path)
            let stages = UnmergedStages.parse(try await git.run(RewriteCommands.unmergedStages(path: path), background: true).stdout)
            guard stages.isContentConflict else { throw GitError(.unknown(exit: 1, stderr: path)) }
            let labels = await conflictLabels(path: path, current: try? ConflictFileText.read(url).text)
            let result = try await git.run(ConflictRestart.mergeOneFile(path: path, stages: stages))
            try relabelConflict(at: url, with: labels)
            return result.exitCode != 0
        }
    }

    @discardableResult
    public func startOverEveryFile() async throws -> [String] {
        if snapshot == nil { try await refresh() }
        let paths = snapshot?.conflicts.filter { $0.kind == .bothModified || $0.kind == .bothAdded }.map(\.path) ?? []
        guard !paths.isEmpty else { return [] }
        return try await perform("startOver") {
            guard let root = try await rewriteLocation().root else { throw GitError(.notARepository) }
            var labels: [String: ConflictLabels] = [:]
            for path in paths {
                labels[path] = await conflictLabels(path: path, current: try? ConflictFileText.read(root.appending(path: path)).text)
            }
            _ = try await git.run(ConflictRestart.mergeIndex(paths: paths))
            for path in paths {
                try relabelConflict(at: root.appending(path: path), with: labels[path] ?? .fallback)
            }
            return paths
        }
    }

    public func packLooseObjects() async throws -> PackSummary {
        if snapshot == nil { try await refresh() }
        guard let snapshot else { throw GitError(.notARepository) }
        let base = snapshot.commonDir.appending(path: "objects/pack/pack").path(percentEncoded: false)
        let before = await objectStats()
        try await perform("packObjects") {
            _ = try await git.run(PackCommands.packLoose(into: base))
            _ = try await git.run(MaintenanceTask.prunePacked.command)
        }
        let after = await objectStats()
        return PackSummary(looseBefore: before.loose, looseAfter: after.loose, packsBefore: before.packs, packsAfter: after.packs)
    }

    public func redundantPacks() async throws -> [String] {
        try await perform("packRedundant", refresh: false) {
            var result = try await git.run(PackCommands.redundant())
            if result.exitCode == PackCommands.usageExit {
                result = try await git.run(PackCommands.redundant(confirmed: false))
            }
            if PackCommands.foundNoPacks(result) { return [] }
            guard result.exitCode == 0 else { throw ErrorClassifier.classify(result) }
            return PackCommands.redundantPacks(result.output)
        }
    }

    public func recoverObjects(fromPack url: URL) async throws -> Int {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw GitError(.unknown(exit: 1, stderr: error.localizedDescription))
        }
        let before = await objectStats()
        try await perform("unpackObjects") {
            _ = try await git.run(PackCommands.unpack(data))
        }
        let after = await objectStats()
        return max(0, after.loose - before.loose)
    }

    public func registeredRepositories() async -> [String] {
        guard let result = try? await git.run(MaintenanceCommands.registered, background: true) else { return [] }
        return ConfigCommands.values(result.stdout).filter { !$0.isEmpty }
    }

    public func runMaintenanceEverywhere() async throws -> MaintenanceEverywhere {
        let listed = await registeredRepositories()
        guard !listed.isEmpty else { return MaintenanceEverywhere(repositories: 0, unreachable: []) }
        return try await perform("maintenanceEverywhere") {
            var result = try await git.run(MaintenanceCommands.runEverywhere())
            if result.exitCode == PackCommands.usageExit {
                result = try await git.run(MaintenanceCommands.runEverywhere(keepGoing: false))
            }
            let unreachable = MaintenanceCommands.unreachable(result.errorOutput)
            if result.exitCode != 0, unreachable.isEmpty { throw ErrorClassifier.classify(result) }
            return MaintenanceEverywhere(repositories: listed.count, unreachable: unreachable)
        }
    }

    public func mergeHead(for source: String) async -> MergeHead? {
        guard let result = try? await git.run(ConsoleCommands.resolveCommit(source), background: true), result.exitCode == 0, let oid = OID(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let kind: MergeHead.Kind
        if snapshot?.branches.contains(where: { $0.name == source }) == true {
            kind = .branch
        } else if snapshot?.remoteBranches.contains(where: { $0.fullName == source }) == true {
            kind = .remoteBranch
        } else if snapshot?.tags.contains(where: { $0.name == source }) == true {
            kind = .tag
        } else {
            kind = .commit
        }
        return MergeHead(oid: oid, name: source, kind: kind)
    }

    public func defaultMergeMessage(source: String) async -> String? {
        guard let head = await mergeHead(for: source), let result = try? await git.run(MessageCommands.mergeMessage([head]), background: true) else { return nil }
        let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? nil : message
    }

    public func cleanMessage(_ text: String) async -> String {
        guard let result = try? await git.run(MessageCommands.cleanup(text), background: true) else { return text }
        return result.output
    }

    public func addTrailers(_ trailers: [Trailer], to message: CommitMessage) async throws -> CommitMessage {
        guard !trailers.isEmpty else { return message }
        let subject = message.subject.components(separatedBy: "\n").joined(separator: " ")
        let input = subject + "\n\n" + message.body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        let result = try await git.run(MessageCommands.addTrailers(trailers, to: input))
        let body = result.output.components(separatedBy: "\n").dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return CommitMessage(subject: message.subject, body: body)
    }
}
