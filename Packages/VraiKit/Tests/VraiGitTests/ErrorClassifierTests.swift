import Foundation
import Testing
@testable import VraiGit

struct ErrorClassifierTests {
    static func result(_ name: String) throws -> GitResult {
        let metaLines = try String(contentsOf: Recorded.directory.appending(path: "errors/\(name).meta"), encoding: .utf8).split(separator: "\n")
        let exit = Int32(metaLines.first ?? "1") ?? 1
        let arguments = metaLines.count > 1 ? metaLines[1].split(separator: " ").map(String.init) : []
        let stderr = try Data(contentsOf: Recorded.directory.appending(path: "errors/\(name).err"))
        let stdout = try Data(contentsOf: Recorded.directory.appending(path: "errors/\(name).out"))
        return GitResult(command: GitCommand(arguments), exitCode: exit, stdout: stdout, stderr: stderr, startedAt: Date(), duration: .zero)
    }

    @Test(arguments: [
        ("offline-fetch", "networkUnreachable"),
        ("push-rejected", "pushRejected"),
        ("unknown-revision", "refNotFound"),
        ("branch-exists", "refExists"),
        ("invalid-branch-name", "invalidRefName"),
        ("not-fully-merged", "branchNotMerged"),
        ("checked-out-elsewhere", "branchCheckedOutElsewhere"),
        ("local-changes", "localChangesWouldBeOverwritten"),
        ("not-a-repository", "notARepository"),
        ("nothing-to-stash", "nothingToStash")
    ])
    func recordedFailuresMapToCodes(name: String, expected: String) throws {
        let result = try Self.result(name)
        #expect(ErrorClassifier.code(for: result).name == expected)
    }

    @Test func detailsAreParsed() throws {
        if case .networkUnreachable(let host) = ErrorClassifier.code(for: try Self.result("offline-fetch")) {
            #expect(host == "127.0.0.1")
        } else {
            Issue.record("expected networkUnreachable")
        }
        if case .branchCheckedOutElsewhere(let path) = ErrorClassifier.code(for: try Self.result("checked-out-elsewhere")) {
            #expect(path == "/SANDBOX/fixtures/everyday/vrai-release")
        }
        if case .localChangesWouldBeOverwritten(let paths) = ErrorClassifier.code(for: try Self.result("local-changes")) {
            #expect(paths.contains("Sources/VraiGit/Graph/LaneLayout.swift"))
        } else {
            Issue.record("expected localChangesWouldBeOverwritten")
        }
    }

    @Test func authFailureFromTheAuthServer() {
        let stderr = "remote: Credentials expired or revoked.\nfatal: Authentication failed for 'http://127.0.0.1:47801/vrai.git/'\n"
        let result = GitResult(command: GitCommand(["fetch", "origin"]), exitCode: 128, stdout: Data(), stderr: Data(stderr.utf8), startedAt: Date(), duration: .zero)
        #expect(ErrorClassifier.code(for: result) == .authFailed(host: "127.0.0.1"))
        let ssh = GitResult(command: GitCommand(["fetch"]), exitCode: 128, stdout: Data(), stderr: Data("git@github.com: Permission denied (publickey).\nfatal: Could not read from remote repository.\n".utf8), startedAt: Date(), duration: .zero)
        #expect(ErrorClassifier.code(for: ssh) == .authFailed(host: "github.com"))
    }

    @Test func lockAndConflicts() {
        let lock = GitResult(command: GitCommand(["add", "x"]), exitCode: 128, stdout: Data(), stderr: Data("fatal: Unable to create '/repo/.git/index.lock': File exists.\n".utf8), startedAt: Date(), duration: .zero)
        #expect(ErrorClassifier.code(for: lock) == .lockFileExists(path: "/repo/.git/index.lock"))
        let merge = GitResult(command: GitCommand(["merge", "x"]), exitCode: 1, stdout: Data("Auto-merging a.txt\nCONFLICT (content): Merge conflict in a.txt\nCONFLICT (content): Merge conflict in dir/b c.txt\nAutomatic merge failed; fix conflicts and then commit the result.\n".utf8), stderr: Data(), startedAt: Date(), duration: .zero)
        #expect(ErrorClassifier.code(for: merge) == .conflicts(paths: ["a.txt", "dir/b c.txt"]))
    }
}
