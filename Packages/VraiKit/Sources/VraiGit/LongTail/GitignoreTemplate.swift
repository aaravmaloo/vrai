import Foundation

public enum GitignoreTemplate: String, Sendable, Hashable, CaseIterable, Codable {
    case swift = "Swift"
    case xcode = "Xcode"
    case node = "Node"
    case python = "Python"
    case none = "None"

    public var contents: String? {
        switch self {
        case .swift:
            return Self.join(Self.macOS + [".build/", "/Packages", ".swiftpm/", "Package.resolved", "*.xcodeproj/xcuserdata/", "DerivedData/", "*.xcresult"])
        case .xcode:
            return Self.join(Self.macOS + ["xcuserdata/", "*.xcuserstate", "*.xcscmblueprint", "*.xccheckout", "DerivedData/", "build/", "*.moved-aside", "*.hmap", "*.ipa", "*.dSYM.zip", "*.dSYM", "*.xcresult", ".swiftpm/"])
        case .node:
            return Self.join(Self.macOS + ["node_modules/", "npm-debug.log*", "yarn-debug.log*", "yarn-error.log*", "pnpm-debug.log*", ".npm/", ".env", ".env.local", "dist/", "build/", "coverage/", ".cache/"])
        case .python:
            return Self.join(Self.macOS + ["__pycache__/", "*.py[cod]", "*.so", ".Python", "build/", "dist/", "*.egg-info/", ".eggs/", ".venv/", "venv/", "env/", ".env", ".pytest_cache/", ".mypy_cache/", ".coverage", "htmlcov/"])
        case .none:
            return nil
        }
    }

    static let macOS = [".DS_Store"]

    static func join(_ lines: [String]) -> String {
        lines.joined(separator: "\n") + "\n"
    }
}
