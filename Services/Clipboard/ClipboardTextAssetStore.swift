import Darwin
import Foundation

final class ClipboardTextAssetStore: @unchecked Sendable {
    private enum CachePolicy {
        static let totalCostLimit = 32 * 1_024 * 1_024
        static let maximumEntryCost = 4 * 1_024 * 1_024
    }

    private let fileManager: FileManager
    private let directory: URL
    private let fullTextCache = NSCache<NSString, NSString>()

    init(fileManager: FileManager = .default, directory: URL) {
        self.fileManager = fileManager
        self.directory = directory
        fullTextCache.countLimit = 256
        fullTextCache.totalCostLimit = CachePolicy.totalCostLimit
    }

    func saveText(_ text: String) -> String? {
        let filename = ClipboardAssetFilename()
        let url = directory.appendingPathComponent(filename.rawValue)
        let temporaryURL = directory.appendingPathComponent(".\(UUID().uuidString).tmp")

        do {
            guard let data = text.data(using: .utf8) else { return nil }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: temporaryURL, options: .withoutOverwriting)
            let handle = try FileHandle(forWritingTo: temporaryURL)
            try handle.synchronize()
            try handle.close()
            try fileManager.setAttributes(
                [.posixPermissions: 0o400],
                ofItemAtPath: temporaryURL.path
            )
            try fileManager.moveItem(at: temporaryURL, to: url)
            cache(text, filename: filename.rawValue)
            return filename.rawValue
        } catch {
            removeTemporaryFileBestEffort(at: temporaryURL)
            BufferLogger.persistence.error("Failed to save text file: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func fullText(for item: ClipboardItem) -> String? {
        if let colorPayload = item.colorPayload {
            return colorPayload.originalText
        }

        guard let filename = item.textFilename else { return item.textContent }
        let cacheKey = filename as NSString
        if let cachedText = fullTextCache.object(forKey: cacheKey) {
            return cachedText as String
        }
        guard let validatedFilename = ClipboardAssetFilename(rawValue: filename) else {
            BufferLogger.persistence.error("Rejected invalid text asset filename")
            return item.textContent
        }
        let url = directory.appendingPathComponent(validatedFilename.rawValue)

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            cache(text, filename: filename)
            return text
        } catch {
            BufferLogger.persistence.error("Failed to load text file: \(String(describing: error), privacy: .public)")
            return item.textContent
        }
    }

    func fingerprint(for item: ClipboardItem) throws -> ClipboardSearchAssetFingerprint {
        guard let filename = item.textFilename else {
            let byteCount = Int64((item.textContent ?? "").utf8.count)
            return ClipboardSearchAssetFingerprint(
                fileIdentity: nil,
                byteCount: byteCount,
                modificationNanoseconds: 0
            )
        }
        let url = try assetURL(for: filename)
        let handle = try FileHandle(forReadingFrom: url)
        defer { closeBestEffort(handle) }
        return try fingerprint(fileDescriptor: handle.fileDescriptor)
    }

