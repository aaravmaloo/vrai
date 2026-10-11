import Foundation

struct UndoJournal: Codable {
    static let version = 1

    var version: Int
    var entries: [UndoEntry]

    static func read(_ url: URL, fileManager: FileManager = .default) -> [UndoEntry] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let journal = try? decoder.decode(UndoJournal.self, from: data) { return journal.entries }
        let aside = url.deletingLastPathComponent().appending(path: url.lastPathComponent + ".unreadable")
        try? fileManager.removeItem(at: aside)
        try? fileManager.moveItem(at: url, to: aside)
        return []
    }

    static func write(_ entries: [UndoEntry], to url: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(UndoJournal(version: version, entries: entries))
        try data.write(to: url, options: .atomic)
    }
}
