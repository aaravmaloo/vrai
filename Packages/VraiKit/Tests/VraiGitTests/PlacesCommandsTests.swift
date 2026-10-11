import Foundation
import Testing
@testable import VraiGit

struct PlacesCommandsTests {
    static let a = String(repeating: "a", count: 40)
    static let b = String(repeating: "b", count: 40)
    static let c = String(repeating: "c", count: 40)

    @Test func worktreeCommands() {
        #expect(PlacesCommands.addWorktree(path: "/tmp/vrai fix", branch: "fix/sync", createBranch: true).display == "git worktree add -b fix/sync -- \"/tmp/vrai fix\"")
        #expect(PlacesCommands.addWorktree(path: "/tmp/w", branch: "fix/sync", createBranch: true, startPoint: "main").arguments == ["worktree", "add", "-b", "fix/sync", "--", "/tmp/w", "main"])
        #expect(PlacesCommands.addWorktree(path: "/tmp/w", branch: "fix/sync", createBranch: true, startPoint: "HEAD").arguments == ["worktree", "add", "-b", "fix/sync", "--", "/tmp/w"])
        #expect(PlacesCommands.addWorktree(path: "/tmp/w", branch: "release/0.9", createBranch: false).arguments == ["worktree", "add", "--", "/tmp/w", "release/0.9"])
        #expect(PlacesCommands.removeWorktree(path: "/tmp/w", force: false).risk == .safe)
        #expect(PlacesCommands.removeWorktree(path: "/tmp/w", force: true).display == "git worktree remove --force -- /tmp/w")
        #expect(PlacesCommands.removeWorktree(path: "/tmp/w", force: true).risk == .destructive)
        #expect(PlacesCommands.lockWorktree(path: "/tmp/w", reason: nil).display == "git worktree lock -- /tmp/w")
        #expect(PlacesCommands.lockWorktree(path: "/tmp/w", reason: "USB drive").display == "git worktree lock --reason \"USB drive\" -- /tmp/w")
        #expect(PlacesCommands.unlockWorktree(path: "/tmp/w").display == "git worktree unlock -- /tmp/w")
        #expect(PlacesCommands.pruneWorktrees().display == "git worktree prune --verbose")
        #expect(PlacesCommands.pruneWorktrees().access == .write)
    }

    @Test func submoduleCommands() {
        #expect(PlacesCommands.submodule(path: "Vendor/x", action: .initUpdate).display == "git submodule update --init --recursive --progress -- Vendor/x")
        #expect(PlacesCommands.submodule(path: "Vendor/x", action: .update).display == "git submodule update --recursive --progress -- Vendor/x")
        #expect(PlacesCommands.submodule(path: "Vendor/x", action: .updateRemote).display == "git submodule update --init --remote --merge --progress -- Vendor/x")
        #expect(PlacesCommands.submodule(path: "Vendor/x", action: .sync).display == "git submodule sync --recursive -- Vendor/x")
        #expect(PlacesCommands.submodule(path: nil, action: .sync).display == "git submodule sync --recursive")
        #expect(PlacesCommands.submodule(path: "Vendor/x", action: .record).display == "git add -- Vendor/x")
        #expect(PlacesCommands.submodule(path: "Vendor/x", action: .deinit).display == "git submodule deinit -f -- Vendor/x")
        #expect(PlacesCommands.submodule(path: "Vendor/x", action: .deinit).risk == .destructive)
        #expect(PlacesCommands.addSubmodule(url: "https://example.com/x.git", path: "Vendor/x").display == "git submodule add --progress -- https://example.com/x.git Vendor/x")
        #expect(PlacesCommands.addSubmodule(url: "git@example.com:x.git", path: "Vendor/x", branch: "main").arguments == ["submodule", "add", "--progress", "-b", "main", "--", "git@example.com:x.git", "Vendor/x"])
    }

    @Test func readCommands() {
        #expect(PlacesCommands.reflog().display == "git reflog show -z --date=unix --format=%H%x00%gd%x00%gs%x00%ct -n 500 HEAD --")
        #expect(PlacesCommands.restoreReflog("HEAD@{3}").display == "git reset --keep HEAD@{3}")
        #expect(PlacesCommands.restoreReflog("HEAD@{3}").risk == .rewrites)
        #expect(PlacesCommands.blame(path: "README.md", at: "HEAD").arguments == ["blame", "--porcelain", "HEAD", "--", "README.md"])
        #expect(PlacesCommands.showFile(path: "Docs/a b.md", at: Self.a).arguments == ["show", Self.a + ":Docs/a b.md"])
        #expect(PlacesCommands.fileHistory(path: "README.md").arguments.contains("--follow"))
        #expect(PlacesCommands.fileHistory(path: "README.md").arguments.suffix(2) == ["--", "README.md"])
        #expect(PlacesCommands.removeReplacement(Self.a).display == "git replace -d \(Self.a)")
        #expect(PlacesCommands.pseudoRef("ORIG_HEAD").acceptedExitCodes == [0, 1])
    }

