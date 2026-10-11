import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@MainActor
@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct RemoteStoreTests {
    @Test func addRemoteValidatesAndAdds() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let store = try await copy.store()
        let url = "file://" + copy.remote("mira").path(percentEncoded: false)
        let summary = try await store.addRemote(name: "friend", url: url)
        #expect(try await copy.config("remote.friend.url") == url)
        #expect(summary.message == "Added remote friend")
        #expect(summary.detail == url)
        #expect(store.snapshot?.remotes.contains { $0.name == "friend" } == true)
        let fetched = try await store.fetch(remote: "friend")
        #expect(fetched.newCommits["friend/spike/metal-graph"] != nil)

        let console = ConsoleRecorder()
        let watched = try await copy.store(observer: console.observer)
        await expectCode("invalidURL") { try await watched.addRemote(name: "broken", url: "not a url") }
        await expectCode("invalidURL") { try await watched.addRemote(name: "broken", url: "htps://example.com/x.git") }
        #expect(!console.entries.contains { $0.command.hasPrefix("git remote add") })
        await expectCode("refExists") { try await store.addRemote(name: "origin", url: "https://github.com/vrai-app/vrai.git") }
        await expectCode("invalidRefName") { try await store.addRemote(name: "bad name", url: "https://github.com/vrai-app/vrai.git") }
    }

    @Test func editRemoteRenamesAndRewritesURLs() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let store = try await copy.store()
        let console = ConsoleRecorder()
        let watched = try await copy.store(observer: console.observer)
        let summary = try await watched.editRemote(name: "mira", newName: "friend", fetchURL: "https://github.com/miraokafor/vrai.git", pushURL: "git@github.com:miraokafor/vrai.git", prune: true)
        #expect(summary.message == "Saved remote friend")
        #expect(try await copy.config("remote.friend.url") == "https://github.com/miraokafor/vrai.git")
        #expect(try await copy.config("remote.friend.pushurl") == "git@github.com:miraokafor/vrai.git")
        #expect(try await copy.config("remote.friend.prune") == "true")
        #expect(try await copy.config("remote.mira.url") == nil)
        #expect(try await copy.config("branch.mira/spike/metal-graph.remote") == "friend")
        #expect(try await copy.tip("refs/remotes/friend/spike/metal-graph") != nil)
        let commands = console.entries.filter { !$0.background }.map(\.command)
        #expect(commands == [
            "git remote rename mira friend",
            "git remote set-url friend https://github.com/miraokafor/vrai.git",
            "git remote set-url --push friend git@github.com:miraokafor/vrai.git",
            "git config remote.friend.prune true"
        ])

        try await store.editRemote(name: "friend", pushURL: "", prune: false)
        #expect(try await copy.config("remote.friend.pushurl") == nil)
        #expect(try await copy.config("remote.friend.prune") == "false")
        #expect(try await copy.config("remote.friend.url") == "https://github.com/miraokafor/vrai.git")
        let remote = store.snapshot?.remotes.first { $0.name == "friend" }
        #expect(remote?.pushURL == nil)
        #expect(remote?.prune == false)

        await expectCode("remoteNotFound") { try await store.editRemote(name: "nope", fetchURL: "https://example.com/x.git") }
        await expectCode("invalidURL") { try await store.editRemote(name: "friend", fetchURL: "not a url") }
        await expectCode("refExists") { try await store.editRemote(name: "friend", newName: "origin") }
    }

    @Test func removeRemote() async throws {
        let copy = try ScenarioCopy.make("everyday")
        defer { copy.remove() }
        let store = try await copy.store()
        let summary = try await store.removeRemote(name: "mira")
        #expect(summary.message == "Removed remote mira")
        #expect(try await copy.config("remote.mira.url") == nil)
        #expect(try await copy.tip("refs/remotes/mira/spike/metal-graph") == nil)
        #expect(store.snapshot?.remotes.map(\.name) == ["origin"])
        await expectCode("remoteNotFound") { try await store.removeRemote(name: "mira") }
    }
}

struct RemoteURLTests {
    @Test(arguments: [
        ("https://github.com/vrai-app/vrai.git", "github.com", "vrai-app/vrai"),
        ("http://127.0.0.1:47813/vrai.git", "127.0.0.1:47813", "vrai"),
        ("ssh://git@github.com:2222/vrai-app/vrai.git", "github.com:2222", "vrai-app/vrai"),
        ("git@github.com:miraokafor/vrai.git", "github.com", "miraokafor/vrai"),
        ("github.com:vrai-app/vrai", "github.com", "vrai-app/vrai"),
        ("file:///tmp/x/origin.git", "", "tmp/x/origin"),
        ("/Users/me/My Repos/vrai.git", "", "Users/me/My Repos/vrai"),
        ("../sibling.git", "", "../sibling")
    ])
    func validURLs(text: String, host: String, path: String) {
        let url = RemoteURL(text)
        #expect(url != nil)
        #expect((url?.hostAndPort ?? "") == host)
        #expect(url?.repositoryPath == path)
    }

    @Test(arguments: ["", "not a url", "htps://example.com/x.git", "https://exa mple.com/x", "https://", "github.com/vrai-app/vrai", "line\nbreak"])
    func invalidURLs(text: String) {
        #expect(RemoteURL(text) == nil)
    }

    @Test func displayNames() {
        #expect(RemoteURL("https://github.com/vrai-app/vrai.git")?.displayName == "github.com/vrai-app/vrai")
        #expect(listed(["origin"]) == "origin")
        #expect(listed(["mira", "origin"]) == "mira and origin")
        #expect(listed(["a", "b", "c"]) == "a, b and c")
    }
}
