import Foundation

private struct ClipboardHistoryEnvelope: Codable, Sendable {
    let version: Int
    let items: [ClipboardItem]

    static let currentVersion = 1
}

protocol ClipboardHistoryPersisting: Sendable {
    func loadHistory() throws -> [ClipboardItem]
    func saveHistory(_ items: [ClipboardItem]) throws
}

final class ClipboardHistoryPersistence: ClipboardHistoryPersisting, @unchecked Sendable {
    private let fileManager: FileManager
    private let paths: ClipboardStoragePaths

    init(fileManager: FileManager = .default, paths: ClipboardStoragePaths) {
        self.fileManager = fileManager
        self.paths = paths
    }

    func loadHistory() throws -> [ClipboardItem] {
        guard fileManager.fileExists(atPath: paths.historyFileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: paths.historyFileURL)

        if let envelope = try? JSONDecoder().decode(ClipboardHistoryEnvelope.self, from: data) {
            return envelope.items
        }

        return try JSONDecoder().decode([ClipboardItem].self, from: data)
    }

    func saveHistory(_ items: [ClipboardItem]) throws {
        let envelope = ClipboardHistoryEnvelope(
            version: ClipboardHistoryEnvelope.currentVersion,
            items: items
        )
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: paths.historyFileURL, options: .atomic)
    }
}
