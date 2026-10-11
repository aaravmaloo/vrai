import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VraiCore
import VraiGit

@MainActor
enum CoverageActions {
    static func compareWithBeforeRebase(_ window: WindowModel, branch: String) {
        let store = window.store
        Task {
            do {
                if try await store.compareWithBeforeRebase(branch: branch) != nil {
                    window.console.show()
                } else {
                    window.toasts.show(Toast(message: String(localized: "\(branch) hasn't been rebased lately", bundle: .module), detail: String(localized: "Its last move in the reflog wasn't a rebase, so there's no before to compare with.", bundle: .module), icon: "arrow.left.arrow.right"))
                }
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "The comparison didn't run", bundle: .module))
            }
        }
    }

    static func annotate(_ window: WindowModel, path: String, revision: String?) {
        let store = window.store
        window.console.show()
        Task {
            do {
                try await store.annotate(path: path, at: revision)
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "git annotate didn't run", bundle: .module))
            }
        }
    }

    static func openDiffTool(_ window: WindowModel, file: WorkingFile) {
        let store = window.store
        let name = PathParts.split(file.path).name
        window.toasts.show(Toast(message: String(localized: "Opened \(name) in FileMerge", bundle: .module), icon: "plusminus", timeout: Toast.brief))
        Task {
            do {
                try await store.openDiffTool(path: file.path, staged: file.staged == .full)
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "The diff tool didn't open", bundle: .module))
            }
        }
    }

    static func confirmStartOver(_ window: WindowModel, path: String, everyFile: Bool, perform: @escaping @MainActor () -> Void) {
        let name = PathParts.split(path).name
        window.alerts.present(AlertRequest(
            title: everyFile ? String(localized: "Start over with every conflicted file?", bundle: .module) : String(localized: "Start over with \(name)?", bundle: .module),
            message: everyFile
                ? String(localized: "git merges each file again from both sides and puts every conflict back. Choices you made in these files are lost.", bundle: .module)
                : String(localized: "git merges \(name) again from both sides and puts every conflict back. Choices you made in this file are lost.", bundle: .module),
            actions: [
                AlertAction(title: String(localized: "Start over", bundle: .module), role: .destructive, action: perform),
                AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel)
            ]
        ))
    }

    static func packLooseObjects(_ window: WindowModel) {
        let store = window.store
        guard !store.busy.contains("packObjects") else { return }
        let busy = window.toasts.show(Toast(message: String(localized: "Packing loose objects\u{2026}", bundle: .module), detail: String(localized: "You can keep working.", bundle: .module), icon: "archivebox", timeout: 3600, busy: true))
        Task {
            defer { window.toasts.dismiss(busy) }
            do {
                let summary = try await store.packLooseObjects()
                let detail = summary.packed == 0
                    ? String(localized: "Every reachable object was already in a pack.", bundle: .module)
                    : String(localized: "\(n(summary.packed, "loose object")) moved into a new pack; \(n(summary.looseAfter, "loose object")) left.", bundle: .module)
                window.toasts.show(Toast(message: String(localized: "Packed loose objects", bundle: .module), detail: detail, icon: "archivebox", action: String(localized: "Show console", bundle: .module)) {
                    window.console.show()
                })
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "The objects weren't packed", bundle: .module))
            }
        }
    }

    static func findRedundantPacks(_ window: WindowModel) {
        let store = window.store
        Task {
            do {
                let packs = try await store.redundantPacks()
                if packs.isEmpty {
                    window.toasts.show(Toast(message: String(localized: "No redundant packs", bundle: .module), detail: String(localized: "Every pack holds objects that no other pack has.", bundle: .module), icon: "archivebox"))
                } else {
                    window.toasts.show(Toast(tone: .warning, message: String(localized: "Found \(n(packs.count, "redundant pack"))", bundle: .module), detail: String(localized: "Their objects are in other packs too. Clean up removes them.", bundle: .module), icon: "archivebox", action: String(localized: "Clean up", bundle: .module)) {
                        LongTailActions.maintenance(window, .gc)
                    })
                }
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "The packs weren't checked", bundle: .module))
            }
        }
    }

    static func recoverObjects(_ window: WindowModel) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let type = UTType(filenameExtension: "pack") { panel.allowedContentTypes = [type] }
        panel.prompt = String(localized: "Recover", bundle: .module)
        panel.message = String(localized: "Choose a .pack file, for example from another clone, to copy the objects it has into this repository.", bundle: .module)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let store = window.store
        Task {
            do {
                let added = try await store.recoverObjects(fromPack: url)
                window.toasts.show(Toast(message: added == 0 ? String(localized: "The repository already had every object", bundle: .module) : String(localized: "Recovered \(n(added, "object"))", bundle: .module), detail: String(localized: "From \(url.lastPathComponent). Verify integrity to check the repository again.", bundle: .module), icon: "shippingbox", action: String(localized: "Verify integrity", bundle: .module)) {
                    LongTailActions.verifyIntegrity(window)
                })
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "The objects weren't recovered", bundle: .module))
            }
        }
    }

    static func addCoAuthor(_ window: WindowModel, _ person: Contributor) {
        let store = window.store
        let changes = window.changes
        let message = CommitMessage(subject: changes.subject, body: changes.body)
        Task {
            do {
                let updated = try await store.addTrailers([.coAuthor(name: person.name, email: person.email)], to: message)
                guard changes.subject == message.subject, changes.body == message.body else { return }
                changes.body = updated.body
            } catch {
                RewriteActions.report(error, window, failure: String(localized: "The co-author wasn't added", bundle: .module))
            }
        }
    }
}
