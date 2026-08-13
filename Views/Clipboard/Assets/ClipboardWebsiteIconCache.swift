import AppKit
import Foundation

private final class ClipboardWebsiteIconImageValue: @unchecked Sendable {
    let image: NSImage?

    init(_ image: NSImage?) {
        self.image = image
    }
}

private enum ClipboardWebsiteIconImageCodec {
    nonisolated static func decode(_ data: Data) async -> ClipboardWebsiteIconImageValue {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: ClipboardWebsiteIconImageValue(NSImage(data: data)))
            }
        }
    }

    nonisolated static func pngData(from value: ClipboardWebsiteIconImageValue) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard let image = value.image,
                    let tiffData = image.tiffRepresentation,
                    let representation = NSBitmapImageRep(data: tiffData)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: representation.representation(using: .png, properties: [:])
                )
            }
        }
    }
}

@MainActor
enum ClipboardWebsiteIconCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 240
        return cache
    }()

    private static var missingKeys = Set<String>()
    private static var diskStore = ClipboardWebsiteIconDiskStore.defaultStore()
    private static var hasHydratedPersistedIcons = false

    static func cachedIcon(for url: URL) -> NSImage? {
        guard let key = cacheKey(for: url) else {
            return nil
        }

        return cache.object(forKey: key as NSString)
    }

    static func hasMarkedMissingIcon(for url: URL) -> Bool {
        guard let key = cacheKey(for: url) else {
            return false
        }

        return missingKeys.contains(key)
    }

    static func markMissing(for url: URL) {
        guard let key = cacheKey(for: url) else {
            return
        }

        missingKeys.insert(key)
    }

    static func store(_ image: NSImage, for url: URL) {
        guard let key = cacheKey(for: url) else {
            return
        }

        let normalizedImage = normalizedIcon(from: image)
        cache.setObject(normalizedImage, forKey: key as NSString)
        missingKeys.remove(key)

        let currentDiskStore = diskStore
        Task {
            guard
                let data = await ClipboardWebsiteIconImageCodec.pngData(
                    from: ClipboardWebsiteIconImageValue(normalizedImage)
                )
            else { return }
            await currentDiskStore.store(data, forKey: key)
        }
    }

    static func hydratePersistedIcons(limit: Int = 240) async {
        guard !hasHydratedPersistedIcons else {
            return
        }

        let entries = await diskStore.loadAll(limit: limit)
        for entry in entries {
            guard let image = await ClipboardWebsiteIconImageCodec.decode(entry.data).image else {
                continue
            }

            cache.setObject(normalizedIcon(from: image), forKey: entry.key as NSString)
        }
        hasHydratedPersistedIcons = true
    }

    static func loadPersistedIcon(for url: URL) async -> NSImage? {
        guard let key = cacheKey(for: url),
            let data = await diskStore.loadData(forKey: key),
            let image = await ClipboardWebsiteIconImageCodec.decode(data).image
        else {
            return nil
        }

        let normalizedImage = normalizedIcon(from: image)
        cache.setObject(normalizedImage, forKey: key as NSString)
        missingKeys.remove(key)
        return normalizedImage
    }

    static func clear() {
        cache.removeAllObjects()
        missingKeys.removeAll()
    }

    static func configureDiskStoreForTesting(directory: URL) {
        diskStore = ClipboardWebsiteIconDiskStore(directory: directory)
        hasHydratedPersistedIcons = false
        clear()
    }

    private static func cacheKey(for url: URL) -> String? {
        url.host.map { "website:\($0.lowercased())" }
    }

    private static func normalizedIcon(from image: NSImage) -> NSImage {
        let iconCopy = image.copy() as? NSImage ?? image

        if let idealSize = preferredIconSize(for: iconCopy) {
            iconCopy.size = idealSize
        }

        return iconCopy
    }

    private static func preferredIconSize(for image: NSImage) -> NSSize? {
        let bitmapRepresentations = image.representations.compactMap { $0 as? NSBitmapImageRep }

        if let largestRepresentation = bitmapRepresentations.max(by: {
            ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh)
        }) {
            return scaledIconSize(
                width: CGFloat(largestRepresentation.pixelsWide),
                height: CGFloat(largestRepresentation.pixelsHigh)
            )
        }

        guard image.size.width > 0, image.size.height > 0 else {
            return nil
        }

        return scaledIconSize(width: image.size.width, height: image.size.height)
    }

    private static func scaledIconSize(width: CGFloat, height: CGFloat) -> NSSize {
        let maxDimension: CGFloat = 128
        let currentMaxDimension = max(width, height)
        guard currentMaxDimension > maxDimension else {
            return NSSize(width: width, height: height)
        }

        let scale = maxDimension / currentMaxDimension
        return NSSize(width: width * scale, height: height * scale)
    }

}

struct ClipboardWebsiteIconDiskEntry: Sendable {
    let key: String
    let data: Data
}

actor ClipboardWebsiteIconDiskStore {
    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    static func defaultStore() -> ClipboardWebsiteIconDiskStore {
        let cachesDirectory =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return ClipboardWebsiteIconDiskStore(
            directory:
                cachesDirectory
                .appendingPathComponent("Buffer", isDirectory: true)
                .appendingPathComponent("WebsiteIcons", isDirectory: true)
        )
    }

    func store(_ data: Data, forKey key: String) {
        do {
            try createDirectoryIfNeeded()
            try data.write(to: fileURL(forKey: key), options: .atomic)
        } catch {
            BufferLogger.persistence.error(
                "Failed to persist website icon for \(key, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func loadData(forKey key: String) -> Data? {
        try? Data(contentsOf: fileURL(forKey: key))
    }

    func loadAll(limit: Int) -> [ClipboardWebsiteIconDiskEntry] {
        guard limit > 0,
            let fileURLs = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        return
            fileURLs
            .filter { $0.pathExtension == "png" }
            .sorted { lhs, rhs in
                let lhsDate = try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let rhsDate = try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return (lhsDate ?? .distantPast) > (rhsDate ?? .distantPast)
            }
            .prefix(limit)
            .compactMap { fileURL in
                guard let key = Self.cacheKey(from: fileURL),
                    let data = try? Data(contentsOf: fileURL)
                else {
                    return nil
                }

                return ClipboardWebsiteIconDiskEntry(key: key, data: data)
            }
    }

    private func createDirectoryIfNeeded() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    private func fileURL(forKey key: String) -> URL {
        directory.appendingPathComponent(Self.fileName(forKey: key))
    }

    nonisolated static func fileName(forKey key: String) -> String {
        let encodedKey = Data(key.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(encodedKey).png"
    }

    nonisolated static func cacheKey(from fileURL: URL) -> String? {
        var encodedKey = fileURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let paddingCount = (4 - encodedKey.count % 4) % 4
        encodedKey.append(String(repeating: "=", count: paddingCount))

        guard let data = Data(base64Encoded: encodedKey) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}
