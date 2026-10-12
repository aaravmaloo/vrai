import SwiftUI
import VraiCore
import VraiGit

struct CherryPickSheet: View {
    let ids: [OID]
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @State private var recordOrigin = false
    @State private var noCommit = false
    @State private var mainline = 1
    @State private var commits: [PreviewCommit] = []
    @State private var hasMerge = false

    var body: some View {
        let head = window.headName
        let command = RewriteCommands.cherryPick(ids: ids, recordOrigin: recordOrigin, noCommit: noCommit, mainline: hasMerge ? mainline : nil)
        RewriteSheet(
            title: String(localized: "Cherry-pick onto \(head)", bundle: .module),
            description: String(localized: "Copies the changes of a commit onto the current branch as a new commit.", bundle: .module)
        ) {
            RewriteCommitList(commits: commits)
            RewriteCheckbox(String(localized: "Note where it came from in the message", bundle: .module), isOn: $recordOrigin, description: String(localized: "Adds (cherry picked from commit \u{2026}), -x", bundle: .module))
            RewriteCheckbox(String(localized: "Apply the changes without committing", bundle: .module), isOn: $noCommit, description: String(localized: "--no-commit", bundle: .module))
            if hasMerge {
                RewriteField(label: String(localized: "This is a merge. Diff against parent", bundle: .module)) {
                    SegmentedControl(selection: $mainline, items: [
                        SegmentItem(value: 1, title: String(localized: "1, the branch it was merged into", bundle: .module), label: String(localized: "Parent 1", bundle: .module)),
                        SegmentItem(value: 2, title: String(localized: "2, the merged branch", bundle: .module), label: String(localized: "Parent 2", bundle: .module))
                    ], small: false)
                }
            }
            RewriteOptions(command: command)
        } actions: {
            RewriteFoot(label: ids.count == 1 ? String(localized: "Cherry-pick \(ids[0].short)", bundle: .module) : String(localized: "Cherry-pick \(n(ids.count, "commit"))", bundle: .module), disabled: ids.isEmpty, identifier: "cherry-run", cancel: { window.sheets.dismiss() }) {
                window.sheets.dismiss()
                RewriteActions.cherryPick(window, ids: ids, recordOrigin: recordOrigin, noCommit: noCommit, mainline: hasMerge ? mainline : nil)
            }
        }
        .task {
            commits = await store.previewSubjects(ids)
            for id in ids where await store.isMergeCommit(id) {
                hasMerge = true
                break
            }
        }
    }
}
