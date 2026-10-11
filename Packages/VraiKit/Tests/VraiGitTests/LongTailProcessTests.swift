import Foundation
import Testing
@testable import VraiGit

struct LongTailProcessTests {
    @Test func stdinThatGitNeverReadsDoesNotKillTheApp() async throws {
        let directory = FileManager.default.temporaryDirectory
        let git = GitProcess(executable: try GitExecutable.discover(), workingDirectory: directory, environment: .user())
        let payload = Data(repeating: 0x61, count: 4 * 1024 * 1024)
        for _ in 0..<3 {
            let result = try await git.run(GitCommand(["version"], stdin: payload))
            #expect(result.output.hasPrefix("git version"))
        }
    }
}
