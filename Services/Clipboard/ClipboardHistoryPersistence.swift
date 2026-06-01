import Foundation

private struct ClipboardHistoryEnvelope: Codable, Sendable {
    let version: Int
    let items: [ClipboardItem]

    static let currentVersion = 1
}

protocol ClipboardHistoryPersisting: Sendable {
    func saveHistory(_ items: [ClipboardItem])
}

final class ClipboardHistoryPersistence: ClipboardHistoryPersisting, @unchecked Sendable {
    private let fileManager: FileManager
    private let paths: ClipboardStoragePaths

    init(fileManager: FileManager = .default, paths: ClipboardStoragePaths) {
        self.fileManager = fileManager
        self.paths = paths
    }

    func loadHistory() -> [ClipboardItem] {
        guard fileManager.fileExists(atPath: paths.historyFileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: paths.historyFileURL)

            if let envelope = try? JSONDecoder().decode(ClipboardHistoryEnvelope.self, from: data) {
                return envelope.items
            }

            return try JSONDecoder().decode([ClipboardItem].self, from: data)
        } catch {
            BufferLogger.persistence.error("Failed to load history: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    func saveHistory(_ items: [ClipboardItem]) {
        do {
            let envelope = ClipboardHistoryEnvelope(
                version: ClipboardHistoryEnvelope.currentVersion,
                items: items
            )
            let data = try JSONEncoder().encode(envelope)
            try data.write(to: paths.historyFileURL, options: .atomic)
        } catch {
            BufferLogger.persistence.error("Failed to save history: \(String(describing: error), privacy: .public)")
        }
    }
}
