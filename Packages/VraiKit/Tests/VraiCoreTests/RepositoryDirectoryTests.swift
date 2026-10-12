import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

struct RepositoryOwnerTests {
    @Test(arguments: [
        ("git@github.com:Cefense/vrai.git", "Cefense"),
        ("git@github.com:aaravmaloo/apm", "aaravmaloo"),
        ("https://github.com/aaravmaloo/apm", "aaravmaloo"),
        ("https://github.com/aaravmaloo/apm.git", "aaravmaloo"),
        ("https://github.com/apms-org/site/", "apms-org"),
        ("https://user:token@github.com/apms-org/site.git", "apms-org"),
        ("http://git.example.com:8080/team/tool.git", "team"),
        ("ssh://git@github.com/Cefense/vrai", "Cefense"),
        ("ssh://git@github.com:22/Cefense/vrai.git", "Cefense"),
        ("git@host.example:~alice/notes.git", "alice")
    ])
    func parsesTheOwnerFromEachURLForm(remote: String, owner: String) {
        #expect(RepositoryOwner.parse(remote) == owner)
    }

    @Test func nestedGitLabGroupsUseTheFirstPathSegment() {
        #expect(RepositoryOwner.parse("https://gitlab.com/apms-org/backend/payments.git") == "apms-org")
        #expect(RepositoryOwner.parse("git@gitlab.com:apms-org/backend/tools/cli.git") == "apms-org")
        #expect(RepositoryOwner.parse("ssh://git@gitlab.com/apms-org/backend/payments") == "apms-org")
    }

    @Test(arguments: [
        "file:///Users/me/remotes/origin.git",
        "file://localhost/Users/me/remotes/origin.git",
        "/Users/me/remotes/origin.git",
        "../origin.git",
        "~/remotes/origin.git",
        "https://example.com/solo.git",
        "git@example.com:solo.git",
        "not a url",
        ""
    ])
    func localOrOwnerlessRemotesHaveNoOwner(remote: String) {
        #expect(RepositoryOwner.parse(remote) == nil)
    }

    @Test func missingRemoteHasNoOwner() {
        #expect(RepositoryOwner.parse(nil) == nil)
    }
}

struct RepositoryDirectoryTests {
    static let base = Date(timeIntervalSince1970: 1_791_720_000)

    static func recent(_ name: String, _ remote: String?, _ age: Double, folder: String = "/Users/me/Developer") -> RecentRepository {
        RecentRepository(path: folder + "/" + name, name: name, lastOpened: base.addingTimeInterval(-age * 60), remote: remote)
    }

    static let sample: [RecentRepository] = [
        recent("vrai", "git@github.com:Cefense/vrai.git", 0),
        recent("apm", "https://github.com/aaravmaloo/apm.git", 1),
        recent("site", "git@github.com:apms-org/site.git", 2),
        recent("notes", nil, 3),
        recent("Zeta", "https://github.com/cefense/Zeta", 4),
        recent("local", "file:///Users/me/remotes/local.git", 5),
        recent("alpha", "ssh://git@github.com/Cefense/alpha.git", 6),
        recent("beta", "git@gitlab.com:zed-org/apps/beta.git", 7)
    ]

    static func names(_ section: DirectorySection) -> [String] { section.entries.map(\.name) }

    @Test func groupsRecentFirstThenOwnersThenOther() {
        let sections = RepositoryDirectory.sections(Self.sample, current: "/Users/me/Developer/vrai")
        #expect(sections.map(\.kind) == [.recent, .owner("aaravmaloo"), .owner("apms-org"), .owner("Cefense"), .owner("zed-org"), .other])
        #expect(Self.names(sections[0]) == ["apm", "site", "notes"])
        #expect(Self.names(sections[3]) == ["alpha", "vrai", "Zeta"])
        #expect(Self.names(sections[5]) == ["local", "notes"])
        #expect(RepositoryDirectory.flatten(sections).count == 11)
    }

    @Test func recentFollowsLastOpenedNotListOrderAndSkipsTheCurrentRepository() {
        let shuffled = Array(Self.sample.reversed())
        let sections = RepositoryDirectory.sections(shuffled, current: "/Users/me/Developer/apm")
        #expect(sections.first?.kind == .recent)
        #expect(sections.first.map(Self.names) == ["vrai", "site", "notes"])
        let none = RepositoryDirectory.sections(Self.sample, current: nil)
        #expect(none.first.map(Self.names) == ["vrai", "apm", "site"])
    }

    @Test func ownersMergeCaseInsensitivelyAndSortCaseInsensitively() {
        let list = [
            Self.recent("one", "git@github.com:zulu/one.git", 0),
            Self.recent("two", "git@github.com:Alpha/two.git", 1),
            Self.recent("three", "git@github.com:alpha/three.git", 2),
            Self.recent("four", "git@github.com:beta/four.git", 3)
        ]
        let sections = RepositoryDirectory.sections(list, current: nil).filter { $0.kind != .recent }
        #expect(sections.map(\.kind) == [.owner("Alpha"), .owner("beta"), .owner("zulu")])
        #expect(Self.names(sections[0]) == ["three", "two"])
    }

