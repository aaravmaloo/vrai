import Foundation
import Testing
import VraiCore
import VraiGit
@testable import VraiUI

@MainActor
struct LongTailLogicTests {
    @Test func onboardingNamesTheProblem() {
        let missing = OnboardingView(problem: GitError(.gitNotFound))
        #expect(missing.title == "Vrai needs git")
        #expect(missing.message.contains("command line tools"))
        let old = OnboardingView(problem: GitError(.gitTooOld(found: GitVersion(2, 30), needed: GitVersion(2, 45))))
        #expect(old.title == "Git 2.30.0 is too old for Vrai")
        #expect(old.message.contains("2.45.0 or later"))
    }

    @Test func repositoryTilesKeepTheirColor() {
        let first = RepoRowView.lane(for: "vrai")
        #expect(first == RepoRowView.lane(for: "vrai"))
        #expect((0..<BranchColors.laneCount).contains(first))
        #expect(RepoRowView.branchLane("main") == 0)
        #expect(RepoRowView.branchLane("feature/graph-renderer") != 0)
    }

    @Test func archivePrefixesUseTheVersion() {
        #expect(ArchiveSheet.version("v0.9.1") == "0.9.1")
        #expect(ArchiveSheet.version("vnext") == "vnext")
        #expect(ArchiveSheet.version("release-3") == "release-3")
    }

    @Test func splitSuggestsASecondSubject() {
        #expect(SplitSheet.secondSubject("Graph: assign lane colors") == "Graph: assign lane colors (part 2)")
        #expect(SplitSheet.secondSubject("").isEmpty)
    }

    @Test func maintenanceResultsReadPlainly() {
        let saved = MaintenanceResult(task: .gc, before: 4_000_000, after: 3_000_000, packsBefore: 3, packsAfter: 1, looseBefore: 214, looseAfter: 0, output: "")
        let detail = LongTailActions.detail(saved)
        #expect(detail.contains("in 1 pack"))
        #expect(detail.contains("saved"))
        let kept = MaintenanceResult(task: .prune, before: 10, after: 10, packsBefore: 1, packsAfter: 1, looseBefore: 2, looseAfter: 2, output: "")
        #expect(LongTailActions.detail(kept) == "Objects younger than 2 weeks were kept.")
        for task in MaintenanceTask.allCases {
            #expect(!LongTailActions.busyTitle(task).isEmpty)
            #expect(!LongTailActions.doneTitle(task).isEmpty)
        }
    }

    @Test func longTailErrorsGetTheirOwnTitles() {
        let command = GitCommand.write(["am", "--3way", "--", "/tmp/0001.patch"])
        let result = GitResult(command: command, exitCode: 128, stdout: Data(), stderr: Data("error: patch failed: README.md:1\n".utf8), startedAt: Date(), duration: .zero)
        let copy = ErrorCopy(GitError(.unknown(exit: 128, stderr: "error: patch failed"), result: result))
        #expect(copy.title == "The patches didn't apply")
        #expect(copy.message.contains("patch failed"))
        #expect(ErrorCopy.longTail(GitError(.pathExists))?.title == "That folder already exists")
        #expect(ErrorCopy.longTail(GitError(.cancelled))?.title == "Stopped")
    }

    @Test func terminalsMapToBundleIdentifiers() {
        #expect(TerminalLauncher.bundleIdentifiers["Terminal"] == "com.apple.Terminal")
        #expect(TerminalLauncher.bundleIdentifiers["iTerm"] == "com.googlecode.iterm2")
        #expect(TerminalLauncher.bundleIdentifiers["Ghostty"] == "com.mitchellh.ghostty")
        #expect(TerminalLauncher.bundleIdentifiers["Warp"] == "dev.warp.Warp-Stable")
    }

    @Test func pathsExpandAndAbbreviateAgainstHome() {
        let home = URL(filePath: "/Users/avery", directoryHint: .isDirectory)
        #expect(LongTailPanels.expand("~/Developer", home: home)?.path(percentEncoded: false) == "/Users/avery/Developer")
        #expect(LongTailPanels.expand("~", home: home) == home)
        #expect(LongTailPanels.expand("  ", home: home) == nil)
        #expect(LongTailPanels.abbreviate(URL(filePath: "/Users/avery/Developer/vrai/"), home: home) == "~/Developer/vrai")
        #expect(LongTailPanels.abbreviate(URL(filePath: "/opt/src"), home: home) == "/opt/src")
    }

    @Test func appSheetsHaveStableIdentifiers() {
        #expect(AppSheetKind.clone(url: nil).id == "clone")
        #expect(AppSheetKind.open.id == "open")
        #expect(AppSheetKind.newRepository(folder: "~/x").id == "init")
        #expect(AppSheetKind.reference("rebase").id == "reference:rebase")
        #expect(AppSheetKind.bugReport.id == "bugreport")
    }
}
