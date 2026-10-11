import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
struct CloneLab {
    let copy: ScenarioCopy
    let home: URL
    let app: AppModel

    static func make() throws -> CloneLab {
        let copy = try ScenarioCopy.make("everyday")
        let home = copy.root.deletingLastPathComponent().appending(path: "app", directoryHint: .isDirectory)
        let fm = FileManager.default
        try fm.createDirectory(at: home.appending(path: "home", directoryHint: .isDirectory), withIntermediateDirectories: true)
        try fm.copyItem(at: Sandbox.root.appending(path: "gitconfig"), to: home.appending(path: "gitconfig"))
        let app = AppModel(launch: LaunchOptions(sandbox: home))
        return CloneLab(copy: copy, home: home, app: app)
    }

    var originURL: String { "file://" + copy.remote("origin").path(percentEncoded: false).trimmingSuffix("/") }

    func destination(_ name: String) -> URL {
        app.developerFolder.appending(path: name, directoryHint: .isDirectory)
    }

    func git(_ arguments: [String], in url: URL) async throws -> String {
        try await copy.git(arguments, in: url)
    }

    func remove() { copy.remove() }
}

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct CloneTests {
    @Test func cloneWithSubmodulesReportsProgressAndOpens() async throws {
        let lab = try CloneLab.make()
        defer { lab.remove() }
        let target = lab.destination("vrai-clone")
        let request = CloneRequest(url: lab.originURL, destination: target, branch: "main", recurseSubmodules: true)
        #expect(request.command.display.hasPrefix("git clone --progress --branch main --recurse-submodules -- file://"))
        let handle = lab.app.startClone(request)
        var events: [CloneProgress] = []
        for await event in handle.progress { events.append(event) }
        let reference = try await handle.value
        #expect(reference.path == target.path(percentEncoded: false).trimmingTrailingSlashes())
        #expect(events.first?.stage == .connecting)
        #expect(events.last?.stage == .finished)
        let receiving = events.filter { $0.stage == .receiving }
        #expect(!receiving.isEmpty)
        #expect(receiving.contains { $0.hasObjects && $0.fraction != nil })
        #expect(receiving.last?.fraction == 1)
        #expect(events.contains { $0.stage == .resolving || $0.stage == .checkingOut })
        let submodules = Set(events.compactMap(\.submodule))
        #expect(submodules.isSuperset(of: ["Vendor/libgit2", "Vendor/cmark-gfm", "Vendor/swift-argument-parser"]))
        let status = try await lab.git(["submodule", "status"], in: target)
        let lines = status.split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines.allSatisfy { !$0.hasPrefix("-") })
        #expect(try await lab.git(["rev-parse", "--abbrev-ref", "HEAD"], in: target) == "main")
        #expect(lab.app.recents.first?.path == reference.path)
        #expect(lab.app.wasRequested(reference))
    }

    @Test func clonePlanSignatureStreamsUntilFinished() async throws {
        let lab = try CloneLab.make()
        defer { lab.remove() }
        let target = lab.destination("shallow")
        var stages: [CloneProgress.Stage] = []
        for await event in lab.app.clone(url: lab.originURL, to: target, branch: "release/0.9", depth: 1, recurseSubmodules: false) { stages.append(event.stage) }
        #expect(stages.last == .finished)
        #expect(try await lab.git(["rev-parse", "--is-shallow-repository"], in: target) == "true")
        #expect(try await lab.git(["rev-list", "--count", "HEAD"], in: target) == "1")
        #expect(try await lab.git(["rev-parse", "--abbrev-ref", "HEAD"], in: target) == "release/0.9")
    }

    @Test func cancelStopsTheCloneAndLeavesNoFolder() async throws {
        let lab = try CloneLab.make()
        defer { lab.remove() }
        let target = lab.destination("cancelled")
        let handle = lab.app.startClone(CloneRequest(url: lab.originURL, destination: target))
        handle.cancel()
        await #expect(throws: GitError.self) { _ = try await handle.value }
        do {
            _ = try await handle.value
        } catch let error as GitError {
            #expect(error.code == .cancelled)
        }
        #expect(!FileManager.default.fileExists(atPath: target.path(percentEncoded: false)))
        #expect(lab.app.recents.isEmpty)
    }

    @Test func cloneIntoAnExistingFolderFailsWithPathExists() async throws {
        let lab = try CloneLab.make()
        defer { lab.remove() }
        let target = lab.destination("taken")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("keep\n".utf8).write(to: target.appending(path: "notes.txt"))
        let handle = lab.app.startClone(CloneRequest(url: lab.originURL, destination: target))
        do {
            _ = try await handle.value
            Issue.record("expected the clone to fail")
        } catch let error as GitError {
            #expect(error.code == .pathExists)
        }
        #expect(FileManager.default.fileExists(atPath: target.appending(path: "notes.txt").path(percentEncoded: false)))
    }

    @Test func bareMirrorAndPartialClones() async throws {
        let lab = try CloneLab.make()
        defer { lab.remove() }
        let bare = lab.destination("bare.git")
        _ = try await lab.app.startClone(CloneRequest(url: lab.originURL, destination: bare, bare: true)).value
        #expect(try await lab.git(["rev-parse", "--is-bare-repository"], in: bare) == "true")
        #expect(lab.app.recents.isEmpty)
        let mirror = lab.destination("mirror.git")
        _ = try await lab.app.startClone(CloneRequest(url: lab.originURL, destination: mirror, mirror: true)).value
        #expect(try await lab.git(["config", "--get", "remote.origin.mirror"], in: mirror) == "true")
        _ = try await lab.git(["config", "uploadpack.allowFilter", "true"], in: lab.copy.remote("origin"))
        let partial = lab.destination("partial")
        _ = try await lab.app.startClone(CloneRequest(url: lab.originURL, destination: partial, history: .blobless, recurseSubmodules: false)).value
        #expect(try await lab.git(["config", "--get", "remote.origin.partialclonefilter"], in: partial) == "blob:none")
    }

    @Test func branchPickerReadsRemoteAndBundleHeads() async throws {
        let lab = try CloneLab.make()
        defer { lab.remove() }
        let heads = try await lab.app.remoteHeads(url: lab.originURL)
        #expect(heads.defaultBranch == "main")
        #expect(heads.branches.first == "main")
        #expect(Set(heads.branches) == ["main", "feature/graph-renderer", "feature/line-staging", "release/0.9"])
        let store = try await lab.copy.store()
        let file = lab.app.desktopFolder.appending(path: "vrai.bundle")
        try await store.createBundle(refs: ["main", "release/0.9"], to: file)
        let bundled = try await lab.app.remoteHeads(url: file.path(percentEncoded: false))
        #expect(Set(bundled.branches) == ["main", "release/0.9"])
        let target = lab.destination("from-bundle")
        let request = CloneRequest(url: file.path(percentEncoded: false), destination: target, branch: "release/0.9", recurseSubmodules: false)
        #expect(request.isBundle)
        _ = try await lab.app.startClone(request).value
        #expect(try await lab.git(["rev-parse", "--abbrev-ref", "HEAD"], in: target) == "release/0.9")
    }

    @Test func scalarCloneMakesAnEnlistment() async throws {
        let lab = try CloneLab.make()
        defer { lab.remove() }
        let enlistment = lab.destination("large")
        let request = CloneRequest(url: lab.originURL, destination: enlistment, scalar: true, maintenance: false)
        #expect(request.command.display.hasPrefix("scalar clone --no-maintenance file://"))
        #expect(request.command.subcommand == "scalar")
        let reference = try await lab.app.startClone(request).value
        #expect(reference.path.hasSuffix("/large/src"))
        #expect(try await lab.git(["rev-parse", "--abbrev-ref", "HEAD"], in: request.repositoryURL) == "main")
        #expect(try await lab.git(["config", "--get", "core.sparseCheckout"], in: request.repositoryURL) == "true")
    }

    @Test func initCreatesARepositoryWithTemplate() async throws {
        let lab = try CloneLab.make()
        defer { lab.remove() }
        #expect(await lab.app.defaultBranchName() == "main")
        #expect(await lab.app.isValidBranchName("trunk"))
        #expect(!(await lab.app.isValidBranchName("bad..name")))
        let folder = lab.destination("pocket-notes")
        let reference = try await lab.app.initRepository(at: folder, initialBranch: "trunk", gitignoreTemplate: .swift, readme: true)
        #expect(reference.path == folder.path(percentEncoded: false).trimmingTrailingSlashes())
        #expect(try await lab.git(["symbolic-ref", "HEAD"], in: folder) == "refs/heads/trunk")
        let ignore = try String(contentsOf: folder.appending(path: ".gitignore"), encoding: .utf8)
        #expect(ignore == GitignoreTemplate.swift.contents)
        #expect(try String(contentsOf: folder.appending(path: "README.md"), encoding: .utf8) == "# pocket-notes\n")
        #expect(lab.app.recents.first?.path == reference.path)
        let status = await lab.app.recentStatus(at: folder)
        #expect(status.empty)
        #expect(status.changes == 2)
        #expect(lab.app.initCommand(at: folder, initialBranch: "trunk").display.hasPrefix("git init --initial-branch=trunk /"))
    }

    @Test func inspectFindsRootsAndOffersInit() async throws {
        let lab = try CloneLab.make()
        defer { lab.remove() }
        let inside = lab.copy.repository.appending(path: "Sources", directoryHint: .isDirectory)
        #expect(await lab.app.inspect(path: inside.path(percentEncoded: false)) == .repository(RepositoryReference(url: lab.copy.repository)))
        let plain = lab.app.developerFolder.appending(path: "plain", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        #expect(await lab.app.inspect(path: plain.path(percentEncoded: false)) == .notARepository(plain.standardizedFileURL))
        let gone = lab.app.developerFolder.appending(path: "gone", directoryHint: .isDirectory)
        #expect(await lab.app.inspect(path: gone.path(percentEncoded: false)) == .missing(gone.standardizedFileURL))
        #expect(await lab.app.inspect(path: "~/Developer/plain") == .notARepository(plain.standardizedFileURL))
    }

    @Test func recentStatusAndNearbyRepositories() async throws {
        let lab = try CloneLab.make()
        defer { lab.remove() }
        let status = await lab.app.recentStatus(at: lab.copy.repository)
        #expect(status.branch == "feature/graph-renderer")
        #expect(status.ahead == 2)
        #expect(status.behind == 1)
        #expect(status.changes > 0)
        #expect(!status.missing)
        #expect(await lab.app.recentStatus(at: lab.copy.root.appending(path: "nowhere")).missing)
        let detached = lab.copy.root.appending(path: "detached-at-tag", directoryHint: .isDirectory)
        _ = try await lab.git(["worktree", "add", "--detach", detached.path(percentEncoded: false), "v0.9.1"], in: lab.copy.repository)
        let looking = await lab.app.recentStatus(at: detached)
        #expect(looking.detached)
        #expect(looking.branch == nil)
        #expect(looking.tag == "v0.9.1")
        let found = await lab.app.nearbyRepositories(in: lab.copy.root)
        #expect(found.contains { $0.url.lastPathComponent == "vrai" && !$0.isWorktree })
        #expect(found.contains { $0.url.lastPathComponent == "vrai-release" && $0.isWorktree })
    }

    @Test func gitReferenceReadsTheManualPage() async throws {
        let lab = try CloneLab.make()
        defer { lab.remove() }
        #expect(lab.app.manualCommand(for: "bisect").display == "git help --man bisect")
        let page = try await lab.app.manual(for: "bisect")
        #expect(page.contains { line in line.contains { $0.style == .bold && $0.text.contains("NAME") } })
        #expect(page.contains { line in line.map(\.text).joined().contains("git-bisect") })
        #expect(AppModel.referenceCommands.count == 6)
    }

    @Test func cloneURLValidationAndNames() {
        #expect(AppModel.isCloneURL("git@github.com:vrai-app/vrai.git"))
        #expect(AppModel.isCloneURL("https://github.com/apple/swift-collections.git"))
        #expect(AppModel.isCloneURL("ssh://git@example.com/repo.git"))
        #expect(AppModel.isCloneURL("file:///tmp/origin.git"))
        #expect(AppModel.isCloneURL("~/Desktop/vrai.bundle"))
        #expect(!AppModel.isCloneURL("not a url"))
        #expect(!AppModel.isCloneURL("github.com"))
        #expect(AppModel.repositoryName(fromURL: "git@github.com:vrai-app/vrai.git") == "vrai")
        #expect(AppModel.repositoryName(fromURL: "https://github.com/apple/swift-collections.git/") == "swift-collections")
        #expect(AppModel.repositoryName(fromURL: "/Users/a/Desktop/vrai.bundle") == "vrai")
    }

    @Test func cloneProgressParserReadsGitLines() {
        var parser = CloneProgressParser(destination: "/tmp/vrai")
        #expect(parser.consume("Cloning into '/tmp/vrai'...")?.stage == .connecting)
        let receiving = parser.consume("Receiving objects:  45% (126/279), 1.20 MiB | 2.30 MiB/s")
        #expect(receiving?.stage == .receiving)
        #expect(receiving?.current == 126)
        #expect(receiving?.total == 279)
        #expect(receiving?.transferred == "1.20 MiB")
        #expect(receiving?.speed == "2.30 MiB/s")
        #expect(parser.consume("remote: Counting objects: 100% (279/279), done.")?.stage == .counting)
        #expect(parser.consume("Resolving deltas: 100% (30/30), done.")?.fraction == 1)
        #expect(parser.consume("Submodule 'Vendor/libgit2' (file:///r/libgit2.git) registered for path 'Vendor/libgit2'")?.stage == .submodules)
        let sub = parser.consume("Cloning into '/tmp/vrai/Vendor/libgit2'...")
        #expect(sub?.submodule == "Vendor/libgit2")
        #expect(parser.consume("Receiving objects: 100% (10/10), done.")?.submodule == "Vendor/libgit2")
        #expect(parser.submodules == ["Vendor/libgit2"])
        #expect(parser.consume("") == nil)
    }
}
