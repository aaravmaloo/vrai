import Foundation
import Testing
import VraiCore
import VraiGit
@testable import VraiUI

@MainActor
struct ExpertLogicTests {
    @Test func anUneditedPreviewLeavesTheSheetToRunItsOwnCommand() {
        let draft = CommandDraft()
        var ran: [[String]] = []
        draft.runner = { commands in ran.append(contentsOf: commands.map(\.command.arguments)) }
        draft.register(0, RewriteCommands.reset(to: "HEAD~1", mode: .soft))
        #expect(draft.text(0) == "git reset --soft HEAD~1")
        #expect(!draft.isEdited)
        #expect(!draft.submit())
        draft.edit(0, "git reset --soft HEAD~1  ")
        #expect(!draft.isEdited)
        #expect(ran.isEmpty)
    }

    @Test func anEditedPreviewRunsWhatWasTypedAsArguments() {
        let draft = CommandDraft()
        var ran: [[String]] = []
        draft.runner = { commands in ran.append(contentsOf: commands.map(\.command.arguments)) }
        draft.register(0, RewriteCommands.stash(message: "WIP"))
        draft.register(1, RewriteCommands.reset(to: "HEAD~1", mode: .soft))
        draft.edit(1, "git reset --keep HEAD~2; rm -rf x")
        #expect(draft.isEdited(1))
        #expect(!draft.isEdited(0))
        #expect(draft.submit())
        #expect(ran == [["stash", "push", "-m", "WIP"], ["reset", "--keep", "HEAD~2;", "rm", "-rf", "x"]])
    }

    @Test func anEditThatIsNotAGitCommandShowsAProblemAndRunsNothing() {
        let draft = CommandDraft()
        var ran = 0
        draft.runner = { _ in ran += 1 }
        draft.register(0, RewriteCommands.reset(to: "HEAD~1", mode: .soft))
        draft.edit(0, "git -c core.editor=vim commit")
        #expect(draft.submit())
        #expect(draft.problem == ConsoleCopy.problem(.globalOptions))
        #expect(ran == 0)
        draft.revert(0)
        #expect(draft.problem == nil)
        #expect(!draft.isEdited)
    }

    @Test func theRiskTagNeverDropsBelowTheSheetFloor() {
        #expect(RiskTag.level(SyncCommands.push(remote: "origin", refspec: "main")) == .safe)
        #expect(RiskTag.level(SyncCommands.push(remote: "origin", refspec: "main"), at: .rewrites) == .rewrites)
        #expect(RiskTag.level(RewriteCommands.reset(to: "HEAD~1", mode: .hard), at: .rewrites) == .destructive)
        #expect(RiskTag.tag(.safe) == nil)
        #expect(RiskTag.tag(.rewrites)?.label == "Rewrites history")
        #expect(RiskTag.tag(.destructive)?.label == "Destructive")
    }
}
