import Foundation

final class ClipboardTextAssetStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let directory: URL

    init(fileManager: FileManager = .default, directory: URL) {
        self.fileManager = fileManager
        self.directory = directory
    }

    func saveText(_ text: String) -> String? {
        let filename = UUID().uuidString + ".txt"
        let url = directory.appendingPathComponent(filename)

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return filename
        } catch {
            BufferLogger.persistence.error("Failed to save text file: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func fullText(for item: ClipboardItem) -> String? {
        if let colorPayload = item.colorPayload {
            return colorPayload.originalText
        }

        guard let filename = item.textFilename else { return item.textContent }
        let url = directory.appendingPathComponent(filename)

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            BufferLogger.persistence.error("Failed to load text file: \(String(describing: error), privacy: .public)")
            return item.textContent
        }
    }

    func textChunk(for item: ClipboardItem, charCount: Int) -> (text: String, totalBytes: Int, reachedEOF: Bool)? {
        if let colorPayload = item.colorPayload {
            let content = colorPayload.originalText
            let prefix = String(content.prefix(charCount))
            return (prefix, content.utf8.count, content.count <= charCount)
        }

        if let filename = item.textFilename {
            let url = directory.appendingPathComponent(filename)

            do {
                let attributes = try fileManager.attributesOfItem(atPath: url.path)
                let totalBytes = attributes[.size] as? Int ?? 0
                let maximumBytesToRead = min(charCount * 4, totalBytes)

                let fileHandle = try FileHandle(forReadingFrom: url)
                defer { try? fileHandle.close() }

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
        guard let filename = item.textFilename else { return item.textContent?.utf8.count }
        return fileSize(at: directory.appendingPathComponent(filename))
    }

    func deleteTextFile(for item: ClipboardItem) {
        guard let filename = item.textFilename else { return }
        removeItemIfPresent(at: directory.appendingPathComponent(filename), label: "text")
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
}
