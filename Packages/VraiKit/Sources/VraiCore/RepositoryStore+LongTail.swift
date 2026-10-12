import Foundation
import VraiGit

extension UndoEntry.Kind {
    public static let fixup = UndoEntry.Kind(rawValue: "fixup")
    public static let reword = UndoEntry.Kind(rawValue: "reword")
    public static let split = UndoEntry.Kind(rawValue: "split")
    public static let applyPatches = UndoEntry.Kind(rawValue: "applyPatches")
    public static let clean = UndoEntry.Kind(rawValue: "clean")
}

public struct RepositoryInfo: Sendable, Hashable {
    public struct Pack: Sendable, Hashable, Identifiable {
        public var name: String
        public var objects: Int
        public var bytes: Int64

        public var id: String { name }
    }

    public var name: String
    public var path: String
    public var commits: Int
    public var branches: Int
    public var tags: Int
    public var contributors: Int
    public var firstSubject: String?
    public var firstDate: Date?
    public var looseObjects: Int
    public var looseBytes: Int64
    public var packBytes: Int64
    public var packs: [Pack]
    public var garbage: Int
    public var remotes: [String]
    public var hooks: [String]
    public var objectFormat: String
    public var isShallow: Bool
    public var isBare: Bool
    public var partialFilter: String?
    public var sparse: Bool
    public var structure: [String: String]

    public var diskBytes: Int64 { looseBytes + packBytes }
}

public struct MaintenanceResult: Sendable, Hashable {
    public var task: MaintenanceTask
    public var before: Int64
    public var after: Int64
    public var packsBefore: Int
    public var packsAfter: Int
    public var looseBefore: Int
    public var looseAfter: Int
    public var output: String

    public init(task: MaintenanceTask, before: Int64, after: Int64, packsBefore: Int, packsAfter: Int, looseBefore: Int, looseAfter: Int, output: String) {
        self.task = task
        self.before = before
        self.after = after
        self.packsBefore = packsBefore
        self.packsAfter = packsAfter
        self.looseBefore = looseBefore
        self.looseAfter = looseAfter
        self.output = output
    }
}

public struct IntegrityReport: Sendable, Hashable {
    public var fsck: FsckReport
    public var packsChecked: Int
    public var badPacks: [String]

    public var isHealthy: Bool { fsck.isHealthy && badPacks.isEmpty }
}

public struct BranchComparison: Sendable, Hashable {
    public var base: String
    public var head: String
    public var onlyInBase: [ComparedCommit]
    public var onlyInHead: [ComparedCommit]
    public var baseCount: Int
    public var headCount: Int
    public var mergeBase: OID?
    public var mergeBaseName: String?
    public var files: [FileStat]
    public var command: GitCommand
}

public struct PullRequestSummary: Sendable, Hashable {
    public var text: String
    public var branch: String
    public var url: String
    public var published: Bool
}

public struct IgnoreResult: Sendable, Hashable {
    public var pattern: String
    public var added: Bool
    public var rule: String?
}

public struct CleanPlan: Sendable, Hashable {
    public var paths: [String]
    public var ignored: Bool
    public var files: [String]
    public var bytes: Int64
    public var keepsCopy: Bool
}

public struct FolderChange: Sendable, Hashable {
    public var id: OID
    public var date: Date
    public var subject: String
}

public struct SparseState: Sendable, Hashable {
    public var enabled: Bool
    public var folders: [String]
    public var available: [String]
}

extension RepositoryStore {
    public static let cleanCopyFileLimit = 2000
    public static let cleanCopyByteLimit: Int64 = 100 * 1024 * 1024

    func longTailRoot() async throws -> URL {
        if let root = snapshot?.root { return root }
        guard let root = try await rewriteLocation().root else { throw GitError(.notARepository) }
        return root
    }

    @discardableResult
    func withRefUndo<T: Sendable>(_ kind: UndoEntry.Kind, label: String, detail: String? = nil, _ body: () async throws -> T) async throws -> T {
        let before = try await rewriteRefs()
        let value = try await body()
        let after = try await rewriteRefs()
        try await recordRewrite(kind, label: label, detail: detail, before: before, after: after)
        return value
    }

