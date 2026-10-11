import Foundation

public enum WorktreeParser {
    public static let command = GitCommand.read(["worktree", "list", "--porcelain", "-z"])

    public static func parse(_ data: Data) -> [Worktree] {
        var worktrees: [Worktree] = []
        var current: Worktree?
        for field in ParseSupport.nulFields(data) {
            if field.isEmpty {
                if let done = current { worktrees.append(done) }
                current = nil
                continue
            }
            let (key, value) = split(field)
            if key == "worktree" {
                if let done = current { worktrees.append(done) }
                current = Worktree(path: value, isMain: worktrees.isEmpty)
                continue
            }
            guard current != nil else { continue }
            switch key {
            case "HEAD": current?.head = OID(value)
            case "branch": current?.branch = value.hasPrefix("refs/heads/") ? String(value.dropFirst("refs/heads/".count)) : value
            case "detached":
                let head = current?.head
                current?.detachedAt = head
            case "bare": current?.isBare = true
            case "locked":
                current?.locked = true
                current?.lockReason = value.isEmpty ? nil : value
            case "prunable": current?.prunable = value.isEmpty ? "prunable" : value
            default: break
            }
        }
        if let done = current { worktrees.append(done) }
        return worktrees
    }

    static func split(_ field: String) -> (String, String) {
        guard let space = field.firstIndex(of: " ") else { return (field, "") }
        return (String(field[..<space]), String(field[field.index(after: space)...]))
    }
}
