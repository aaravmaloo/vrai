import CoreGraphics
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
    public var windowSize: CGSize?
    public var capture = false
    public var settings: String?
    public var gitProblem: String?
    public var openDelay: Int?

    public init(sandbox: URL? = nil, open: URL? = nil, appearance: Appearance? = nil, now: Date? = nil, windowSize: CGSize? = nil, capture: Bool = false, settings: String? = nil) {
        self.sandbox = sandbox
        self.open = open
        self.appearance = appearance
        self.now = now
        self.windowSize = windowSize
        self.capture = capture
        self.settings = settings
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
            case "-VraiWindowSize":
                let parts = value.split(separator: "x").compactMap { Double($0) }
                windowSize = parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
            case "-VraiCapture":
                capture = ["YES", "1", "true"].contains(value)
            case "-VraiSettings":
                settings = value
            case "-VraiGitProblem":
                gitProblem = value
            case "-VraiOpenDelay":
                openDelay = Int(value)
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
