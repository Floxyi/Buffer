import AppKit

@MainActor
enum ClipboardImageAssetLoader {
    private final class ImageValue: @unchecked Sendable {
        let image: NSImage

        init(_ image: NSImage) {
            self.image = image
        }
    }

    private struct ActiveLoad<Value: Sendable> {
        let id: UUID
        let task: Task<Value?, Never>
    }

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
    private static var activeThumbnailLoads: [String: ActiveLoad<ImageValue>] = [:]
    private static var activePreviewLoads: [String: ActiveLoad<ImageValue>] = [:]
    private static var activeDimensionsLoads: [UUID: ActiveLoad<String>] = [:]

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

        if let activeLoad = activeThumbnailLoads[key] {
            let value = await activeLoad.task.value
            return Task.isCancelled ? nil : value?.image
        }

        let loadID = UUID()
        let task: Task<ImageValue?, Never> = Task { @MainActor in
            guard !Task.isCancelled,
                let thumbnail = await store.thumbnailAsync(for: item, maxPixelSize: pixelSize),
                !Task.isCancelled
            else { return nil }

            thumbnailCache.setObject(thumbnail, forKey: key as NSString)
            return ImageValue(thumbnail)
        }
        activeThumbnailLoads[key] = ActiveLoad(id: loadID, task: task)
        let value = await task.value
        if activeThumbnailLoads[key]?.id == loadID {
            activeThumbnailLoads.removeValue(forKey: key)
        }
        return Task.isCancelled ? nil : value?.image
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

        if let activeLoad = activePreviewLoads[filename] {
            let value = await activeLoad.task.value
            return Task.isCancelled ? nil : value?.image
        }

        let loadID = UUID()
        let task: Task<ImageValue?, Never> = Task { @MainActor in
            guard !Task.isCancelled,
                let image = await store.imageAsync(for: item),
                !Task.isCancelled
            else { return nil }

            previewImageCache.setObject(image, forKey: filename as NSString)
            return ImageValue(image)
        }
        activePreviewLoads[filename] = ActiveLoad(id: loadID, task: task)
        let value = await task.value
        if activePreviewLoads[filename]?.id == loadID {
            activePreviewLoads.removeValue(forKey: filename)
        }
        return Task.isCancelled ? nil : value?.image
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

        if let activeLoad = activeDimensionsLoads[item.id] {
            let dimensionsText = await activeLoad.task.value
            return Task.isCancelled ? nil : dimensionsText
        }

        let loadID = UUID()
        let task: Task<String?, Never> = Task { @MainActor in
            guard !Task.isCancelled,
                let dimensionsText = await store.imageDimensionsAsync(for: item),
                !Task.isCancelled
            else { return nil }

            imageDimensionsTextCache[item.id] = dimensionsText
            return dimensionsText
        }
        activeDimensionsLoads[item.id] = ActiveLoad(id: loadID, task: task)
        let dimensionsText = await task.value
        if activeDimensionsLoads[item.id]?.id == loadID {
            activeDimensionsLoads.removeValue(forKey: item.id)
        }
        return Task.isCancelled ? nil : dimensionsText
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
        for load in activeThumbnailLoads.values {
            load.task.cancel()
        }
        for load in activePreviewLoads.values {
            load.task.cancel()
        }
        for load in activeDimensionsLoads.values {
            load.task.cancel()
        }
        activeThumbnailLoads.removeAll()
        activePreviewLoads.removeAll()
        activeDimensionsLoads.removeAll()
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
