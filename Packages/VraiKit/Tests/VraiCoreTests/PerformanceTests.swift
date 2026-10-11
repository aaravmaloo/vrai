import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@Suite(.serialized, .enabled(if: Sandbox.available && ProcessInfo.processInfo.environment["VRAI_PERF"] == "1", "run Scripts/perf.sh"))
struct PerformanceTests {
    static let reportURL = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "build/perf/budgets.txt")

    static func record(_ line: String) {
        print("PERF " + line)
        try? FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: reportURL) {
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            try? handle.close()
        } else {
            try? Data((line + "\n").utf8).write(to: reportURL)
        }
    }

    static func time(runs: Int, _ body: () async throws -> Void) async throws -> [Duration] {
        let clock = ContinuousClock()
        try await body()
        var samples: [Duration] = []
        for _ in 0..<runs {
            let start = clock.now
            try await body()
            samples.append(clock.now - start)
        }
        return samples
    }

    @Test func everydaySnapshotUnder150Milliseconds() async throws {
        let git = try Sandbox.git("everyday/vrai")
        let samples = try await Self.time(runs: 9) { _ = try await SnapshotBuilder(git: git).build() }
        let value = milliseconds(median(samples))
        Self.record(String(format: "snapshot everyday: median %.1f ms, min %.1f ms, max %.1f ms (9 warm runs, budget 150 ms)", value, milliseconds(samples.min()!), milliseconds(samples.max()!)))
        #expect(value < 150)
    }

    static func firstPage(_ git: GitProcess) async throws -> [Duration] {
        try await time(runs: 5) {
            let pager = HistoryPager(git: git)
            let page = try await pager.nextPage()
            #expect(page?.commits.count == 2000)
            await pager.cancel()
        }
    }

    @Test(.enabled(if: Sandbox.has("large/monorepo")))
    func largeFirstHistoryPage() async throws {
        let git = try Sandbox.git("large/monorepo")
        let value = milliseconds(median(try await Self.firstPage(git)))
        Self.record(String(format: "history large, first 2000 commits: median %.1f ms (5 warm runs, budget 300 ms)", value))
        #expect(value < 300)

        var environment = git.environment
        environment.base["GIT_CONFIG_COUNT"] = "1"
        environment.base["GIT_CONFIG_KEY_0"] = "core.commitGraph"
        environment.base["GIT_CONFIG_VALUE_0"] = "false"
        let withoutGraph = GitProcess(executable: git.executable, workingDirectory: git.workingDirectory, environment: environment)
        let slow = milliseconds(median(try await Self.firstPage(withoutGraph)))
        Self.record(String(format: "history large, first 2000 commits, commit-graph ignored: median %.1f ms (5 warm runs, for reference)", slow))
    }

    @Test(.enabled(if: Sandbox.has("large/monorepo")))
    func largeSnapshot() async throws {
        let git = try Sandbox.git("large/monorepo")
        let samples = try await Self.time(runs: 5) { _ = try await SnapshotBuilder(git: git).build() }
        Self.record(String(format: "snapshot large: median %.1f ms (5 warm runs, no budget in M1)", milliseconds(median(samples))))
    }
}
