import Foundation

public actor UndoStore {
    public static let retention: TimeInterval = 14 * 24 * 60 * 60
    public static let historyLimit = 50
    public static let refNamespace = "refs/vrai/undo/"
    public static let absent = OID(String(repeating: "0", count: 40))!
    public static let refMovingKinds: Set<UndoEntry.Kind> = [.commit, .amend, .merge, .pull, .rebase, .reset, .resetHard, .cherryPick, .revert]
    public static let refDeletingKinds: Set<UndoEntry.Kind> = [.branchDelete, .tagDelete]

    static let identity = [
        "GIT_AUTHOR_NAME": "Vrai",
        "GIT_AUTHOR_EMAIL": "undo@vrai.invalid",
        "GIT_COMMITTER_NAME": "Vrai",
        "GIT_COMMITTER_EMAIL": "undo@vrai.invalid"
    ]

    struct Location: Sendable {
        var commonDir: URL
        var gitDir: URL
        var root: URL
    }

    public let git: GitProcess
    public private(set) var entries: [UndoEntry] = []
    let now: @Sendable () -> Date
    var location: Location?

    public init(git: GitProcess) {
        self.init(git: git, now: { Date() })
    }

    public init(git: GitProcess, now: @escaping @Sendable () -> Date) {
        self.git = git
        self.now = now
    }

    public func journalURL() async throws -> URL {
        try await resolve().commonDir.appending(path: "vrai/undo.json")
    }

    public func worktreeRoot() async throws -> URL {
        try await resolve().root
    }

    func resolve() async throws -> Location {
        if let location { return location }
        let dirs = try await git.run(.read(["rev-parse", "--path-format=absolute", "--git-common-dir", "--absolute-git-dir"]), background: true).output.split(separator: "\n").map(String.init)
        guard dirs.count >= 2 else { throw GitError(.notARepository) }
        let top = try await git.runAllowingFailure(.read(["rev-parse", "--path-format=absolute", "--show-toplevel"]), background: true)
        let rootPath = top.succeeded ? top.output.trimmingCharacters(in: .newlines) : ""
        let resolved = Location(
            commonDir: URL(filePath: dirs[0], directoryHint: .isDirectory),
            gitDir: URL(filePath: dirs[1], directoryHint: .isDirectory),
            root: rootPath.isEmpty ? git.workingDirectory : URL(filePath: rootPath, directoryHint: .isDirectory)
        )
        location = resolved
        return resolved
    }

    func load() async throws -> [UndoEntry] {
        let loaded = UndoJournal.read(try await journalURL())
        entries = loaded
        return loaded
    }

    @discardableResult
    func mutate(_ change: (inout [UndoEntry]) -> Void) async throws -> [UndoEntry] {
        let url = try await journalURL()
        var list = UndoJournal.read(url)
        change(&list)
        try UndoJournal.write(list, to: url)
        entries = list
        return list
    }

    func loadCurrent() async throws -> [UndoEntry] {
        let list = try await load()
        let cutoff = now().addingTimeInterval(-Self.retention)
        let expired = Set(list.filter { $0.date < cutoff }.map(\.id))
        guard !expired.isEmpty else { return list }
        for id in expired { try await deleteRefs(of: id) }
        return try await mutate { $0.removeAll { expired.contains($0.id) } }
    }

    public func record(_ entry: UndoEntry) async throws {
        try await protect(entry)
        _ = try await loadCurrent()
        try await mutate { list in
            list.removeAll { $0.id == entry.id }
            list.insert(entry, at: 0)
        }
    }

    public func complete(_ id: UUID) async throws {
        guard let entry = try await load().first(where: { $0.id == id }) else { return }
        var refsAfter: [String: OID]?
        var filesAfter: [String: OID]?
        let refs = trackedRefs(entry)
        if !refs.isEmpty {
            var after: [String: OID] = [:]
            for ref in refs {
                let value = try await currentValue(of: ref)
                if !value.isZero { after[ref] = value }
            }
            refsAfter = after
        }
        if !entry.files.isEmpty {
            filesAfter = try await hashWorktree(Array(entry.files.keys), write: false)
        }
        try await mutate { list in
            guard let index = list.firstIndex(where: { $0.id == id }) else { return }
            if let refsAfter { list[index].refsAfter = refsAfter }
            if let filesAfter { list[index].filesAfter = filesAfter }
        }
    }

    public func forget(_ id: UUID) async throws {
        try await deleteRefs(of: id)
        try await mutate { $0.removeAll { $0.id == id } }
    }

    public func recent(limit: Int = UndoStore.historyLimit) async throws -> [UndoEntry] {
        Array(try await loadCurrent().prefix(limit))
    }

    public func entry(_ id: UUID) async throws -> UndoEntry? {
        try await loadCurrent().first { $0.id == id }
    }

    @discardableResult
    public func undoLast() async throws -> UndoEntry? {
        let busy = try await operationInProgress()
        for latest in try await loadCurrent() {
            if !busy, try await isNoOp(latest) {
                try await forget(latest.id)
                continue
            }
            try await restore(latest)
            return latest
        }
        return nil
    }

    func operationInProgress() async throws -> Bool {
        let gitDir = try await resolve().gitDir
        return ["MERGE_HEAD", "rebase-merge", "rebase-apply", "CHERRY_PICK_HEAD", "REVERT_HEAD"].contains {
            FileManager.default.fileExists(atPath: gitDir.appending(path: $0).path(percentEncoded: false))
        }
    }

    func isNoOp(_ entry: UndoEntry) async throws -> Bool {
        let refs = trackedRefs(entry)
        guard !refs.isEmpty, !Self.refDeletingKinds.contains(entry.kind) else { return false }
        for ref in refs {
            let start = before(ref, in: entry)
            let after = if let recorded = entry.refsAfter { recorded[ref] ?? Self.absent } else { try await reflogAfter(ref, before: start, since: entry.date, kind: entry.kind) }
            if after != start { return false }
            if try await currentValue(of: ref) != start { return false }
        }
        return true
    }

    public func restore(_ entry: UndoEntry) async throws {
        guard let stored = try await loadCurrent().first(where: { $0.id == entry.id }) else { throw GitError(.undoNoLongerApplies) }
        try await apply(stored)
        try await forget(stored.id)
    }

    public func refNames(of id: UUID) async throws -> [String] {
        let output = try await git.run(.read(["for-each-ref", "--format=%(refname)", Self.refNamespace + id.uuidString + "/"]), background: true).output
        return output.split(separator: "\n").map(String.init)
    }

    func deleteRefs(of id: UUID) async throws {
        let refs = try await refNames(of: id)
        guard !refs.isEmpty else { return }
        let script = refs.map { "delete " + $0 + "\n" }.joined()
        try await git.run(.write(["update-ref", "--stdin"], stdin: Data(script.utf8)), background: true)
    }

    public func storeBlob(_ data: Data) async throws -> OID {
        let output = try await git.run(.write(["hash-object", "-w", "--stdin"], stdin: data), background: true).output
        guard let oid = OID(output.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw GitError(.unknown(exit: 0, stderr: output)) }
        return oid
    }

    public func snapshotFiles(_ paths: [String]) async throws -> [String: OID] {
        try await hashWorktree(paths, write: true)
    }

    func hashWorktree(_ paths: [String], write: Bool) async throws -> [String: OID] {
        let root = try await worktreeRoot()
        let fileManager = FileManager.default
        var out: [String: OID] = [:]
        var regular: [String] = []
        for path in paths {
            let full = root.appending(path: path).path(percentEncoded: false)
            guard let attributes = try? fileManager.attributesOfItem(atPath: full) else {
                out[path] = Self.absent
                continue
            }
            switch attributes[.type] as? FileAttributeType {
            case .typeSymbolicLink?:
                let target = try fileManager.destinationOfSymbolicLink(atPath: full)
                out[path] = try await hashData(Data(target.utf8), write: write)
            case .typeDirectory?:
                continue
            default:
                regular.append(path)
            }
        }
        if !regular.isEmpty {
            var arguments = ["hash-object"]
            if write { arguments.append("-w") }
            arguments += ["--no-filters", "--"] + regular
            let command = write ? GitCommand.write(arguments) : GitCommand.read(arguments)
            let lines = try await git.run(command, background: true).output.split(separator: "\n")
            for (path, line) in zip(regular, lines) {
                if let oid = OID(String(line)) { out[path] = oid }
            }
        }
        return out
    }

    func hashData(_ data: Data, write: Bool) async throws -> OID {
        let arguments = write ? ["hash-object", "-w", "--stdin"] : ["hash-object", "--stdin"]
        var command = write ? GitCommand.write(arguments) : GitCommand.read(arguments)
        command.stdin = data
        let output = try await git.run(command, background: true).output
        guard let oid = OID(output.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw GitError(.unknown(exit: 0, stderr: output)) }
        return oid
    }

    struct Target {
        var oid: OID
        var mode: String
        var name: String
    }

    func protect(_ entry: UndoEntry) async throws {
        var targets: [Target] = []
        func add(_ oid: OID?, mode: String = "100644", name: String = "object") {
            guard let oid, !oid.isZero, !targets.contains(where: { $0.oid == oid }) else { return }
            targets.append(Target(oid: oid, mode: mode, name: name))
        }
        for key in entry.refsBefore.keys.sorted() { add(entry.refsBefore[key]) }
        for oid in entry.objects { add(oid) }
        let root = try await worktreeRoot()
        for path in entry.files.keys.sorted() {
            let name = path.split(separator: "/").last.map(String.init) ?? "file"
            add(entry.files[path], mode: Self.mode(of: root.appending(path: path)), name: name.isEmpty ? "file" : name)
        }
        add(entry.stashCommit)
        add(entry.patch, name: "patch")
        guard !targets.isEmpty else { return }
        let types = try await objectTypes(targets.map(\.oid))
        var script = ""
        for (index, target) in targets.enumerated() {
            let protected: OID
            switch types[target.oid] {
            case "commit", "tag":
                protected = target.oid
            case "tree":
                protected = try await wrap(tree: target.oid, label: entry.label)
            case "blob":
                let tree = try await makeTree(blob: target.oid, mode: target.mode, name: target.name)
                protected = try await wrap(tree: tree, label: entry.label)
            default:
                throw GitError(.unknown(exit: 0, stderr: "missing object " + target.oid.rawValue))
            }
            script += "create " + Self.refNamespace + entry.id.uuidString + "/" + String(index) + " " + protected.rawValue + "\n"
        }
        try await git.run(.write(["update-ref", "--stdin"], stdin: Data(script.utf8)), background: true)
    }

    static func mode(of url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)) else { return "100644" }
        if attributes[.type] as? FileAttributeType == .typeSymbolicLink { return "120000" }
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
        return permissions & 0o100 != 0 ? "100755" : "100644"
    }

    func objectTypes(_ oids: [OID]) async throws -> [OID: String] {
        let input = oids.map { $0.rawValue + "\n" }.joined()
        var command = GitCommand.read(["cat-file", "--batch-check=%(objectname) %(objecttype)"])
        command.stdin = Data(input.utf8)
        let output = try await git.run(command, background: true).output
        var types: [OID: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ")
            if parts.count == 2, let oid = OID(String(parts[0])) { types[oid] = String(parts[1]) }
        }
        return types
    }

    func makeTree(blob: OID, mode: String, name: String) async throws -> OID {
        var input = Data((mode + " blob " + blob.rawValue + "\t").utf8)
        input.append(Data(name.utf8))
        input.append(0)
        let output = try await git.run(.write(["mktree", "-z"], stdin: input), background: true).output
        guard let oid = OID(output.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw GitError(.unknown(exit: 0, stderr: output)) }
        return oid
    }

    func wrap(tree: OID, label: String) async throws -> OID {
        var command = GitCommand.write(["commit-tree", "--no-gpg-sign", "-m", "Vrai undo: " + label, tree.rawValue])
        command.environment = Self.identity
        let output = try await git.run(command, background: true).output
        guard let oid = OID(output.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw GitError(.unknown(exit: 0, stderr: output)) }
        return oid
    }

    func trackedRefs(_ entry: UndoEntry) -> [String] {
        guard Self.refMovingKinds.contains(entry.kind) || !entry.refsBefore.isEmpty && !Self.refDeletingKinds.contains(entry.kind) else { return [] }
        var refs = Set(entry.refsBefore.keys)
        if Self.refMovingKinds.contains(entry.kind), let head = entry.head {
            if head.hasPrefix("refs/") { refs.insert(head) } else if OID(head) != nil { refs.insert("HEAD") }
        }
        return refs.sorted()
    }

    func before(_ ref: String, in entry: UndoEntry) -> OID {
        if let value = entry.refsBefore[ref] { return value }
        if ref == "HEAD", let head = entry.head, let oid = OID(head) { return oid }
        return Self.absent
    }

    func currentValue(of ref: String) async throws -> OID {
        let result = try await git.run(.read(["rev-parse", "-q", "--verify", ref], acceptedExitCodes: [0, 1]), background: true)
        return OID(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? Self.absent
    }
}
