import Foundation

public struct UpdateFeed: Sendable, Equatable {
    public static let feedKey = "SUFeedURL"
    public static let publicKeyKey = "SUPublicEDKey"
    public static let sandboxArgument = "-VraiSandbox"

    public let url: URL
    public let publicKey: String

    public init?(info: [String: Any], arguments: [String]) {
        guard !arguments.contains(Self.sandboxArgument) else { return nil }
        guard let url = Self.feedURL(info[Self.feedKey]), let publicKey = Self.publicKey(info[Self.publicKeyKey]) else { return nil }
        self.url = url
        self.publicKey = publicKey
    }

    static func feedURL(_ value: Any?) -> URL? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", let host = url.host(), !host.isEmpty else { return nil }
        return url
    }

    static func publicKey(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        guard Data(base64Encoded: text)?.count == 32 else { return nil }
        return text
    }
}
