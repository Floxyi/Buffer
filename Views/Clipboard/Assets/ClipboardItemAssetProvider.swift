import AppKit

@MainActor
protocol ClipboardItemAssetProviding: AnyObject {
    func cachedThumbnail(for item: ClipboardItem, leadingVisualSize: CGFloat) -> NSImage?
    func loadThumbnail(for item: ClipboardItem, leadingVisualSize: CGFloat) async -> NSImage?
    func cachedImageDimensionsText(for item: ClipboardItem) -> String?
    func loadImageDimensionsText(for item: ClipboardItem) async -> String?
    func cachedPreviewImage(for item: ClipboardItem) -> NSImage?
    func loadPreviewImage(for item: ClipboardItem) async -> NSImage?
    func loadFullText(for item: ClipboardItem) async -> String?
    func loadTextChunk(for item: ClipboardItem, charCount: Int) async -> ClipboardTextChunk?
    func loadItemSize(for item: ClipboardItem) async -> Int?
    func cachedLeadingIcon(for item: ClipboardItem) -> NSImage?
    func loadApplicationIcon(for item: ClipboardItem) async -> NSImage?
    func loadPreferredLeadingIcon(for item: ClipboardItem) async -> NSImage?
    func prewarmImageAssets(
        for items: [ClipboardItem],
        leadingVisualSize: CGFloat,
        limit: Int
    ) async
}

@MainActor
final class ClipboardItemAssetProvider: ClipboardItemAssetProviding {
    private let store: ClipboardStore
    private let settings: SettingsManager

    init(store: ClipboardStore, settings: SettingsManager) {
        self.store = store
        self.settings = settings
    }

    func cachedThumbnail(for item: ClipboardItem, leadingVisualSize: CGFloat) -> NSImage? {
        ClipboardImageAssetLoader.cachedThumbnail(
            for: item,
            leadingVisualSize: leadingVisualSize
        )
    }

    func loadThumbnail(for item: ClipboardItem, leadingVisualSize: CGFloat) async -> NSImage? {
        await ClipboardImageAssetLoader.loadThumbnail(
            for: item,
            store: store,
            leadingVisualSize: leadingVisualSize
        )
    }

    func cachedImageDimensionsText(for item: ClipboardItem) -> String? {
        ClipboardImageAssetLoader.cachedImageDimensionsText(for: item)
    }

    func loadImageDimensionsText(for item: ClipboardItem) async -> String? {
        await ClipboardImageAssetLoader.loadImageDimensionsText(for: item, store: store)
    }

    func cachedPreviewImage(for item: ClipboardItem) -> NSImage? {
        ClipboardImageAssetLoader.cachedPreviewImage(for: item)
    }

    func loadPreviewImage(for item: ClipboardItem) async -> NSImage? {
        await ClipboardImageAssetLoader.loadPreviewImage(for: item, store: store)
    }

    func loadFullText(for item: ClipboardItem) async -> String? {
        await store.fullTextAsync(for: item)
    }

    func loadTextChunk(for item: ClipboardItem, charCount: Int) async -> ClipboardTextChunk? {
        await store.textChunkAsync(for: item, charCount: charCount)
    }

    func loadItemSize(for item: ClipboardItem) async -> Int? {
        await store.itemSizeAsync(for: item)
    }

    func cachedLeadingIcon(for item: ClipboardItem) -> NSImage? {
        ClipboardItemIconLoader.cachedLeadingIcon(
            for: item,
            settings: settings
        )
    }

    func loadApplicationIcon(for item: ClipboardItem) async -> NSImage? {
        await ClipboardItemIconLoader.loadApplicationIcon(for: item)
    }

    func loadPreferredLeadingIcon(for item: ClipboardItem) async -> NSImage? {
        await ClipboardItemIconLoader.loadPreferredLeadingIcon(
            for: item,
            settings: settings
        )
    }

    func prewarmImageAssets(
        for items: [ClipboardItem],
        leadingVisualSize: CGFloat,
        limit: Int
    ) async {
        await ClipboardImageAssetLoader.prewarmVisibleImages(
            for: items,
            store: store,
            leadingVisualSize: leadingVisualSize,
            limit: limit
        )
    }
}
