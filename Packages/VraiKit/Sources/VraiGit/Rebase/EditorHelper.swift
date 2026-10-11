import Foundation

public enum EditorHelper {
    public static let name = "vrai-editor"
    public static let environmentKey = "VRAI_EDITOR_HELPER"

    public static func locate(environment: GitEnvironment, fileManager: FileManager = .default) -> String? {
        var candidates: [String] = []
        if let explicit = environment.base[environmentKey], !explicit.isEmpty { candidates.append(explicit) }
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: name) { candidates.append(bundled.path(percentEncoded: false)) }
        if let main = Bundle.main.executableURL {
            candidates.append(main.deletingLastPathComponent().appending(path: name).path(percentEncoded: false))
        }
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    public static func quote(_ word: String) -> String {
        "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func sequenceEditor(helper: String, todo: URL) -> String {
        quote(helper) + " --todo " + quote(todo.path(percentEncoded: false))
    }

    public static func messageEditor(helper: String, messages: URL) -> String {
        quote(helper) + " --messages " + quote(messages.path(percentEncoded: false))
    }
}