    @Test func reposSortByNameWithNumbersInOrder() {
        let list = [
            Self.recent("repo10", "git@github.com:acme/repo10.git", 0),
            Self.recent("Repo2", "git@github.com:acme/repo2.git", 1),
            Self.recent("repo1", "git@github.com:acme/repo1.git", 2)
        ]
        let sections = RepositoryDirectory.sections(list, current: nil).filter { $0.kind != .recent }
        #expect(sections.map(Self.names) == [["repo1", "Repo2", "repo10"]])
    }

    @Test func emptyListHasNoSections() {
        #expect(RepositoryDirectory.sections([], current: nil).isEmpty)
    }

    @Test func currentRepositoryIndexPointsIntoItsOwnerGroup() {
        let sections = RepositoryDirectory.sections(Self.sample, current: "/Users/me/Developer/vrai")
        let index = RepositoryDirectory.index(of: "/Users/me/Developer/vrai", in: sections)
        #expect(index == 6)
        #expect(index.map { RepositoryDirectory.flatten(sections)[$0].name } == "vrai")
        #expect(RepositoryDirectory.index(of: "/Users/me/Developer/gone", in: sections) == nil)
        #expect(RepositoryDirectory.index(of: nil, in: sections) == nil)
    }
}

struct RepositoryFilterTests {
    static func recent(_ name: String, _ owner: String?, _ age: Double = 0) -> RecentRepository {
        RepositoryDirectoryTests.recent(name, owner.map { "git@github.com:\($0)/\(name).git" }, age)
    }

    @Test func filterHidesRecentAndRanksBestMatchesFirstWithinEachGroup() {
        let list = [
            Self.recent("vintage-rails", "Cefense", 0),
            Self.recent("old-vrai", "Cefense", 1),
            Self.recent("vrai-site", "Cefense", 2),
            Self.recent("vrai", "Cefense", 3),
            Self.recent("apm", "aaravmaloo", 4)
        ]
        let sections = RepositoryDirectory.sections(list, current: nil, query: "vrai")
        #expect(sections.map(\.kind) == [.owner("Cefense")])
        #expect(sections.first.map(RepositoryDirectoryTests.names) == ["vrai", "vrai-site", "old-vrai", "vintage-rails"])
    }

    @Test func matchesSubsequencesOfOwnerAndNameIgnoringCase() {
        let list = [
            Self.recent("vrai", "Cefense", 0),
            Self.recent("apm", "aaravmaloo", 1),
            Self.recent("scratch", nil, 2)
        ]
        let qualified = RepositoryDirectory.sections(list, current: nil, query: "cef/vr")
        #expect(RepositoryDirectory.flatten(qualified).map(\.name) == ["vrai"])
        let owner = RepositoryDirectory.sections(list, current: nil, query: "AARAV")
        #expect(RepositoryDirectory.flatten(owner).map(\.name) == ["apm"])
        let spaced = RepositoryDirectory.sections(list, current: nil, query: "  scr tch ")
        #expect(spaced.map(\.kind) == [.other])
        #expect(RepositoryDirectory.flatten(spaced).map(\.name) == ["scratch"])
        #expect(RepositoryDirectory.sections(list, current: nil, query: "zzz").isEmpty)
    }

    @Test func nameMatchesOutrankOwnerOnlyMatches() {
        let named = DirectoryEntry(path: "/a", name: "cefense-tools", owner: "someone", lastOpened: .now)
        let owned = DirectoryEntry(path: "/b", name: "vrai", owner: "Cefense", lastOpened: .now)
        #expect(RepositoryDirectory.score(named, "cefense") > RepositoryDirectory.score(owned, "cefense"))
        #expect(RepositoryDirectory.score(owned, "cefense") > 0)
        #expect(RepositoryDirectory.score(owned, "") == 1)
        #expect(RepositoryDirectory.score(owned, "xyz") == 0)
    }

    @Test func bestIndexFindsTheTopMatchAcrossGroups() {
        let list = [
            Self.recent("old-vrai-notes", "aaravmaloo", 0),
            Self.recent("vrai", "Cefense", 1)
        ]
        let sections = RepositoryDirectory.sections(list, current: nil, query: "vrai")
        #expect(sections.map(\.kind) == [.owner("aaravmaloo"), .owner("Cefense")])
        #expect(RepositoryDirectory.bestIndex(sections, query: "vrai") == 1)
        #expect(RepositoryDirectory.bestIndex([], query: "vrai") == nil)
    }
}

struct RecentsDecodingTests {
    @Test func decodesEntriesWrittenBeforeTheRemoteField() throws {
        let json = #"{"version":1,"repositories":[{"path":"/Users/me/Developer/vrai","name":"vrai","lastOpened":1791720000}]}"#
        let file = try JSONDecoder().decode(RecentsFile.self, from: Data(json.utf8))
        #expect(file.repositories.count == 1)
        #expect(file.repositories[0].remote == nil)
        #expect(file.repositories[0].lastOpened == Date(timeIntervalSince1970: 1_791_720_000))
    }