    @Test func reflogUsesTheEntryTimeAndItsPosition() {
        let data = Data("\(Self.a)\u{0}HEAD@{1791747074}\u{0}commit: One\u{0}1791712800\u{0}\(Self.b)\u{0}HEAD@{1791740000}\u{0}\u{0}1791500000\u{0}".utf8)
        let entries = ReflogParser.parse(data)
        #expect(entries.map(\.selector) == ["HEAD@{0}", "HEAD@{1}"])
        #expect(entries[0].date == Date(timeIntervalSince1970: 1_791_747_074))
        #expect(entries[1].message.isEmpty)
        let branch = ReflogParser.parse(Data("\(Self.a)\u{0}feature/x@{1791747074}\u{0}branch: Created\u{0}1\u{0}".utf8))
        #expect(branch.first?.selector == "feature/x@{0}")
        let indexed = ReflogParser.parse(Data("\(Self.a)\u{0}HEAD@{0}\u{0}reset\u{0}1791712800\u{0}".utf8))
        #expect(indexed.first?.date == Date(timeIntervalSince1970: 1_791_712_800))
    }

    @Test func fileHistoryParsesRenamesAndStats() {
        func record(_ id: String, _ parent: String, _ subject: String, _ files: [String]) -> String {
            "\u{1E}" + [id, parent, "Avery Chen", "avery@vrai.app", "1791712800", "Avery Chen", "avery@vrai.app", "1791712800", subject, ""].joined(separator: "\u{0}") + "\u{0}\u{0}\n" + files.joined(separator: "\u{0}") + "\u{0}"
        }
        let text = record(Self.a, Self.b, "Rename lanes", [":100644 100644 1111111 2222222 R087", "Old/Lane.swift", "New/Lane.swift", "3\t1\t", "Old/Lane.swift", "New/Lane.swift"])
            + record(Self.b, Self.c, "Tune lanes", [":100644 100644 3333333 1111111 M", "Old/Lane.swift", "8\t2\tOld/Lane.swift"])
            + record(Self.c, "", "Add lanes", [":000000 100644 0000000 3333333 A", "Old/Lane.swift", "72\t0\tOld/Lane.swift"])
        let entries = FileHistoryParser.parse(Data(text.utf8), path: "New/Lane.swift")
        #expect(entries.map(\.commit.subject) == ["Rename lanes", "Tune lanes", "Add lanes"])
        #expect(entries[0].file.status == .renamed)
        #expect(entries[0].file.path == "New/Lane.swift")
        #expect(entries[0].file.oldPath == "Old/Lane.swift")
        #expect(entries[0].file.additions == 3)
        #expect(entries[1].file.path == "Old/Lane.swift")
        #expect(entries[1].file.additions == 8)
        #expect(entries[1].file.deletions == 2)
        #expect(entries[2].file.status == .added)
        #expect(entries[2].commit.parents.isEmpty)
        #expect(FileHistoryParser.parse(Data(), path: "x").isEmpty)
    }

    @Test func refListKindsAndNamespaces() {
        let text = [
            "refs/heads/main\u{0}\(Self.a)\u{0}commit\u{0}\u{0}\u{0}",
            "refs/remotes/origin/HEAD\u{0}\(Self.a)\u{0}commit\u{0}refs/remotes/origin/main\u{0}\u{0}",
            "refs/tags/v1\u{0}\(Self.b)\u{0}tag\u{0}\u{0}\(Self.c)\u{0}",
            "refs/tags/v0\u{0}\(Self.a)\u{0}commit\u{0}\u{0}\u{0}",
            "refs/stash\u{0}\(Self.c)\u{0}commit\u{0}\u{0}\u{0}",
            "refs/notes/commits\u{0}\(Self.c)\u{0}commit\u{0}\u{0}\u{0}",
            "refs/replace/\(Self.a)\u{0}\(Self.b)\u{0}commit\u{0}\u{0}\u{0}",
            "refs/vrai/undo/X/0\u{0}\(Self.b)\u{0}commit\u{0}\u{0}\u{0}",
            "refs/bisect/bad\u{0}\(Self.b)\u{0}commit\u{0}\u{0}\u{0}",
            "refs/custom/thing\u{0}\(Self.b)\u{0}commit\u{0}\u{0}\u{0}"
        ].joined(separator: "\n") + "\n"
        let refs = RefListParser.parse(Data(text.utf8))
        #expect(refs.map(\.kind) == [.branch, .symbolic, .annotatedTag, .tag, .stash, .notes, .replace, .undo, .bisect, .other])
        #expect(refs[1].symbolicTarget == "refs/remotes/origin/main")
        #expect(refs[0].namespace == "refs/heads")
        #expect(refs[4].namespace == "refs/stash")
        #expect(refs[6].replacedObject == Self.a)
        #expect(refs[0].replacedObject == nil)
        #expect(refs[2].peeled?.rawValue == Self.c)
        #expect(refs[2].commit?.rawValue == Self.c)
        #expect(refs[3].commit?.rawValue == Self.a)
    }
}
