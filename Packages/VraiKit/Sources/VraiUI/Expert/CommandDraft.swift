import Observation
import SwiftUI
import VraiCore
import VraiGit

@MainActor
@Observable
final class CommandDraft {
    var texts: [Int: String] = [:]
    var built: [Int: GitCommand] = [:]
    var problem: String?
    @ObservationIgnored var runner: (@MainActor ([TypedCommand]) -> Void)?

    func register(_ index: Int, _ command: GitCommand) {
        if built[index] != command { built[index] = command }
    }

    func text(_ index: Int) -> String {
        texts[index] ?? built[index]?.display ?? ""
    }

    func edit(_ index: Int, _ text: String) {
        if let command = built[index], text.trimmingCharacters(in: .whitespacesAndNewlines) == command.display {
            texts.removeValue(forKey: index)
        } else {
            texts[index] = text
        }
        problem = nil
    }

    func revert(_ index: Int) {
        texts.removeValue(forKey: index)
        problem = nil
    }

    func isEdited(_ index: Int) -> Bool {
        guard let text = texts[index], let command = built[index] else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines) != command.display
    }

    var isEdited: Bool {
        built.keys.contains { isEdited($0) }
    }

    func commands() -> [TypedCommand]? {
        var out: [TypedCommand] = []
        for index in built.keys.sorted() {
            guard let command = built[index] else { continue }
            if isEdited(index) {
                let text = text(index)
                if let issue = TypedCommand.problem(text) {
                    problem = ConsoleCopy.problem(issue)
                    return nil
                }
                guard let typed = TypedCommand(text) else { return nil }
                out.append(typed)
            } else {
                out.append(TypedCommand(command: command))
            }
        }
        return out
    }

    @discardableResult
    func submit() -> Bool {
        guard isEdited else { return false }
        guard let commands = commands(), !commands.isEmpty else { return true }
        runner?(commands)
        return true
    }
}

struct CommandDraftKey: EnvironmentKey {
    static let defaultValue: CommandDraft? = nil
}

extension EnvironmentValues {
    var commandDraft: CommandDraft? {
        get { self[CommandDraftKey.self] }
        set { self[CommandDraftKey.self] = newValue }
    }
}

struct CommandDraftScope: ViewModifier {
    @Environment(WindowModel.self) private var window
    @State private var draft = CommandDraft()

    func body(content: Content) -> some View {
        content
            .environment(\.commandDraft, draft)
            .onAppear { install() }
    }

    func install() {
        weak let target = window
        draft.runner = { commands in
            guard let target else { return }
            target.sheets.dismiss()
            target.runEdited(commands)
        }
    }
}