    @Test func decodesTheRemoteFieldWhenPresent() throws {
        let json = #"{"version":1,"repositories":[{"path":"/Users/me/Developer/vrai","lastOpened":1791720000,"remote":"git@github.com:Cefense/vrai.git"}]}"#
        let file = try JSONDecoder().decode(RecentsFile.self, from: Data(json.utf8))
        #expect(file.repositories[0].remote == "git@github.com:Cefense/vrai.git")
        #expect(file.repositories[0].name == "vrai")
    }

    @Test func encodesTheRemoteOnlyWhenKnown() throws {
        let plain = RecentRepository(path: "/Users/me/Developer/notes", name: "notes", lastOpened: Date(timeIntervalSince1970: 1_791_720_000))
        let linked = RecentRepository(path: "/Users/me/Developer/vrai", name: "vrai", lastOpened: Date(timeIntervalSince1970: 1_791_720_000), remote: "https://github.com/Cefense/vrai.git")
        let plainJSON = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!plainJSON.contains("remote"))
        let data = try JSONEncoder().encode(RecentsFile(repositories: [plain, linked]))
        let decoded = try JSONDecoder().decode(RecentsFile.self, from: data)
        #expect(decoded.repositories == [plain, linked])
    }
}

@MainActor
struct RecentsCapTests {
    static func makeApp() -> (app: AppModel, folder: URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vrai-recents-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (AppModel(launch: LaunchOptions(sandbox: folder)), folder)
    }

    @Test func keepsTheHundredMostRecentRepositories() throws {
        #expect(AppModel.maximumRecents == 100)
        let (app, folder) = Self.makeApp()
        defer { try? FileManager.default.removeItem(at: folder) }
        for index in 0..<120 {
            app.noteOpened(RepositoryReference(path: "/Users/me/Developer/repo\(index)"))
        }
        #expect(app.recents.count == 100)
        #expect(app.recents.first?.name == "repo119")
        #expect(app.recents.last?.name == "repo20")
        let reloaded = AppModel(launch: LaunchOptions(sandbox: folder))
        #expect(reloaded.recents.count == 100)
        #expect(reloaded.recents.map(\.path) == app.recents.map(\.path))
    }

    @Test func reopeningKeepsTheKnownRemote() throws {
        let (app, folder) = Self.makeApp()
        defer { try? FileManager.default.removeItem(at: folder) }
        let vrai = RepositoryReference(path: "/Users/me/Developer/vrai")
        app.noteOpened(vrai)
        app.noteOpened(RepositoryReference(path: "/Users/me/Developer/apm"))
        let probe = DirectoryProbe(path: vrai.path, status: RecentStatus(branch: "main", detached: false, changes: 2, ahead: 1, behind: 0, missing: false, empty: false), remote: "git@github.com:Cefense/vrai.git", remoteKnown: true)
        #expect(app.apply(probe))
        #expect(!app.apply(probe))
        #expect(app.directoryStatus[vrai.path]?.changes == 2)
        app.noteOpened(vrai)
        #expect(app.recents.first?.path == vrai.path)
        #expect(app.recents.first?.remote == "git@github.com:Cefense/vrai.git")
        let unknown = DirectoryProbe(path: vrai.path, status: .missingFolder, remote: nil, remoteKnown: false)
        #expect(!app.apply(unknown))
        #expect(app.recents.first?.remote == "git@github.com:Cefense/vrai.git")
        #expect(app.directoryStatus[vrai.path]?.missing == true)
    }
}

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct RepositoryDirectoryProbeTests {
    @Test func probesStatusAndOriginForEachRepository() async throws {
        let lab = try CloneLab.make()
        defer { lab.remove() }
        let repository = lab.copy.repository
        _ = try await lab.git(["remote", "set-url", "origin", "git@github.com:Cefense/vrai.git"], in: repository)
        let reference = RepositoryReference(url: repository)
        let gone = RepositoryReference(path: lab.copy.root.appending(path: "gone").path(percentEncoded: false))
        lab.app.noteOpened(gone)
        lab.app.noteOpened(reference)
        await lab.app.probeDirectory([reference.path, gone.path], width: 2)
        #expect(lab.app.recents.first { $0.path == reference.path }?.remote == "git@github.com:Cefense/vrai.git")
        #expect(lab.app.directoryStatus[reference.path]?.missing == false)
        #expect(lab.app.directoryStatus[gone.path]?.missing == true)
        let sections = RepositoryDirectory.sections(lab.app.recents, current: reference.path)
        #expect(sections.contains { $0.kind == .owner("Cefense") && $0.entries.map(\.path) == [reference.path] })
        let saved = try JSONDecoder().decode(RecentsFile.self, from: Data(contentsOf: try #require(lab.app.launch.recentsFile)))
        #expect(saved.repositories.first { $0.path == reference.path }?.remote == "git@github.com:Cefense/vrai.git")
        _ = try await lab.git(["remote", "remove", "origin"], in: repository)
        await lab.app.probeDirectory([reference.path])
        #expect(lab.app.recents.first { $0.path == reference.path }?.remote == nil)
    }
}
