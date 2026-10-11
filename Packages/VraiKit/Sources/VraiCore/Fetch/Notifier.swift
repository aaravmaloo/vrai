import Foundation

public struct FetchNotification: Sendable, Hashable {
    public var repository: String
    public var title: String
    public var body: String
    public var newCommits: [String: Int]

    public init(repository: String, title: String, body: String, newCommits: [String: Int]) {
        self.repository = repository
        self.title = title
        self.body = body
        self.newCommits = newCommits
    }

    public static func lines(for newCommits: [String: Int]) -> [String] {
        newCommits.filter { $0.value > 0 }.sorted { $0.key < $1.key }.map { ref, count in
            String(localized: "\(n(count, "new commit")) on \(ref)", bundle: .module)
        }
    }
}

public protocol Notifier: Sendable {
    func post(_ notification: FetchNotification) async
}

public struct ClosureNotifier: Notifier {
    let handler: @Sendable (FetchNotification) async -> Void

    public init(_ handler: @escaping @Sendable (FetchNotification) async -> Void) {
        self.handler = handler
    }

    public func post(_ notification: FetchNotification) async {
        await handler(notification)
    }
}
