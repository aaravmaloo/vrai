import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@Suite(.enabled(if: Sandbox.available, "run Scripts/make-fixtures.sh first"))
struct EditorHelperTests {
    struct Folder {
        let url = Sandbox.root.appending(path: "scratch/editor-" + UUID().uuidString, directoryHint: .isDirectory)

        init() throws {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        func write(_ name: String, _ text: String) throws -> URL {
            let file = url.appending(path: name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
            return file
        }

        func read(_ file: URL) throws -> String {
            try String(contentsOf: file, encoding: .utf8)
        }

        func remove() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func run(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(filePath: try #require(EditorBuild.path))
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    static func messages(_ entries: [EditorMessage]) throws -> String {
        String(decoding: try JSONEncoder().encode(entries), as: UTF8.self)
    }

    @Test func helperBuildsFromItsSource() {
        #expect(EditorBuild.path != nil)
    }

    @Test func todoReplacesGitsList() throws {
        let folder = try Folder()
        defer { folder.remove() }
        let prepared = try folder.write("vrai/todo", "pick 1111111 # one\ndrop 2222222 # two\n")
        let target = try folder.write(".git/rebase-merge/git-rebase-todo", "pick 2222222 # two\npick 1111111 # one\n")
        #expect(try Self.run(["--todo", prepared.path(percentEncoded: false), target.path(percentEncoded: false)]) == 0)
        #expect(try folder.read(target) == "pick 1111111 # one\ndrop 2222222 # two\n")
        #expect(try Self.run(["--todo", folder.url.appending(path: "missing").path(percentEncoded: false), target.path(percentEncoded: false)]) == 1)
    }

    @Test func messagesFollowTheStepGitIsOn() throws {
        let folder = try Folder()
        defer { folder.remove() }
        let one = String(repeating: "1", count: 40)
        let two = String(repeating: "2", count: 40)
        let three = String(repeating: "3", count: 40)
        let prepared = try folder.write("vrai/messages.json", try Self.messages([
            EditorMessage(commit: three, message: "Three, squashed"),
            EditorMessage(commit: two, message: "Two, reworded\n\nWith a body.")
        ]))
        let done = try folder.write(".git/rebase-merge/done", "pick \(one) # one\nreword \(two) # two\n")
        let target = try folder.write(".git/COMMIT_EDITMSG", "two\n\n# Please enter the commit message\n")
        #expect(try Self.run(["--messages", prepared.path(percentEncoded: false), target.path(percentEncoded: false)]) == 0)
        #expect(try folder.read(target) == "Two, reworded\n\nWith a body.\n")

        try Data("pick \(one) # one\nreword \(two) # two\npick \(String(repeating: "4", count: 40)) # four\n".utf8).write(to: done)
        let untouched = try folder.write(".git/COMMIT_EDITMSG", "four\n")
        #expect(try Self.run(["--messages", prepared.path(percentEncoded: false), untouched.path(percentEncoded: false)]) == 0)
        #expect(try folder.read(untouched) == "four\n")

        try Data("squash \(String(three.prefix(7))) # three\n".utf8).write(to: done)
        #expect(try Self.run(["--messages", prepared.path(percentEncoded: false), untouched.path(percentEncoded: false)]) == 0)
        #expect(try folder.read(untouched) == "Three, squashed\n")
    }

    @Test func messagesGoInOrderOutsideARebase() throws {
        let folder = try Folder()
        defer { folder.remove() }
        let prepared = try folder.write("vrai/messages.json", try Self.messages([
            EditorMessage(commit: nil, message: "First"),
            EditorMessage(commit: nil, message: "Second")
        ]))
        let target = try folder.write("COMMIT_EDITMSG", "original\n")
        let arguments = ["--messages", prepared.path(percentEncoded: false), target.path(percentEncoded: false)]
        #expect(try Self.run(arguments) == 0)
        #expect(try folder.read(target) == "First\n")
        #expect(try Self.run(arguments) == 0)
        #expect(try folder.read(target) == "Second\n")
        #expect(try Self.run(arguments) == 0)
        #expect(try folder.read(target) == "Second\n")
        #expect(try Self.run([target.path(percentEncoded: false)]) == 0)
    }
}
