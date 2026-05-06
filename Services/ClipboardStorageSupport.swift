import AppKit
import Foundation

struct ClipboardStoragePaths: Sendable {
    let storageDirectory: URL
    let historyFileURL: URL
    let imagesDirectory: URL
    let textsDirectory: URL

    init(storageDirectory: URL, historyFileURL: URL, imagesDirectory: URL, textsDirectory: URL) {
        self.storageDirectory = storageDirectory
        self.historyFileURL = historyFileURL
        self.imagesDirectory = imagesDirectory
        self.textsDirectory = textsDirectory
    }

    init(fileManager: FileManager = .default) throws {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let storageDirectory = appSupport.appendingPathComponent("Buffer", isDirectory: true)

        self.storageDirectory = storageDirectory
        self.historyFileURL = storageDirectory.appendingPathComponent("history.json")
        self.imagesDirectory = storageDirectory.appendingPathComponent("images", isDirectory: true)
        self.textsDirectory = storageDirectory.appendingPathComponent("texts", isDirectory: true)
    }
}

private struct ClipboardHistoryEnvelope: Codable, Sendable {
    let version: Int
    let items: [ClipboardItem]

    static let currentVersion = 1
}

final class ClipboardHistoryPersistence: @unchecked Sendable {
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

final class ClipboardAssetStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let paths: ClipboardStoragePaths

    init(fileManager: FileManager = .default, paths: ClipboardStoragePaths) {
        self.fileManager = fileManager
        self.paths = paths
    }

    func ensureDirectoriesExist() {
        createDirectoryIfNeeded(at: paths.storageDirectory, label: "storage")
        createDirectoryIfNeeded(at: paths.imagesDirectory, label: "images")
        createDirectoryIfNeeded(at: paths.textsDirectory, label: "texts")
    }

    func cleanupOrphanedAssets(referencedBy items: [ClipboardItem]) {
        let referencedImages = Set(items.compactMap(\.imageFilename))
        let referencedTexts = Set(items.compactMap(\.textFilename))

        cleanupOrphanedFiles(in: paths.imagesDirectory, keeping: referencedImages, label: "image")
        cleanupOrphanedFiles(in: paths.textsDirectory, keeping: referencedTexts, label: "text")
    }

    func image(for item: ClipboardItem) -> NSImage? {
        guard item.type == .image, let filename = item.imageFilename else { return nil }
        let url = paths.imagesDirectory.appendingPathComponent(filename)
        return NSImage(contentsOf: url)
    }

    func saveImage(_ data: Data) -> String? {
        let filename = UUID().uuidString + ".png"
        let url = paths.imagesDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: url, options: .atomic)
            return filename
        } catch {
            BufferLogger.persistence.error("Failed to save image: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func saveText(_ text: String) -> String? {
        let filename = UUID().uuidString + ".txt"
        let url = paths.textsDirectory.appendingPathComponent(filename)

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return filename
        } catch {
            BufferLogger.persistence.error("Failed to save text file: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func fullText(for item: ClipboardItem) -> String? {
        guard let filename = item.textFilename else { return item.textContent }
        let url = paths.textsDirectory.appendingPathComponent(filename)

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            BufferLogger.persistence.error("Failed to load text file: \(String(describing: error), privacy: .public)")
            return item.textContent
        }
    }

    func textChunk(for item: ClipboardItem, charCount: Int) -> (text: String, totalBytes: Int, reachedEOF: Bool)? {
        if let filename = item.textFilename {
            let url = paths.textsDirectory.appendingPathComponent(filename)

            do {
                let attributes = try fileManager.attributesOfItem(atPath: url.path)
                let totalBytes = attributes[.size] as? Int ?? 0
                let maximumBytesToRead = min(charCount * 4, totalBytes)

                let fileHandle = try FileHandle(forReadingFrom: url)
                defer {
                    try? fileHandle.close()
                }

                let data = try fileHandle.read(upToCount: maximumBytesToRead) ?? Data()
                let fullChunkString = String(decoding: data, as: UTF8.self)
                let exactChunkString = String(fullChunkString.prefix(charCount))
                let reachedEOF = fullChunkString.count < charCount
                return (exactChunkString, totalBytes, reachedEOF)
            } catch {
                BufferLogger.persistence.error("Failed to read text chunk: \(String(describing: error), privacy: .public)")
                return nil
            }
        }

        let content = item.textContent ?? ""
        let totalBytes = item.originalSizeBytes ?? content.utf8.count
        let prefix = String(content.prefix(charCount))
        let reachedEOF = content.count <= charCount

        return (prefix, totalBytes, reachedEOF)
    }

    func itemSize(for item: ClipboardItem) -> Int? {
        if let original = item.originalSizeBytes {
            return original
        }

        switch item.type {
        case .text:
            if let filename = item.textFilename {
                return fileSize(at: paths.textsDirectory.appendingPathComponent(filename))
            }
            return item.textContent?.utf8.count
        case .image:
            if let filename = item.imageFilename {
                return fileSize(at: paths.imagesDirectory.appendingPathComponent(filename))
            }
            return nil
        }
    }

    func deleteAssociatedFiles(for item: ClipboardItem) {
        deleteImageFile(for: item)
        deleteTextFile(for: item)
    }

    private func deleteImageFile(for item: ClipboardItem) {
        guard item.type == .image, let filename = item.imageFilename else { return }
        removeItemIfPresent(at: paths.imagesDirectory.appendingPathComponent(filename), label: "image")
    }

    private func deleteTextFile(for item: ClipboardItem) {
        guard let filename = item.textFilename else { return }
        removeItemIfPresent(at: paths.textsDirectory.appendingPathComponent(filename), label: "text")
    }

    private func createDirectoryIfNeeded(at url: URL, label: String) {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            BufferLogger.persistence.error("Failed to create \(label, privacy: .public) directory: \(String(describing: error), privacy: .public)")
        }
    }

    private func fileSize(at url: URL) -> Int? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int
        } catch {
            BufferLogger.persistence.error("Failed to read file size at \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func removeItemIfPresent(at url: URL, label: String) {
        guard fileManager.fileExists(atPath: url.path) else { return }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            BufferLogger.persistence.error("Failed to remove \(label, privacy: .public) file \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func cleanupOrphanedFiles(in directory: URL, keeping referencedNames: Set<String>, label: String) {
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }

        for fileURL in contents where !referencedNames.contains(fileURL.lastPathComponent) {
            removeItemIfPresent(at: fileURL, label: label)
        }
    }
}
