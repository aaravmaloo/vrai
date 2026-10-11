import Foundation

public enum HookTrace {
    public static func attach(to command: inout GitCommand) -> URL {
        let trace = FileManager.default.temporaryDirectory.appending(path: "vrai-hooks-\(UUID().uuidString).trace")
        command.environment["GIT_TRACE2_EVENT"] = trace.path(percentEncoded: false)
        return trace
    }

    public static func remove(_ trace: URL) {
        try? FileManager.default.removeItem(at: trace)
    }

    public static func failedHook(in trace: URL) -> String? {
        guard let data = try? Data(contentsOf: trace) else { return nil }
        var hooks: [Int: String] = [:]
        var failed: String?
        for line in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any], let event = object["event"] as? String else { continue }
            let child = (object["child_id"] as? NSNumber)?.intValue
            if event == "child_start", object["child_class"] as? String == "hook", let child, let name = object["hook_name"] as? String {
                hooks[child] = name
            } else if event == "child_exit", let child, let name = hooks[child], let code = (object["code"] as? NSNumber)?.intValue, code != 0 {
                failed = name
            }
        }
        return failed
    }

    public static func refine(_ error: GitError, trace: URL) -> GitError {
        guard let hook = failedHook(in: trace), let result = error.result else { return error }
        let kept = result.errorOutput.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            if line.hasPrefix("From ") || line.hasPrefix("Not committing merge") { return false }
            if line.first?.isWhitespace == true, line.contains("->") { return false }
            return true
        }
        let output = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return GitError(.hookFailed(name: hook, output: output), result: result)
    }
}
