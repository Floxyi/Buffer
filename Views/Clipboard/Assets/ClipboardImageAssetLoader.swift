import AppKit

@MainActor
enum ClipboardImageAssetLoader {
    private static let defaultThumbnailScale = CGFloat(2)
    private static let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 500
        return cache
    }()

    private static var imageDimensionsTextCache: [UUID: String] = [:]
    private static let previewImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 128
        return cache
    }()

    static func loadThumbnail(
        for item: ClipboardItem,
        store: ClipboardStore,
        leadingVisualSize: CGFloat
    ) async -> NSImage? {
        let token = BufferPerformanceDiagnostics.begin(.thumbnailLoad)
        defer { BufferPerformanceDiagnostics.end(token) }

        let pixelSize = thumbnailPixelSize(for: leadingVisualSize)
        let key = thumbnailCacheKey(for: item, pixelSize: pixelSize)

        if let cachedThumbnail = thumbnailCache.object(forKey: key as NSString) {
            return cachedThumbnail
        }

        guard !Task.isCancelled,
            let thumbnail = await store.thumbnailAsync(for: item, maxPixelSize: pixelSize),
            !Task.isCancelled
        else {
            return nil
        }

        thumbnailCache.setObject(thumbnail, forKey: key as NSString)
        return thumbnail
    }

    static func cachedThumbnail(
        for item: ClipboardItem,
        leadingVisualSize: CGFloat
    ) -> NSImage? {
        let pixelSize = thumbnailPixelSize(for: leadingVisualSize)
        let key = thumbnailCacheKey(for: item, pixelSize: pixelSize)
        return thumbnailCache.object(forKey: key as NSString)
    }

    static func loadPreviewImage(
        for item: ClipboardItem,
        store: ClipboardStore
    ) async -> NSImage? {
        let token = BufferPerformanceDiagnostics.begin(.previewLoad)
        defer { BufferPerformanceDiagnostics.end(token) }

        guard let filename = item.imageFilename else {
            return nil
        }

        if let cachedImage = previewImageCache.object(forKey: filename as NSString) {
            return cachedImage
        }

        guard !Task.isCancelled,
            let image = await store.imageAsync(for: item),
            !Task.isCancelled
        else {
            return nil
        }

        previewImageCache.setObject(image, forKey: filename as NSString)
        return image
    }

    static func cachedPreviewImage(for item: ClipboardItem) -> NSImage? {
        guard let filename = item.imageFilename else {
            return nil
        }

        return previewImageCache.object(forKey: filename as NSString)
    }

    static func loadImageDimensionsText(
        for item: ClipboardItem,
        store: ClipboardStore
    ) async -> String? {
        if let cachedText = imageDimensionsTextCache[item.id] {
            return cachedText
        }

        guard !Task.isCancelled,
            let dimensionsText = await store.imageDimensionsAsync(for: item),
            !Task.isCancelled
        else {
            return nil
        }

        imageDimensionsTextCache[item.id] = dimensionsText
        return dimensionsText
    }

    static func cachedImageDimensionsText(for item: ClipboardItem) -> String? {
        imageDimensionsTextCache[item.id]
    }

    static func prewarmVisibleImages(
        for items: [ClipboardItem],
        store: ClipboardStore,
        leadingVisualSize: CGFloat,
        limit: Int = 48
    ) async {
        var loadedCount = 0

        for item in items where ClipboardItemTypeRegistry.supportsImageAssets(for: item) {
            if Task.isCancelled {
                return
            }

            if cachedThumbnail(for: item, leadingVisualSize: leadingVisualSize) == nil {
                _ = await loadThumbnail(for: item, store: store, leadingVisualSize: leadingVisualSize)
                loadedCount += 1
            }

            if Task.isCancelled {
                return
            }

            if cachedImageDimensionsText(for: item) == nil {
                _ = await loadImageDimensionsText(for: item, store: store)
            }

            if loadedCount >= limit {
                return
            }
        }
    }

    static func clearCaches() {
        thumbnailCache.removeAllObjects()
        previewImageCache.removeAllObjects()
        imageDimensionsTextCache.removeAll()
    }

    static func removeCachedAssets(for itemID: UUID) {
        imageDimensionsTextCache.removeValue(forKey: itemID)
    }

    static func thumbnailCacheKey(for item: ClipboardItem, pixelSize: CGFloat) -> String {
        "\(item.id.uuidString)-\(Int(pixelSize.rounded()))"
    }

    private static func thumbnailPixelSize(for leadingVisualSize: CGFloat) -> CGFloat {
        leadingVisualSize * defaultThumbnailScale
    }
}
