import Foundation

public struct LaunchOptions: Sendable, Equatable {
    public enum Appearance: String, Sendable, Equatable {
        case light
        case dark
    }

    public var sandbox: URL?
    public var open: URL?
    public var appearance: Appearance?
    public var now: Date?

    public init(sandbox: URL? = nil, open: URL? = nil, appearance: Appearance? = nil, now: Date? = nil) {
        self.sandbox = sandbox
        self.open = open
        self.appearance = appearance
        self.now = now
    }

    public init(arguments: [String]) {
        self.init()
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let key = arguments[index]
            let next = arguments.index(after: index)
            guard next < arguments.endIndex else { break }
            let value = arguments[next]
            switch key {
            case "-VraiSandbox":
                sandbox = URL(filePath: value, directoryHint: .isDirectory).standardizedFileURL
            case "-VraiOpen":
                open = URL(filePath: value, directoryHint: .isDirectory).standardizedFileURL
            case "-VraiAppearance":
                appearance = Appearance(rawValue: value)
            case "-VraiNow":
                now = TimeInterval(value).map { Date(timeIntervalSince1970: $0) }
            default:
                index = next
                continue
            }
            index = arguments.index(after: next)
        }
    }

    public var isSandboxed: Bool { sandbox != nil }

    public static let sandboxSuiteName = "com.aaravmaloo.vrai.sandbox"

    public func makeDefaults() -> UserDefaults {
        guard let sandbox else { return .standard }
        try? FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let path = sandbox.appending(path: Self.sandboxSuiteName).path(percentEncoded: false)
        return UserDefaults(suiteName: path) ?? .standard
    }

    public var recentsFile: URL? {
        sandbox?.appending(path: "recents.json")
    }
}
