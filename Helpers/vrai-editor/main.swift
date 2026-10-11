import Foundation

struct PreparedMessage: Decodable {
    var commit: String?
    var message: String
}

func fail(_ text: String) -> Never {
    FileHandle.standardError.write(Data(("vrai-editor: " + text + "\n").utf8))
    exit(1)
}

func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 2 < arguments.count else { return nil }
    return arguments[index + 1]
}

func replaceTodo(source: String, target: URL) {
    guard let data = FileManager.default.contents(atPath: source) else { fail("can't read the prepared todo list at \(source)") }
    do {
        try data.write(to: target)
    } catch {
        fail("can't write the todo list to \(target.path): \(error.localizedDescription)")
    }
}

func currentStep(editing target: URL) -> String? {
    var directory = target.deletingLastPathComponent()
    for _ in 0..<3 {
        for folder in ["rebase-merge", "rebase-apply"] {
            let done = directory.appendingPathComponent(folder).appendingPathComponent("done")
            guard let text = try? String(contentsOf: done, encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let last = lines.last(where: { !$0.isEmpty && !$0.hasPrefix("#") }) else { return "" }
            let words = last.split(separator: " ").dropFirst()
            let oid = words.first { word in word.count >= 7 && word.allSatisfy { $0.isHexDigit } }
            return oid.map(String.init) ?? ""
        }
        directory = directory.deletingLastPathComponent()
    }
    return nil
}

func nextInOrder(_ messages: [PreparedMessage], cursorPath: String) -> PreparedMessage? {
    let saved = (try? String(contentsOfFile: cursorPath, encoding: .utf8)).flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
    guard saved < messages.count else { return nil }
    try? String(saved + 1).write(toFile: cursorPath, atomically: true, encoding: .utf8)
    return messages[saved]
}

func supplyMessage(source: String, target: URL) {
    guard let data = FileManager.default.contents(atPath: source) else { fail("can't read the prepared messages at \(source)") }
    let messages: [PreparedMessage]
    do {
        messages = try JSONDecoder().decode([PreparedMessage].self, from: data)
    } catch {
        fail("the prepared messages at \(source) aren't valid: \(error.localizedDescription)")
    }
    let chosen: PreparedMessage?
    if let step = currentStep(editing: target) {
        chosen = step.isEmpty ? nil : messages.first { entry in
            guard let commit = entry.commit?.lowercased() else { return false }
            return commit.hasPrefix(step.lowercased()) || step.lowercased().hasPrefix(commit)
        }
    } else {
        chosen = nextInOrder(messages, cursorPath: source + ".cursor")
    }
    guard let chosen else { return }
    let text = chosen.message.hasSuffix("\n") ? chosen.message : chosen.message + "\n"
    do {
        try Data(text.utf8).write(to: target)
    } catch {
        fail("can't write the message to \(target.path): \(error.localizedDescription)")
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let last = arguments.last else { exit(0) }
let target = URL(fileURLWithPath: last)
if let todo = value(after: "--todo", in: arguments) {
    replaceTodo(source: todo, target: target)
} else if let messages = value(after: "--messages", in: arguments) {
    supplyMessage(source: messages, target: target)
}
exit(0)
