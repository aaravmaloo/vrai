import Foundation
import Testing
@testable import VraiCore
@testable import VraiGit

@Suite(.serialized, .enabled(if: Sandbox.available && ProcessInfo.processInfo.environment["VRAI_PERF"] == "1", "run Scripts/perf.sh"))
struct PerformanceTests {
    static let reportURL = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "build/perf/engine.txt")

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

    static func time(runs: Int, isolation: isolated (any Actor)? = #isolation, _ body: () async throws -> Void) async throws -> [Duration] {
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

    @MainActor
    @Test func outsideCommitAppearsWithinASecond() async throws {
        let copy = try ReadSideTests.privateCopy("everyday")
        defer { try? FileManager.default.removeItem(at: copy) }
        let repository = copy.appending(path: "vrai", directoryHint: .isDirectory)
        let store = RepositoryStore(git: try Sandbox.git(at: repository))
        await store.open(watch: true)
        defer { store.close() }
        try await Task.sleep(for: .milliseconds(200))
        let outside = try Sandbox.git(at: repository)
        let clock = ContinuousClock()
        let start = clock.now
        try await outside.run(.write(["commit", "--allow-empty", "-m", "test"]))
        try await waitUntil(timeout: .seconds(5)) { store.history.commits.first?.subject == "test" }
        let elapsed = milliseconds(clock.now - start)
        Self.record(String(format: "outside commit to new history row (everyday): %.0f ms (budget 1000 ms)", elapsed))
        #expect(elapsed < 1000)
    }

    @Test(.enabled(if: Sandbox.has("large/monorepo")))
    func largeSnapshot() async throws {
        let git = try Sandbox.git("large/monorepo")
        let samples = try await Self.time(runs: 5) { _ = try await SnapshotBuilder(git: git).build() }
        Self.record(String(format: "snapshot large: median %.1f ms (5 warm runs, no budget in M1)", milliseconds(median(samples))))
    }

    static let table = "Sources/Generated/LexerTable.swift"

    @MainActor
    @Test(.enabled(if: Sandbox.has("large/monorepo")))
    func largeOpenToFirstPageAndStatus() async throws {
        let clock = ContinuousClock()
        var samples: [Duration] = []
        for run in 0..<4 {
            let store = RepositoryStore(git: try Sandbox.git("large/monorepo"))
            let start = clock.now
            await store.open(watch: false)
            let elapsed = clock.now - start
            #expect(store.snapshot != nil)
            #expect(store.history.commits.count == store.pageSize)
            store.close()
            if run > 0 { samples.append(elapsed) }
        }
        let value = milliseconds(median(samples))
        Self.record(String(format: "engine: open large to snapshot and first page: median %.1f ms (3 warm runs, budget 500 ms end to end)", value))
        #expect(value < 500)
    }

    @MainActor
    @Test(.enabled(if: Sandbox.has("large/monorepo")))
    func largeCommitDetailAndBigDiff() async throws {
        let store = RepositoryStore(git: try Sandbox.git("large/monorepo"))
        await store.open(watch: false)
        defer { store.close() }
        let head = try #require(store.snapshot?.headOID)
        let details = try await Self.time(runs: 7) { _ = try await store.commitDetail(id: head) }
        let detail = milliseconds(median(details))
        Self.record(String(format: "engine: commit detail on large: median %.1f ms (7 warm runs, budget 100 ms end to end)", detail))
        var lines = 0
        let diffs = try await Self.time(runs: 7) {
            let diff = try await store.diff(for: Self.table, in: head)
            lines = diff?.hunks.reduce(0) { $0 + $1.lines.count } ?? 0
        }
        #expect(lines == 5000)
        let diff = milliseconds(median(diffs))
        Self.record(String(format: "engine: diff of the 5,000-line file, read and parsed: median %.1f ms (7 warm runs, budget 100 ms end to end)", diff))
        #expect(detail < 100)
        #expect(diff < 100)
    }

    @MainActor
    @Test(.enabled(if: Sandbox.has("large/monorepo")))
    func largeStageAndUnstageAFile() async throws {
        let copy = try ReadSideTests.privateCopy("large")
        defer { try? FileManager.default.removeItem(at: copy) }
        let repository = copy.appending(path: "monorepo", directoryHint: .isDirectory)
        _ = try await Sandbox.git(at: repository).runAllowingFailure(.write(["update-index", "--refresh", "-q"]))
        let store = RepositoryStore(git: try Sandbox.git(at: repository))
        await store.open(watch: false)
        defer { store.close() }
        let path = "Sources/Module03/Area1/File04.swift"
        let clock = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0..<5 {
            let start = clock.now
            try await store.stage(paths: [path])
            samples.append(clock.now - start)
            #expect(store.snapshot?.working.first { $0.path == path }?.staged == .full)
            let again = clock.now
            try await store.unstage(paths: [path])
            samples.append(clock.now - again)
            #expect(store.snapshot?.working.first { $0.path == path }?.staged == StageState.none)
        }
        let value = milliseconds(median(samples))
        Self.record(String(format: "engine: stage or unstage a file on large, git and refresh: median %.1f ms (10 runs, budget 100 ms end to end)", value))
        #expect(value < 100)
    }

    @MainActor
    @Test func everydayStoreRefresh() async throws {
        let store = RepositoryStore(git: try Sandbox.git("everyday/vrai"))
        await store.open(watch: false)
        defer { store.close() }
        let samples = try await Self.time(runs: 9) { try await store.refresh() }
        let value = milliseconds(median(samples))
        Self.record(String(format: "engine: store refresh on everyday: median %.1f ms (9 warm runs, budget 150 ms end to end)", value))
        #expect(value < 150)
    }
}
