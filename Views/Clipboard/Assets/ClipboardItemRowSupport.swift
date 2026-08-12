import AppKit

struct ClipboardItemRowAssets {
    let thumbnail: NSImage?
    let sourceAppIcon: NSImage?
    let imageDimensionsText: String?

    static let empty = ClipboardItemRowAssets(
        thumbnail: nil,
        sourceAppIcon: nil,
        imageDimensionsText: nil
    )

    func shouldTreatAsLoaded(for item: ClipboardItem) -> Bool {
        switch item.kind {
        case .text, .color, .link:
            return true
        case .image:
            return thumbnail != nil || imageDimensionsText != nil
        }
    }
}

@MainActor
enum ClipboardItemRowAssetLoader {
    static func loadAssets(
        for item: ClipboardItem,
        store: ClipboardStore,
        settings: SettingsManager,
        leadingVisualSize: CGFloat
    ) async -> ClipboardItemRowAssets {
        let thumbnail: NSImage?
        let imageDimensionsText: String?

        if ClipboardItemTypeRegistry.supportsImageAssets(for: item) {
            thumbnail = await ClipboardImageAssetLoader.loadThumbnail(
                for: item,
                store: store,
                leadingVisualSize: leadingVisualSize
            )
            imageDimensionsText = await ClipboardImageAssetLoader.loadImageDimensionsText(
                for: item,
                store: store
            )
        } else {
            thumbnail = nil
            imageDimensionsText = nil
        }

        let sourceAppIcon = await ClipboardSourceApplicationIconLoader.loadSourceApplicationIcon(
            for: item,
            settings: settings
        )

        return ClipboardItemRowAssets(
            thumbnail: thumbnail,
            sourceAppIcon: sourceAppIcon,
            imageDimensionsText: imageDimensionsText
        )
    }

    static func loadThumbnail(
        for item: ClipboardItem,
        store: ClipboardStore,
        leadingVisualSize: CGFloat
    ) async -> NSImage? {
        await ClipboardImageAssetLoader.loadThumbnail(
            for: item,
            store: store,
            leadingVisualSize: leadingVisualSize
        )
    }

    static func cachedThumbnail(
        for item: ClipboardItem,
        leadingVisualSize: CGFloat
    ) -> NSImage? {
        ClipboardImageAssetLoader.cachedThumbnail(
            for: item,
            leadingVisualSize: leadingVisualSize
        )
    }

    static func loadImageDimensionsText(
        for item: ClipboardItem,
        store: ClipboardStore
    ) async -> String? {
        await ClipboardImageAssetLoader.loadImageDimensionsText(for: item, store: store)
    }

    static func cachedImageDimensionsText(for item: ClipboardItem) -> String? {
        ClipboardImageAssetLoader.cachedImageDimensionsText(for: item)
    }

    static func loadSourceApplicationIcon(
        for item: ClipboardItem,
        settings: SettingsManager
    ) async -> NSImage? {
        await ClipboardSourceApplicationIconLoader.loadSourceApplicationIcon(
            for: item,
            settings: settings
        )
    }

    static func cachedSourceApplicationIcon(
        for item: ClipboardItem,
        settings: SettingsManager
    ) -> NSImage? {
        ClipboardSourceApplicationIconLoader.cachedSourceApplicationIcon(
            for: item,
            settings: settings
        )
    }

    static func cachedDisplaySourceApplicationIcon(
        for item: ClipboardItem,
        settings: SettingsManager
    ) -> NSImage? {
        ClipboardSourceApplicationIconLoader.cachedDisplayIcon(
            for: item,
            settings: settings
        )
    }

    static func prewarmSourceIcons(
        for items: [ClipboardItem],
        settings: SettingsManager,
        limit: Int = 40
    ) async {
        await ClipboardSourceApplicationIconLoader.prewarmSourceIcons(
            for: items,
            settings: settings,
            limit: limit
        )
    }

    static func prewarmImageAssets(
        for items: [ClipboardItem],
        store: ClipboardStore,
        leadingVisualSize: CGFloat,
        limit: Int = 48
    ) async {
        await ClipboardImageAssetLoader.prewarmVisibleImages(
            for: items,
            store: store,
            leadingVisualSize: leadingVisualSize,
            limit: limit
        )
    }

    static func clearCaches() {
        ClipboardImageAssetLoader.clearCaches()
        ClipboardSourceApplicationIconLoader.clearCaches()
    }

    static func clearSourceApplicationIconCache() {
        ClipboardSourceApplicationIconLoader.clearSourceApplicationIconCache()
    }

    static func removeCachedAssets(for itemID: UUID) {
        ClipboardImageAssetLoader.removeCachedAssets(for: itemID)
    }
}