    func snapshot(
        for item: ClipboardItem,
        checkCancellation: @Sendable () throws -> Void
    ) throws -> ClipboardSearchAssetSnapshot {
        guard let filename = item.textFilename else {
            try checkCancellation()
            let text = item.textContent ?? ""
            return ClipboardSearchAssetSnapshot(
                text: text,
                fingerprint: ClipboardSearchAssetFingerprint(
                    fileIdentity: nil,
                    byteCount: Int64(text.utf8.count),
                    modificationNanoseconds: 0
                )
            )
        }
        let handle = try FileHandle(forReadingFrom: assetURL(for: filename))
        defer { closeBestEffort(handle) }
        let before = try fingerprint(fileDescriptor: handle.fileDescriptor)
        var data = Data()
        data.reserveCapacity(Int(clamping: before.byteCount))
        while true {
            try checkCancellation()
            guard let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty else {
                break
            }
            data.append(chunk)
        }
        try checkCancellation()
        let after = try fingerprint(fileDescriptor: handle.fileDescriptor)
        guard before == after else {
            throw CocoaError(.fileReadUnknown)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return ClipboardSearchAssetSnapshot(text: text, fingerprint: after)
    }

    func textChunk(for item: ClipboardItem, charCount: Int) -> ClipboardTextChunk? {
        if let colorPayload = item.colorPayload {
            let content = colorPayload.originalText
            let prefix = String(content.prefix(charCount))
            return ClipboardTextChunk(
                text: prefix,
                totalBytes: content.utf8.count,
                reachedEOF: content.count <= charCount
            )
        }

        if let filename = item.textFilename {
            if let cachedText = fullTextCache.object(forKey: filename as NSString) as String? {
                let prefix = String(cachedText.prefix(charCount))
                return ClipboardTextChunk(
                    text: prefix,
                    totalBytes: cachedText.utf8.count,
                    reachedEOF: cachedText.count <= charCount
                )
            }

            guard let url = try? assetURL(for: filename) else { return nil }

            do {
                let totalBytes = fileSize(at: url) ?? 0
                let handle = try FileHandle(forReadingFrom: url)
                defer { closeBestEffort(handle) }
                let maximumBytes = max(4_096, (charCount * 4) + 4)
                let data = try handle.read(upToCount: maximumBytes) ?? Data()
                let decoded = String(decoding: data, as: UTF8.self)
                let prefix = String(decoded.prefix(charCount))
                return ClipboardTextChunk(
                    text: prefix,
                    totalBytes: totalBytes,
                    reachedEOF: data.count >= totalBytes && decoded.count <= charCount
                )
            } catch {
                BufferLogger.persistence.error(
                    "Failed to read text chunk: \(String(describing: error), privacy: .public)")
                return nil
            }
        }

        let content = item.textContent ?? ""
        let totalBytes = item.originalSizeBytes ?? content.utf8.count
        let prefix = String(content.prefix(charCount))
        let reachedEOF = content.count <= charCount
        return ClipboardTextChunk(
            text: prefix,
            totalBytes: totalBytes,
            reachedEOF: reachedEOF
        )
    }

    func itemSize(for item: ClipboardItem) -> Int? {
        guard let filename = item.textFilename else { return item.textContent?.utf8.count }
        guard let url = try? assetURL(for: filename) else { return nil }
        return fileSize(at: url)
    }

    func deleteTextFile(for item: ClipboardItem) {
        guard let filename = item.textFilename else { return }
        deleteText(named: filename)
    }

    func deleteText(named filename: String) {
        fullTextCache.removeObject(forKey: filename as NSString)
        guard let url = try? assetURL(for: filename) else {
            BufferLogger.persistence.error("Rejected invalid text asset filename")
            return
        }
        removeItemIfPresent(at: url, label: "text")
    }

    private func fileSize(at url: URL) -> Int? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int
        } catch {
            BufferLogger.persistence.error(
                "Failed to read file size at \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    private func cache(_ text: String, filename: String) {
        let cost = text.utf8.count
        guard cost <= CachePolicy.maximumEntryCost else { return }
        fullTextCache.setObject(
            text as NSString,
            forKey: filename as NSString,
            cost: cost
        )
    }

    private func removeItemIfPresent(at url: URL, label: String) {
        guard fileManager.fileExists(atPath: url.path) else { return }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            BufferLogger.persistence.error(
                "Failed to remove \(label, privacy: .public) file \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func closeBestEffort(_ handle: FileHandle) {
        do {
            try handle.close()
        } catch {
            BufferLogger.persistence.error(
                "Failed to close text asset handle: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func removeTemporaryFileBestEffort(at url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            BufferLogger.persistence.error(
                "Failed to remove temporary text asset: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func fingerprint(fileDescriptor: Int32) throws -> ClipboardSearchAssetFingerprint {
        var fileStatus = stat()
        guard fstat(fileDescriptor, &fileStatus) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var identifierEncoder = ClipboardLengthPrefixedBinaryEncoder()
        identifierEncoder.appendFixedWidth(UInt64(fileStatus.st_dev))
        identifierEncoder.appendFixedWidth(UInt64(fileStatus.st_ino))
        let nanoseconds =
            Int64(fileStatus.st_mtimespec.tv_sec) * 1_000_000_000
            + Int64(fileStatus.st_mtimespec.tv_nsec)
        return ClipboardSearchAssetFingerprint(
            fileIdentity: identifierEncoder.data,
            byteCount: Int64(fileStatus.st_size),
            modificationNanoseconds: nanoseconds
        )
    }

    private func assetURL(for filename: String) throws -> URL {
        guard let filename = ClipboardAssetFilename(rawValue: filename) else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return directory.appendingPathComponent(filename.rawValue)
    }
}
