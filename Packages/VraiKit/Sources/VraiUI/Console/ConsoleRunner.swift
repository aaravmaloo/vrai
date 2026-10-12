import AppKit
import SwiftUI
import VraiCore
import VraiGit

enum ConsoleCopy {
    static func problem(_ problem: TypedCommand.Problem) -> String {
        switch problem {
        case .empty:
            String(localized: "Type a git command, like status or log --oneline.", bundle: .module)
        case .notGit:
            String(localized: "Start with git to run a command, for example git log --oneline -5.", bundle: .module)
        case .globalOptions:
            String(localized: "Put the git command first, like git status. Options before it, such as -C or -c, don't run here.", bundle: .module)
        }
    }

    static let editor = String(localized: "Vrai's console doesn't open an editor. Pass a message with -m, or use the composer in Changes.", bundle: .module)
    static let interactive = String(localized: "Opened the interactive rebase sheet. Vrai edits the todo list there instead of in an editor.", bundle: .module)
    static let expertOnly = String(localized: "Running git commands is part of Expert mode", bundle: .module)
    static let turnOnExpert = String(localized: "Turn on Expert mode", bundle: .module)
    static let filterRepo = URL(string: "https://github.com/newren/git-filter-repo")

    static func expertDetail(_ text: String) -> String {
        String(localized: "Turn it on to run \(text) here and in the console.", bundle: .module)
    }
}

extension WindowModel {
    public func runTyped(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard preferences.expert else {
            toasts.show(Toast(message: ConsoleCopy.expertOnly, detail: ConsoleCopy.expertDetail(trimmed), icon: "terminal", action: ConsoleCopy.turnOnExpert) { [weak self] in
                self?.toggleExpert()
            })
            return
        }
        if let problem = TypedCommand.problem(trimmed) {
            store.console.remember(trimmed)
            console.notice = ConsoleCopy.problem(problem)
            console.show()
            return
        }
        guard let typed = TypedCommand(trimmed) else { return }
        if let target = typed.interactiveRebaseTarget {
            store.console.remember(typed.display)
            console.notice = ConsoleCopy.interactive
            RewriteActions.openInteractive(self, onto: target)
            return
        }
        if typed.subcommand == "commit", typed.opensEditor {
            store.console.remember(typed.display)
            console.notice = ConsoleCopy.editor
            console.show()
            return
        }
        confirmThenRun([typed])
    }

    public func runEdited(_ commands: [TypedCommand]) {
        guard !commands.isEmpty else { return }
        confirmThenRun(commands)
    }

    public func runAgain(_ entry: ConsoleEntry) {
        runTyped(entry.command)
    }

    func confirmThenRun(_ commands: [TypedCommand]) {
        let risky = commands.filter { $0.risk == .destructive }
        guard let first = risky.first else {
            execute(commands)
            return
        }
        if first.subcommand == "filter-branch" {
            alerts.present(AlertRequest(
                title: String(localized: "Run git filter-branch?", bundle: .module),
                message: String(localized: "git itself discourages filter-branch: it's slow and easy to get wrong, and git filter-repo is the tool it recommends. This rewrites history, and Vrai can't undo what you run here.", bundle: .module),
                actions: [
                    AlertAction(title: String(localized: "Run filter-branch", bundle: .module), role: .destructive) { [weak self] in self?.execute(commands) },
                    AlertAction(title: String(localized: "Learn about filter-repo", bundle: .module)) {
                        if let url = ConsoleCopy.filterRepo { NSWorkspace.shared.open(url) }
                    },
                    AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel)
                ]
            ))
            return
        }
        let shown = risky.map(\.display).joined(separator: "\n")
        alerts.present(AlertRequest(
            title: risky.count == 1 ? String(localized: "Run this destructive command?", bundle: .module) : String(localized: "Run \(risky.count) destructive commands?", bundle: .module),
            message: String(localized: "\(shown)\nIt can throw work away, and Undo history doesn't cover commands you type.", bundle: .module),
            actions: [
                AlertAction(title: risky.count == 1 ? String(localized: "Run command", bundle: .module) : String(localized: "Run commands", bundle: .module), role: .destructive) { [weak self] in self?.execute(commands) },
                AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel)
            ]
        ))
    }

    func execute(_ commands: [TypedCommand]) {
        console.notice = nil
        console.show()
        let id = UUID()
        let store = store
        console.tasks[id] = Task { [weak self] in
            defer { self?.console.tasks.removeValue(forKey: id) }
            for typed in commands {
                do {
                    let run = try await store.run(typed)
                    if !run.succeeded { break }
                } catch let error as GitError {
                    if error.code != .cancelled { self?.alerts.present(error) }
                    break
                } catch {
                    break
                }
                if Task.isCancelled { break }
            }
        }
    }

    public func showObject(_ id: OID) {
        console.show()
        let store = store
        Task {
            _ = try? await store.showObject(id: id)
        }
    }

    public func openPalette(_ mode: PaletteMode = .everything, query: String = "") {
        switcher.dismiss()
        if mode == .branches, query.isEmpty {
            palette.dismiss()
            branchPicker = true
            return
        }
        palette.present(mode, query: query)
    }
}
