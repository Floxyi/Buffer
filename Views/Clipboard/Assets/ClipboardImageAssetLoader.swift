import AppKit

@MainActor
enum ClipboardImageAssetLoader {
    private static let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 500
        return cache
    }()

    private static var imageDimensionsTextCache: [UUID: String] = [:]

    static func loadThumbnail(
        for item: ClipboardItem,
        store: ClipboardStore,
        leadingVisualSize: CGFloat
    ) async -> NSImage? {
        let pixelSize = leadingVisualSize * 2
        let key = thumbnailCacheKey(for: item, pixelSize: pixelSize)

        if let cachedThumbnail = thumbnailCache.object(forKey: key as NSString) {
            return cachedThumbnail
        }

        guard let thumbnail = store.thumbnail(for: item, maxPixelSize: pixelSize) else {
            return nil
        }

        thumbnailCache.setObject(thumbnail, forKey: key as NSString)
        return thumbnail
    }

    static func loadImageDimensionsText(
        for item: ClipboardItem,
        store: ClipboardStore
    ) async -> String? {
        if let cachedText = imageDimensionsTextCache[item.id] {
            return cachedText
        }

        guard let dimensionsText = store.imageDimensions(for: item) else {
            return nil
        }

        imageDimensionsTextCache[item.id] = dimensionsText
        return dimensionsText
    }

    static func clearCaches() {
        thumbnailCache.removeAllObjects()
        imageDimensionsTextCache.removeAll()
    }

    static func removeCachedAssets(for itemID: UUID) {
        imageDimensionsTextCache.removeValue(forKey: itemID)
    }

    static func thumbnailCacheKey(for item: ClipboardItem, pixelSize: CGFloat) -> String {
        "\(item.id.uuidString)-\(Int(pixelSize.rounded()))"
    }
}