    func messageEditor(_ messages: [String], gitDir: URL) throws -> (editor: String, file: URL) {
        guard let helper = EditorHelper.locate(environment: git.environment) else {
            throw GitError(.unknown(exit: 127, stderr: String(localized: "vrai-editor is missing, so Vrai can't hand the message to git. Reinstall Vrai.", bundle: .module)))
        }
        let folder = gitDir.appending(path: "vrai", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "history-messages-\(UUID().uuidString).json")
        let payload = messages.map { ["message": $0] }
        try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]).write(to: file, options: .atomic)
        return (EditorHelper.messageEditor(helper: helper, messages: file), file)
    }

    func removeMessages(_ file: URL) {
        try? FileManager.default.removeItem(at: file)
        try? FileManager.default.removeItem(at: URL(filePath: file.path(percentEncoded: false) + ".cursor"))
    }

    func usesHistory(for id: OID) async -> Bool {
        let version = snapshot?.gitVersion ?? git.executable.version
        guard version >= GitFeature.historyReword.minimumVersion else { return false }
        guard let result = try? await git.run(LongTailCommands.mergesSince(id.rawValue), background: true) else { return false }
        if Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1 > 0 { return false }
        return !(await isMergeCommit(id))
    }

    public func hasStagedChanges() async -> Bool {
        guard let result = try? await git.runAllowingFailure(LongTailCommands.hasStagedChanges(), background: true) else { return false }
        return result.exitCode == 1
    }

    public func hasUnstagedChanges() async -> Bool {
        guard let result = try? await git.runAllowingFailure(LongTailCommands.hasUnstagedChanges(), background: true) else { return false }
        return result.exitCode == 1
    }

    public func fixupCommitCommand(for id: OID) -> GitCommand {
        LongTailCommands.fixup(id.rawValue)
    }

    @discardableResult
    public func fixupCommit(for id: OID) async throws -> OID {
        let subject = await subject(of: id) ?? id.short
        return try await perform("fixup") {
            guard await hasStagedChanges() else { throw GitError(.nothingToCommit) }
            return try await withRefUndo(.fixup, label: String(localized: "Created fixup commit for \(id.short)", bundle: .module), detail: subject) {
                try await git.run(LongTailCommands.fixup(id.rawValue))
                guard let head = try await resolveCommit("HEAD") else { throw GitError(.refNotFound) }
                return head
            }
        }
    }

    public func commitMessage(of id: OID) async throws -> CommitMessage {
        let text = try await git.run(.read(["log", "-1", "--format=%B", id.rawValue, "--"]), background: true).output
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let subject = parts.first.map(String.init) ?? ""
        let body = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return CommitMessage(subject: subject, body: body)
    }

    public func laterCommitCount(after id: OID) async -> Int {
        (try? await commitCount(id.rawValue + "..HEAD")) ?? 0
    }

    public func rewordCommand(id: OID) -> GitCommand {
        LongTailCommands.historyReword(id.rawValue)
    }

    public func reword(id: OID, message: CommitMessage, useHistory: Bool? = nil) async throws {
        guard !message.isEmpty else { throw GitError(.emptyMessage) }
        let history: Bool
        if let useHistory { history = useHistory } else { history = await usesHistory(for: id) }
        guard history else {
            try await rewordWithRebase(id: id, message: message)
            return
        }
        try await perform("reword") {
            let gitDir = try await rewriteLocation().gitDir
            let prepared = try messageEditor([message.text], gitDir: gitDir)
            defer { removeMessages(prepared.file) }
            try await withRefUndo(.reword, label: String(localized: "Reworded \(id.short)", bundle: .module), detail: message.subject) {
                try await git.run(LongTailCommands.historyReword(id.rawValue, editor: prepared.editor))
            }
        }
    }

    func rewordWithRebase(id: OID, message: CommitMessage) async throws {
        let base = try await parentForRewrite(id)
        var steps = try await rebasePlan(onto: base)
        guard let index = steps.firstIndex(where: { $0.commit == id }) else { throw GitError(.refNotFound) }
        steps[index].action = .reword
        steps[index].message = message.text
        try await interactiveRebase(onto: base, plan: steps)
    }

    func parentForRewrite(_ id: OID) async throws -> String {
        guard let parent = try await resolveCommit(id.rawValue + "^") else {
            throw GitError(.unknown(exit: 1, stderr: String(localized: "This is the first commit, so there's no earlier commit to rebase onto.", bundle: .module)))
        }
        return parent.rawValue
    }

    public func commitFiles(id: OID) async throws -> [ChangedPath] {
        LongTailParsers.changedPaths(try await git.run(LongTailCommands.commitFiles(id.rawValue), background: true).stdout)
    }

    public func splitCommand(id: OID, keep paths: [String]) -> GitCommand {
        LongTailCommands.historySplit(id.rawValue, paths: paths)
    }

    public func split(id: OID, moving moved: [String], secondSubject: String, useHistory: Bool? = nil) async throws {
        let subject = secondSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty else { throw GitError(.emptyMessage) }
        let files = try await commitFiles(id: id)
        let all = files.map(\.path)
        let movedSet = Set(moved)
        let kept = all.filter { !movedSet.contains($0) }
        let movedKept = all.filter { movedSet.contains($0) }
        guard !kept.isEmpty, !movedKept.isEmpty else {
            throw GitError(.unknown(exit: 1, stderr: String(localized: "Pick some of the files, but not all of them. Each part needs at least 1 file.", bundle: .module)))
        }
        let original = try await commitMessage(of: id)
        let history: Bool
        if let useHistory { history = useHistory } else { history = await usesHistory(for: id) }
        guard history else {
            try await splitWithRebase(id: id, moving: movedKept, original: original, secondSubject: subject)
            return
        }
        let keptPaths = files.filter { !movedSet.contains($0.path) }.flatMap { [$0.path] + ($0.oldPath.map { [$0] } ?? []) }
        try await perform("split") {
            let gitDir = try await rewriteLocation().gitDir
            let prepared = try messageEditor([original.text, subject], gitDir: gitDir)
            defer { removeMessages(prepared.file) }
            try await withRefUndo(.split, label: String(localized: "Split \(id.short) in two", bundle: .module), detail: original.subject) {
                try await git.run(LongTailCommands.historySplit(id.rawValue, paths: keptPaths, editor: prepared.editor))
            }
        }
    }

    func splitWithRebase(id: OID, moving moved: [String], original: CommitMessage, secondSubject: String) async throws {
        let base = try await parentForRewrite(id)
        var steps = try await rebasePlan(onto: base)
        guard let index = steps.firstIndex(where: { $0.commit == id }) else { throw GitError(.refNotFound) }
        steps[index].action = .edit
        do {
            try await interactiveRebase(onto: base, plan: steps)
        } catch let error as GitError where error.code == .stoppedForEdit {
            let author = try await git.run(.read(["log", "-1", "--format=%an <%ae>%x00%ad", "--date=raw", id.rawValue, "--"]), background: true).output
            let parts = author.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\u{0}")
            try await perform("split") {
                try await git.run(RewriteCommands.reset(to: "HEAD^", mode: .soft))
                try await git.run(StagingService.unstageCommand(paths: moved, unborn: false))
                try await git.run(LongTailCommands.commitReusing(id.rawValue))
                try await git.run(LongTailCommands.addAll(moved))
                try await git.run(LongTailCommands.commit(message: secondSubject, author: parts.count == 2 ? String(parts[0]) : nil, date: parts.count == 2 ? String(parts[1]) : nil))
            }
            try await continueOperation()
        }
    }

    public func savePatchCommands(ids: [OID], to directory: URL) -> [GitCommand] {
        ids.enumerated().map { LongTailCommands.formatPatch($0.element.rawValue, number: $0.offset + 1, to: directory.path(percentEncoded: false)) }
    }

    @discardableResult
    public func savePatches(ids: [OID], to directory: URL) async throws -> [URL] {
        try await perform("savePatches", refresh: false) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var files: [URL] = []
            for command in savePatchCommands(ids: ids, to: directory) {
                let output = try await git.run(command).output
                for line in output.split(separator: "\n") where !line.isEmpty {
                    let path = String(line)
                    files.append(path.hasPrefix("/") ? URL(filePath: path) : directory.appending(path: URL(filePath: path).lastPathComponent))
                }
            }
            return files
        }
    }

    public func sendEmailCommand(files: [URL]) -> GitCommand {
        LongTailCommands.sendEmail(files: files.map { $0.path(percentEncoded: false) })
    }

    public func imapSendCommand() -> GitCommand {
        LongTailCommands.imapSend()
    }

    public func archiveCommand(ref: String, format: ArchiveFormat, prefix: String, paths: [String] = [], to file: URL) -> GitCommand {
        LongTailCommands.archive(ref: ref, format: format, prefix: prefix, output: file.path(percentEncoded: false), paths: paths)
    }

    @discardableResult
    public func exportArchive(ref: String, format: ArchiveFormat, prefix: String, paths: [String] = [], to file: URL) async throws -> URL {
        try await perform("archive", refresh: false) {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await git.run(archiveCommand(ref: ref, format: format, prefix: prefix, paths: paths, to: file))
            return file
        }
    }

    public func archiveCommitID(_ file: URL) async -> String? {
        guard let data = try? Data(contentsOf: file), let result = try? await git.runAllowingFailure(LongTailCommands.archiveCommitID(stdin: data), background: true), result.exitCode == 0 else { return nil }
        let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    public func bundleCommand(refs: [String], to file: URL) -> GitCommand {
        LongTailCommands.bundleCreate(file: file.path(percentEncoded: false), refs: refs)
    }

    @discardableResult
    public func createBundle(refs: [String], to file: URL) async throws -> URL {
        try await perform("bundle", refresh: false) {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await git.run(bundleCommand(refs: refs, to: file))
            return file
        }
    }

    public func applyPatchesCommand(files: [URL], threeWay: Bool, signoff: Bool) -> GitCommand {
        LongTailCommands.applyPatches(files: files.map { $0.path(percentEncoded: false) }, threeWay: threeWay, signoff: signoff)
    }

    @discardableResult
    public func applyPatches(files: [URL], threeWay: Bool, signoff: Bool) async throws -> Int {
        let names = files.map(\.lastPathComponent)
        let label = files.count == 1
            ? String(localized: "Applied \(names[0])", bundle: .module)
            : String(localized: "Applied \(n(files.count, "patch file"))", bundle: .module)
        return try await perform("am") {
            let before = try await resolveCommit("HEAD")
            try await withRefUndo(.applyPatches, label: label) {
                try await git.run(applyPatchesCommand(files: files, threeWay: threeWay, signoff: signoff))
            }
            guard let before else { return 0 }
            return (try? await commitCount(before.rawValue + "..HEAD")) ?? 0
        }
    }

    public func patchSummaries(files: [URL]) async -> [PatchSummary] {
        var out: [PatchSummary] = []
        let scratch = FileManager.default.temporaryDirectory.appending(path: "vrai-mail-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        for file in files {
            let folder = scratch.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            _ = try? await git.run(LongTailCommands.mailsplit(file: file.path(percentEncoded: false), to: folder.path(percentEncoded: false)), background: true)
            let mails = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
            for mail in mails {
                guard let data = try? Data(contentsOf: mail) else { continue }
                let message = folder.appending(path: "msg").path(percentEncoded: false)
                let patch = folder.appending(path: "patch").path(percentEncoded: false)
                guard let result = try? await git.run(LongTailCommands.mailinfo(message: message, patch: patch, mail: data), background: true) else { continue }
                out.append(LongTailParsers.mailinfo(result.output, file: file.lastPathComponent))
            }
        }
        return out
    }

    public func appliedPatchFiles(_ files: [URL], depth: Int = 300) async -> Set<URL> {
        guard let log = try? await git.run(.read(["log", "-p", "--no-color", "--no-ext-diff", "-n", String(depth), "HEAD", "--"]), background: true),
              let known = try? await git.run(LongTailCommands.patchID(stdin: log.stdout), background: true) else { return [] }
        let ids = Set(known.output.split(separator: "\n").compactMap { $0.split(separator: " ").first.map(String.init) })
        var applied: Set<URL> = []
        for file in files {
            guard let data = try? Data(contentsOf: file), let result = try? await git.run(LongTailCommands.patchID(stdin: data), background: true) else { continue }
            let patchIDs = result.output.split(separator: "\n").compactMap { $0.split(separator: " ").first.map(String.init) }
            if !patchIDs.isEmpty, patchIDs.allSatisfy({ ids.contains($0) }) { applied.insert(file) }
        }
        return applied
    }

    public func sparseState() async -> SparseState {
        let enabled = (try? await git.run(.read(["config", "--bool", "core.sparseCheckout"], acceptedExitCodes: [0, 1]), background: true).output.trimmingCharacters(in: .whitespacesAndNewlines)) == "true"
        var folders: [String] = []
        if enabled, let result = try? await git.runAllowingFailure(LongTailCommands.sparseList(), background: true), result.exitCode == 0 {
            folders = LongTailParsers.lines(result.output)
        }
        let data = (try? await git.run(LongTailCommands.topLevelFolders(), background: true).stdout) ?? Data()
        let available = data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }.filter { !$0.isEmpty }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return SparseState(enabled: enabled, folders: folders, available: available)
    }

    public func lastModified(paths: [String]) async -> [String: FolderChange] {
        guard !paths.isEmpty, let listed = try? await git.runAllowingFailure(LongTailCommands.lastModified(paths), background: true), listed.exitCode == 0 else { return [:] }
        let ids = LongTailParsers.lastModified(listed.stdout)
        guard !ids.isEmpty, let shown = try? await git.run(LongTailCommands.commitDates(Array(Set(ids.values.map(\.rawValue))).sorted()), background: true) else { return [:] }
        let dates = LongTailParsers.commitDates(shown.output)
        var out: [String: FolderChange] = [:]
        for (path, id) in ids {
            guard let found = dates[id] else { continue }
            out[path] = FolderChange(id: id, date: found.date, subject: found.subject)
        }
        return out
    }

    public func verifySignature(commit id: OID) async -> SignatureReport {
        await verify(SharedCommands.verifyCommit(id.rawValue))
    }

    public func verifySignature(tag name: String) async -> SignatureReport {
        await verify(SharedCommands.verifyTag(name))
    }

    func verify(_ command: GitCommand) async -> SignatureReport {
        do {
            let result = try await git.runAllowingFailure(command, background: true)
            return LongTailParsers.signature(result.errorOutput, exitCode: result.exitCode)
        } catch {
            return SignatureReport(good: false, signer: nil, keyType: nil, fingerprint: nil, message: String(describing: error))
        }
    }

    public func sparseCommand(folders: [String]) -> GitCommand {
        folders.isEmpty ? LongTailCommands.sparseDisable() : LongTailCommands.sparseSet(folders)
    }

    public func setSparseCheckout(dirs: [String]) async throws {
        try await perform("sparse") {
            _ = try await git.run(LongTailCommands.sparseSet(dirs))
        }
    }

    public func disableSparseCheckout() async throws {
        try await perform("sparse") {
            _ = try await git.run(LongTailCommands.sparseDisable())
        }
    }

    public func textFileURL(_ kind: TextFileKind) async throws -> URL {
        try await longTailRoot().appending(path: kind.fileName)
    }

    public func readTextFile(_ kind: TextFileKind) async throws -> String {
        let url = try await textFileURL(kind)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return "" }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func writeTextFile(_ kind: TextFileKind, contents: String) async throws {
        try await perform("textfile") {
            let url = try await textFileURL(kind)
            var text = contents
            if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
            try Data(text.utf8).write(to: url, options: .atomic)
        }
    }

    @discardableResult
    public func ignore(pattern raw: String) async throws -> IgnoreResult {
        let pattern = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { throw GitError(.unknown(exit: 1, stderr: String(localized: "There's nothing to ignore.", bundle: .module))) }
        return try await perform("ignore") {
            let url = try await textFileURL(.gitignore)
            var text = FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? try String(contentsOf: url, encoding: .utf8) : ""
            let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            let added = !lines.contains(pattern)
            if added {
                if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
                text += pattern + "\n"
                try Data(text.utf8).write(to: url, options: .atomic)
            }
            let probe = pattern.hasPrefix("*") ? "probe" + pattern.dropFirst() : (pattern.hasPrefix("/") ? String(pattern.dropFirst()) : pattern)
            let check = try await git.runAllowingFailure(LongTailCommands.ignoreCheck(probe), background: true)
            let rule = check.exitCode == 0 ? check.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil
            return IgnoreResult(pattern: pattern, added: added, rule: rule)
        }
    }

    public static func ignorePattern(forPath path: String) -> String {
        "/" + path.replacing(#/([*?\[\]!#\\])/#) { "\\" + $0.output.1 }
    }

    public static func ignorePattern(forExtension ext: String) -> String {
        "*" + (ext.hasPrefix(".") ? ext : "." + ext)
    }

    public func setAssumeUnchanged(paths: [String], on: Bool) async throws {
        try await perform("updateIndex") {
            for path in paths { try await git.run(LongTailCommands.assumeUnchanged(path, on)) }
        }
    }

    public func setSkipWorktree(paths: [String], on: Bool) async throws {
        try await perform("updateIndex") {
            for path in paths { try await git.run(LongTailCommands.skipWorktree(path, on)) }
        }
    }

    public func intentToAdd(paths: [String]) async throws {
        try await perform("intentToAdd") {
            _ = try await git.run(LongTailCommands.intentToAdd(paths))
        }
    }

    public func cleanPlan(ignored: Bool, paths: [String] = []) async throws -> CleanPlan {
        let root = try await longTailRoot()
        let output = try await git.run(LongTailCommands.cleanPreview(ignored: ignored, paths: paths), background: true).output
        let listed = LongTailParsers.cleanPreview(output)
        let (files, bytes) = Self.expand(listed, in: root)
        let keeps = files.count <= Self.cleanCopyFileLimit && bytes <= Self.cleanCopyByteLimit
        return CleanPlan(paths: listed, ignored: ignored, files: files, bytes: bytes, keepsCopy: keeps)
    }

    nonisolated static func expand(_ listed: [String], in root: URL) -> (files: [String], bytes: Int64) {
        var files: [String] = []
        var bytes: Int64 = 0
        let manager = FileManager.default
        let prefix = root.standardizedFileURL.path(percentEncoded: false)
        for entry in listed {
            let url = root.appending(path: entry)
            guard entry.hasSuffix("/") else {
                files.append(entry)
                bytes += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                continue
            }
            guard let walker = manager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { continue }
            while let file = walker.nextObject() as? URL {
                let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values?.isRegularFile == true else { continue }
                let full = file.standardizedFileURL.path(percentEncoded: false)
                files.append(String(full.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                bytes += Int64(values?.fileSize ?? 0)
            }
        }
        return (files, bytes)
    }

    public func cleanCommand(ignored: Bool, paths: [String] = []) -> GitCommand {
        LongTailCommands.clean(ignored: ignored, paths: paths)
    }

    public func clean(_ plan: CleanPlan) async throws {
        let label = plan.ignored
            ? String(localized: "Removed \(n(plan.files.count, "untracked or ignored file"))", bundle: .module)
            : String(localized: "Removed \(n(plan.files.count, "untracked file"))", bundle: .module)
        try await perform("clean") {
            var entry: UndoEntry?
            if plan.keepsCopy, !plan.files.isEmpty {
                let files = try await undo.snapshotFiles(plan.files)
                let made = UndoEntry(kind: .clean, label: label, detail: String(localized: "A copy stays in Undo history for 14 days", bundle: .module), files: files)
                try await undo.record(made)
                entry = made
            }
            do {
                try await git.run(LongTailCommands.clean(ignored: plan.ignored, paths: plan.paths))
            } catch {
                if let entry { try? await undo.forget(entry.id) }
                throw error
            }
            if let entry { try await undo.complete(entry.id) }
        }
    }

    public func moveFile(from: String, to: String) async throws {
        try await perform("mv") {
            _ = try await git.run(LongTailCommands.moveFile(from: from, to: to))
        }
    }

    public func removeFile(path: String, keepFile: Bool) async throws {
        try await perform("rm") {
            var entry: UndoEntry?
            if !keepFile {
                let files = try await undo.snapshotFiles([path])
                let made = UndoEntry(kind: .discardFile, label: String(localized: "Deleted \(PathParts.split(path).name)", bundle: .module), detail: String(localized: "A copy stays in Undo history for 14 days", bundle: .module), files: files)
                try await undo.record(made)
                entry = made
            }
            do {
                try await git.run(LongTailCommands.removeFile(path, keepFile: keepFile))
            } catch {
                if let entry { try? await undo.forget(entry.id) }
                throw error
            }
            if let entry { try await undo.complete(entry.id) }
        }
    }

    public func bugReportCommands(to directory: URL, diagnostics: Bool) -> [GitCommand] {
        var commands = [LongTailCommands.bugReport(to: directory.path(percentEncoded: false))]
        if diagnostics { commands.append(LongTailCommands.diagnose(to: directory.path(percentEncoded: false))) }
        return commands
    }

    @discardableResult
    public func bugReport(to directory: URL, diagnostics: Bool = true, note: String = "") async throws -> [URL] {
        try await perform("bugreport", refresh: false) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let before = Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? [])
            for command in bugReportCommands(to: directory, diagnostics: diagnostics) {
                try await git.run(command)
            }
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                try Data((trimmed + "\n").utf8).write(to: directory.appending(path: "what-happened.txt"), options: .atomic)
            }
            let after = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
            return after.filter { !before.contains($0) }.sorted().map { directory.appending(path: $0) }
        }
    }

    public func compareCommand(base: String, head: String) -> GitCommand {
        LongTailCommands.compare(base, head)
    }

    public func compare(base: String, head: String) async throws -> BranchComparison {
        let command = compareCommand(base: base, head: head)
        let listed = LongTailParsers.compared(try await git.run(command, background: true).stdout)
        let counts = LongTailParsers.leftRightCounts(try await git.run(LongTailCommands.compareCounts(base, head), background: true).output)
        var equivalentInBase: Set<String> = []
        var equivalentInHead: Set<String> = []
        if let result = try? await git.run(LongTailCommands.cherry(upstream: head, head: base), background: true) { equivalentInBase = LongTailParsers.cherryPicked(result.output) }
        if let result = try? await git.run(LongTailCommands.cherry(upstream: base, head: head), background: true) { equivalentInHead = LongTailParsers.cherryPicked(result.output) }
        var onlyBase: [ComparedCommit] = []
        var onlyHead: [ComparedCommit] = []
        for var commit in listed {
            if commit.side == .left {
                commit.equivalent = equivalentInBase.contains(commit.id.rawValue)
                onlyBase.append(commit)
            } else {
                commit.equivalent = equivalentInHead.contains(commit.id.rawValue)
                onlyHead.append(commit)
            }
        }
        var mergeBase: OID?
        var mergeBaseName: String?
        if let result = try? await git.run(LongTailCommands.mergeBase(base, head), background: true) {
            mergeBase = OID(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
            if let mergeBase, let named = try? await git.run(LongTailCommands.nameRev(mergeBase.rawValue), background: true) {
                let name = named.output.trimmingCharacters(in: .whitespacesAndNewlines)
                mergeBaseName = name.isEmpty || name == "undefined" ? nil : name
            }
        }
        var files: [FileStat] = []
        if let raw = try? await git.run(LongTailCommands.rawDiff(base, head), background: true), !raw.stdout.isEmpty,
           let stats = try? await git.run(LongTailCommands.pairStats(raw.stdout), background: true) {
            files = LongTailParsers.numstat(stats.stdout)
        }
        return BranchComparison(base: base, head: head, onlyInBase: onlyBase, onlyInHead: onlyHead, baseCount: counts.left, headCount: counts.right, mergeBase: mergeBase, mergeBaseName: mergeBaseName, files: files, command: command)
    }

    public func pullRequestSummary(branch: String, base: String? = nil, remote: String? = nil) async throws -> PullRequestSummary {
        let snapshot = self.snapshot
        let upstream = snapshot?.branches.first { $0.name == branch }?.upstream
        let remoteName = remote ?? upstream?.split(separator: "/").first.map(String.init) ?? defaultRemoteName() ?? "origin"
        let urlResult = try await git.runAllowingFailure(LongTailCommands.remoteURL(remoteName), background: true)
        guard urlResult.exitCode == 0 else { throw GitError(.remoteNotFound, result: urlResult) }
        let url = urlResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let start: String
        if let base {
            start = base
        } else {
            let candidates = ["main", "master", "trunk"].filter { $0 != branch }
            let local = candidates.first { name in snapshot?.branches.contains { $0.name == name } ?? false }
            let remoteBase = candidates.map { remoteName + "/" + $0 }.first { name in snapshot?.remoteBranches.contains { $0.fullName == name } ?? false }
            start = remoteBase ?? local ?? "HEAD"
        }
        var command = LongTailCommands.requestPull(base: start, url: url, end: branch)
        command.acceptedExitCodes = [0, 1]
        let result = try await git.run(command, background: true)
        let published = (try? await git.runAllowingFailure(LongTailCommands.showRef("refs/remotes/" + remoteName + "/" + branch), background: true))?.exitCode == 0
        return PullRequestSummary(text: result.output, branch: branch, url: url, published: published && !result.errorOutput.contains("No match for commit"))
    }

    public func pullRequestCommand(branch: String) -> GitCommand {
        let base = ["main", "master", "trunk"].first { name in name != branch && (snapshot?.branches.contains { $0.name == name } ?? false) } ?? "main"
        let remote = defaultRemoteName() ?? "origin"
        let url = snapshot?.remotes.first { $0.name == remote }?.fetchURL ?? remote
        return LongTailCommands.requestPull(base: base, url: url, end: branch)
    }

    public func contributors() async -> [Contributor] {
        guard let result = try? await git.run(LongTailCommands.contributors(), background: true) else { return [] }
        return LongTailParsers.contributors(result.output)
    }

    public func mailmapPreview(contents: String) async -> [(from: String, to: String)] {
        let people = await contributors()
        guard !people.isEmpty else { return [] }
        let file = FileManager.default.temporaryDirectory.appending(path: "vrai-mailmap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        guard (try? Data(contents.utf8).write(to: file)) != nil else { return [] }
        let contacts = people.map { "\($0.name) <\($0.email)>" }
        guard let result = try? await git.run(LongTailCommands.mailmapPreview(file: file.path(percentEncoded: false), contacts: contacts), background: true) else { return [] }
        let mapped = LongTailParsers.lines(result.output)
        return zip(contacts, mapped).filter { $0.0 != $0.1 }.map { (from: $0.0, to: $0.1) }
    }

    public func attributes(for paths: [String]) async -> [String: [String: String]] {
        guard !paths.isEmpty, let result = try? await git.run(LongTailCommands.attributes(paths), background: true) else { return [:] }
        let fields = ParseSupportBridge.nulFields(result.stdout)
        var out: [String: [String: String]] = [:]
        var index = 0
        while index + 2 < fields.count {
            out[fields[index], default: [:]][fields[index + 1]] = fields[index + 2]
            index += 3
        }
        return out
    }

    public func partialCloneFilter() async -> String? {
        guard let result = try? await git.runAllowingFailure(LongTailCommands.partialCloneFilter(), background: true), result.exitCode == 0 else { return nil }
        let line = result.output.split(separator: "\n").first.map(String.init) ?? ""
        let value = line.split(separator: " ", maxSplits: 1).dropFirst().first.map { String($0).trimmingCharacters(in: .whitespaces) }
        return value.flatMap { $0.isEmpty ? nil : $0 }
    }

    public var hasPromisorPacks: Bool {
        guard let snapshot else { return false }
        let folder = snapshot.commonDir.appending(path: "objects/pack", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.contains { $0.hasSuffix(".promisor") }
    }

    public func isPartialClone() async -> Bool {
        await partialCloneFilter() != nil
    }

    func objectStats() async -> (loose: Int, looseBytes: Int64, packs: Int, packBytes: Int64, garbage: Int) {
        guard let result = try? await git.run(LongTailCommands.countObjects(), background: true) else { return (0, 0, 0, 0, 0) }
        let values = LongTailParsers.keyValues(result.output, separator: ":")
        func int(_ key: String) -> Int { Int(values[key] ?? "") ?? 0 }
        return (int("count"), Int64(int("size")) * 1024, int("packs"), Int64(int("size-pack")) * 1024, int("garbage"))
    }

    public func maintenanceCommand(_ task: MaintenanceTask) -> GitCommand {
        task.command
    }

    @discardableResult
    public func maintenance(_ task: MaintenanceTask) async throws -> MaintenanceResult {
        let stats = await objectStats()
        let output = try await perform("maintenance") {
            try await git.run(task.command).errorOutput
        }
        let after = await objectStats()
        return MaintenanceResult(task: task, before: stats.looseBytes + stats.packBytes, after: after.looseBytes + after.packBytes, packsBefore: stats.packs, packsAfter: after.packs, looseBefore: stats.loose, looseAfter: after.loose, output: output)
    }

    func packFiles() async -> [URL] {
        guard let location = try? await rewriteLocation() else { return [] }
        let commonDir = snapshot?.commonDir ?? location.gitDir
        let folder = commonDir.appending(path: "objects/pack", directoryHint: .isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "idx" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public func verifyIntegrity(packs checkPacks: Bool = false) async throws -> IntegrityReport {
        try await perform("fsck", refresh: false) {
            let result = try await git.runAllowingFailure(MaintenanceTask.fsck.command)
            var report = IntegrityReport(fsck: LongTailParsers.fsck(stdout: result.output, stderr: result.errorOutput), packsChecked: 0, badPacks: [])
            if result.exitCode != 0, report.fsck.problems.isEmpty, report.fsck.missing.isEmpty {
                report.fsck.problems.append(result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            guard checkPacks else { return report }
            for index in await packFiles() {
                let verified = try await git.runAllowingFailure(LongTailCommands.verifyPack(index.path(percentEncoded: false)))
                report.packsChecked += 1
                if verified.exitCode != 0 { report.badPacks.append(index.deletingPathExtension().lastPathComponent) }
            }
            return report
        }
    }

    public func repairPackIndex(_ pack: String) async throws {
        let folder = await packFiles().first?.deletingLastPathComponent()
        guard let folder else { return }
        try await perform("indexPack") {
            _ = try await git.run(LongTailCommands.repairPackIndex(folder.appending(path: pack + ".pack").path(percentEncoded: false)))
        }
    }

    public func repositoryInfo() async throws -> RepositoryInfo {
        if snapshot == nil { try await refresh() }
        guard let snapshot else { throw GitError(.notARepository) }
        let git = self.git
        async let commits = git.run(LongTailCommands.commitCount(), background: true)
        async let first = git.runAllowingFailure(LongTailCommands.firstCommit(), background: true)
        async let format = git.runAllowingFailure(LongTailCommands.objectFormat(), background: true)
        async let structure = git.runAllowingFailure(LongTailCommands.repoStructure(), background: true)
        async let info = git.runAllowingFailure(LongTailCommands.repoInfo(), background: true)
        let people = await contributors()
        let stats = await objectStats()
        let partial = await partialCloneFilter()
        let sparse = await sparseState()
        var packs: [RepositoryInfo.Pack] = []
        for index in await packFiles() {
            guard let data = try? Data(contentsOf: index), let listed = try? await git.run(LongTailCommands.packIndex(data), background: true) else { continue }
            let pack = index.deletingPathExtension().appendingPathExtension("pack")
            let bytes = Int64((try? pack.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            packs.append(RepositoryInfo.Pack(name: index.deletingPathExtension().lastPathComponent, objects: LongTailParsers.objectCount(showIndex: listed.output), bytes: bytes))
        }
        let count = Int((try? await commits)?.output.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        var firstSubject: String?
        var firstDate: Date?
        if let result = try? await first, result.exitCode == 0 {
            let fields = ParseSupportBridge.nulFields(result.stdout)
            var index = 0
            while index + 2 < fields.count {
                let date = TimeInterval(fields[index + 2].trimmingCharacters(in: .whitespacesAndNewlines)).map { Date(timeIntervalSince1970: $0) }
                if let date, date < (firstDate ?? .distantFuture) {
                    firstDate = date
                    firstSubject = fields[index + 1]
                }
                index += 3
            }
        }
        let objectFormat = (try? await format).map { $0.output.trimmingCharacters(in: .whitespacesAndNewlines) } ?? "sha1"
        var lines: [String: String] = [:]
        if let result = try? await structure, result.exitCode == 0 { lines = LongTailParsers.keyValues(result.output, separator: "=") }
        if let result = try? await info, result.exitCode == 0 {
            for (key, value) in LongTailParsers.nulKeyValues(result.stdout) { lines[key] = value }
        }
        let root = snapshot.root ?? snapshot.gitDir
        return RepositoryInfo(
            name: root.lastPathComponent,
            path: root.path(percentEncoded: false),
            commits: count,
            branches: snapshot.branches.count,
            tags: snapshot.tags.count,
            contributors: people.count,
            firstSubject: firstSubject,
            firstDate: firstDate,
            looseObjects: stats.loose,
            looseBytes: stats.looseBytes,
            packBytes: stats.packBytes,
            packs: packs,
            garbage: stats.garbage,
            remotes: snapshot.remotes.map(\.name),
            hooks: snapshot.hooks.filter(\.enabled).map(\.name),
            objectFormat: objectFormat.isEmpty ? "sha1" : objectFormat,
            isShallow: snapshot.isShallow,
            isBare: snapshot.isBare,
            partialFilter: partial,
            sparse: sparse.enabled,
            structure: lines
        )
    }
}
