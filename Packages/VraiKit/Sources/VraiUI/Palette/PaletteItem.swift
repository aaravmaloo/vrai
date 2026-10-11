import SwiftUI
import VraiCore
import VraiGit

struct PaletteItem: Identifiable, PaletteRankable {
    enum Glyph {
        case symbol(String)
        case lane(String, Int)
        case file(FileStatus)
    }

    var id: String
    var label: String
    var glyph: Glyph
    var detail: String?
    var keywords: String?
    var shortcut: String?
    var danger = false
    var risk: GitCommand.Risk?
    var current = false
    var command = false
    var run: @MainActor (_ option: Bool) -> Void

    var rankLabel: String { label }
    var rankKeywords: String? { keywords }
    var rankDetail: String? { detail }
    var rankCurrent: Bool { current }
}

extension PaletteGroupKind {
    var title: String {
        switch self {
        case .run: String(localized: "Run in git", bundle: .module)
        case .topHit: String(localized: "Top hit", bundle: .module)
        case .suggestions: String(localized: "Suggestions", bundle: .module)
        case .recentBranches: String(localized: "Recent branches", bundle: .module)
        case .actions: String(localized: "Actions", bundle: .module)
        case .branches: String(localized: "Branches", bundle: .module)
        case .remoteBranches: String(localized: "Remote branches", bundle: .module)
        case .newBranch: String(localized: "New branch", bundle: .module)
        case .tags: String(localized: "Tags", bundle: .module)
        case .commits: String(localized: "Commits", bundle: .module)
        case .files: String(localized: "Files", bundle: .module)
        case .code: String(localized: "Code", bundle: .module)
        }
    }
}

enum PaletteFileIcon {
    static func symbol(for path: String) -> String {
        let ext = (path.split(separator: ".").last.map(String.init) ?? "").lowercased()
        guard path.contains(".") else { return "doc" }
        if ext == "swift" { return "swift" }
        if ["png", "jpg", "jpeg", "gif", "svg", "webp", "icns", "pdf"].contains(ext) { return "photo" }
        if ["json", "yml", "yaml", "toml", "plist", "js", "ts", "mjs", "jsx", "tsx", "c", "h", "m", "sh"].contains(ext) { return "curlybraces" }
        if ["md", "txt", "rtf"].contains(ext) { return "doc.text" }
        return "doc"
    }
}
