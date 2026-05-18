import AppKit
@preconcurrency import LinkPresentation
import SwiftUI

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
enum LinkPreviewAssetCache {
    private static var metadataCache: [URL: LPLinkMetadata] = [:]
    private static var metadataWaiters: [URL: [CheckedContinuation<UnsafeLinkMetadataBox, Never>]] = [:]
    private static var activeMetadataProviders: [URL: LPMetadataProvider] = [:]
    private static let websiteIconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 240
        return cache
    }()
    private static var missingWebsiteIconKeys = Set<String>()

    static func metadata(for url: URL) async -> LPLinkMetadata? {
        if let cachedMetadata = metadataCache[url] {
            return cachedMetadata
        }

        if metadataWaiters[url] != nil {
            let metadataBox = await withCheckedContinuation { continuation in
                metadataWaiters[url, default: []].append(continuation)
            }
            return metadataBox.value
        }

        metadataWaiters[url] = []

        let metadataBox = await withCheckedContinuation { continuation in
            metadataWaiters[url, default: []].append(continuation)

            let provider = LPMetadataProvider()
            activeMetadataProviders[url] = provider

            provider.startFetchingMetadata(for: url) { metadata, error in
                let metadataBox = UnsafeLinkMetadataBox(value: metadata)

                Task { @MainActor in
                    let continuations = metadataWaiters.removeValue(forKey: url) ?? []
                    activeMetadataProviders[url] = nil

                    if let metadata = metadataBox.value {
                        metadataCache[url] = metadata
                        await cacheWebsiteIcon(from: metadata, for: url)

                        continuations.forEach { $0.resume(returning: UnsafeLinkMetadataBox(value: metadata)) }
                    } else {
                        BufferLogger.ui.error("Failed to fetch link metadata for \(url.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)")
                        continuations.forEach { $0.resume(returning: UnsafeLinkMetadataBox(value: nil)) }
                    }
                }
            }
        }

        return metadataBox.value
    }

    static func cachedWebsiteIcon(for url: URL) -> NSImage? {
        guard let key = websiteIconCacheKey(for: url) else {
            return nil
        }

        return websiteIconCache.object(forKey: key as NSString)
    }

    static func storeWebsiteIcon(_ image: NSImage, for url: URL) {
        guard let key = websiteIconCacheKey(for: url) else {
            return
        }

        websiteIconCache.setObject(normalizedWebsiteIcon(from: image), forKey: key as NSString)
        missingWebsiteIconKeys.remove(key)
    }

    static func hasMissingWebsiteIcon(for url: URL) -> Bool {
        guard let key = websiteIconCacheKey(for: url) else {
            return false
        }

        return missingWebsiteIconKeys.contains(key)
    }

    static func markWebsiteIconMissing(for url: URL) {
        guard let key = websiteIconCacheKey(for: url) else {
            return
        }

        missingWebsiteIconKeys.insert(key)
    }

    static func clear() {
        metadataCache.removeAll()
        let pendingURLs = Array(metadataWaiters.keys)
        for url in pendingURLs {
            let continuations = metadataWaiters.removeValue(forKey: url) ?? []
            continuations.forEach { $0.resume(returning: UnsafeLinkMetadataBox(value: nil)) }
        }
        activeMetadataProviders.removeAll()
        websiteIconCache.removeAllObjects()
        missingWebsiteIconKeys.removeAll()
    }

    private static func cacheWebsiteIcon(from metadata: LPLinkMetadata, for url: URL) async {
        guard cachedWebsiteIcon(for: url) == nil,
              let iconImage = await loadImage(from: metadata.iconProvider) else {
            return
        }

        storeWebsiteIcon(iconImage, for: url)
    }

    private static func loadImage(from itemProvider: NSItemProvider?) async -> NSImage? {
        guard let itemProvider else {
            return nil
        }

        guard itemProvider.canLoadObject(ofClass: NSImage.self) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            itemProvider.loadObject(ofClass: NSImage.self) { object, _ in
                continuation.resume(returning: object as? NSImage)
            }
        }
    }

    private static func websiteIconCacheKey(for url: URL) -> String? {
        url.host.map { "website:\($0.lowercased())" }
    }

    private static func normalizedWebsiteIcon(from image: NSImage) -> NSImage {
        let iconCopy = image.copy() as? NSImage ?? image
        iconCopy.size = NSSize(width: 16, height: 16)
        return iconCopy
    }
}

private struct UnsafeLinkMetadataBox: @unchecked Sendable {
    let value: LPLinkMetadata?
}

@MainActor
enum ClipboardItemRowAssetLoader {
    private static let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 500
        return cache
    }()

    private static let sourceIconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 120
        return cache
    }()

    private static var imageDimensionsTextCache: [UUID: String] = [:]
    private static var missingSourceIconKeys = Set<String>()

    static func loadAssets(
        for item: ClipboardItem,
        store: ClipboardStore,
        settings: SettingsManager,
        leadingVisualSize: CGFloat
    ) async -> ClipboardItemRowAssets {
        let thumbnail: NSImage?
        let imageDimensionsText: String?

        if ClipboardItemTypeRegistry.supportsImageAssets(for: item) {
            thumbnail = await loadThumbnail(
                for: item,
                store: store,
                leadingVisualSize: leadingVisualSize
            )

            imageDimensionsText = await loadImageDimensionsText(
                for: item,
                store: store
            )
        } else {
            thumbnail = nil
            imageDimensionsText = nil
        }

        let sourceAppIcon = await loadSourceApplicationIcon(for: item, settings: settings)

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

    static func loadSourceApplicationIcon(for item: ClipboardItem, settings: SettingsManager) async -> NSImage? {
        if item.kind == .link {
            guard settings.enableWebsitePreviews else {
                return nil
            }

            return await loadWebsiteIcon(for: item)
        }

        guard let key = sourceIconCacheKey(for: item) else {
            return nil
        }

        if let cachedIcon = sourceIconCache.object(forKey: key as NSString) {
            return cachedIcon
        }

        if missingSourceIconKeys.contains(key) {
            return nil
        }

        let iconImage = await loadSourceApplicationIconWithoutCache(for: item)

        guard let iconImage else {
            missingSourceIconKeys.insert(key)
            return nil
        }

        sourceIconCache.setObject(iconImage, forKey: key as NSString)
        missingSourceIconKeys.remove(key)

        return iconImage
    }

    static func prewarmSourceIcons(
        for items: [ClipboardItem],
        settings: SettingsManager,
        limit: Int = 40
    ) async {
        var seenKeys = Set<String>()
        var loadedCount = 0

        for item in items {
            if Task.isCancelled {
                return
            }

            let key: String
            if item.kind == .link {
                guard settings.enableWebsitePreviews,
                      let websiteKey = websiteIconCacheKey(for: item) else {
                    continue
                }
                key = websiteKey
            } else {
                guard let sourceKey = sourceIconCacheKey(for: item) else {
                    continue
                }
                key = sourceKey
            }

            guard seenKeys.insert(key).inserted else {
                continue
            }

            if item.kind == .link {
                guard let url = item.linkPayload?.url else {
                    continue
                }

                if LinkPreviewAssetCache.cachedWebsiteIcon(for: url) != nil ||
                    LinkPreviewAssetCache.hasMissingWebsiteIcon(for: url) {
                    continue
                }
            } else {
                if sourceIconCache.object(forKey: key as NSString) != nil || missingSourceIconKeys.contains(key) {
                    continue
                }
            }

            _ = await loadSourceApplicationIcon(for: item, settings: settings)

            loadedCount += 1
            if loadedCount >= limit {
                return
            }
        }
    }

    static func clearCaches() {
        thumbnailCache.removeAllObjects()
        sourceIconCache.removeAllObjects()
        imageDimensionsTextCache.removeAll()
        missingSourceIconKeys.removeAll()
        LinkPreviewAssetCache.clear()
    }

    static func clearSourceApplicationIconCache() {
        sourceIconCache.removeAllObjects()
        missingSourceIconKeys.removeAll()
    }

    static func removeCachedAssets(for itemID: UUID) {
        imageDimensionsTextCache.removeValue(forKey: itemID)
    }

    private static func thumbnailCacheKey(for item: ClipboardItem, pixelSize: CGFloat) -> String {
        "\(item.id.uuidString)-\(Int(pixelSize.rounded()))"
    }

    private static func sourceIconCacheKey(for item: ClipboardItem) -> String? {
        if let bundlePath = item.sourceAppBundlePath, !bundlePath.isEmpty {
            return "path:\(bundlePath)"
        }

        if let bundleIdentifier = item.sourceAppBundleIdentifier, !bundleIdentifier.isEmpty {
            return "bundle:\(bundleIdentifier)"
        }

        return nil
    }

    private static func websiteIconCacheKey(for item: ClipboardItem) -> String? {
        item.linkPayload?.url.host.map { "website:\($0.lowercased())" }
    }

    private static func loadSourceApplicationIconWithoutCache(for item: ClipboardItem) async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let resolvedIcon: NSImage?

                if let bundlePath = item.sourceAppBundlePath, !bundlePath.isEmpty {
                    resolvedIcon = NSWorkspace.shared.icon(forFile: bundlePath)
                } else if let bundleIdentifier = item.sourceAppBundleIdentifier,
                          let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                    resolvedIcon = NSWorkspace.shared.icon(forFile: appURL.path)
                } else {
                    resolvedIcon = nil
                }

                guard let resolvedIcon else {
                    continuation.resume(returning: nil)
                    return
                }

                let iconCopy = resolvedIcon.copy() as? NSImage ?? resolvedIcon
                iconCopy.size = NSSize(width: 14, height: 14)

                continuation.resume(returning: iconCopy)
            }
        }
    }

    private static func loadWebsiteIcon(for item: ClipboardItem) async -> NSImage? {
        guard let url = item.linkPayload?.url else {
            return nil
        }

        if let cachedIcon = LinkPreviewAssetCache.cachedWebsiteIcon(for: url) {
            return cachedIcon
        }

        if LinkPreviewAssetCache.hasMissingWebsiteIcon(for: url) {
            return nil
        }

        guard let iconURL = faviconURL(for: item) else {
            return nil
        }

        var request = URLRequest(url: iconURL)
        request.timeoutInterval = 5
        request.cachePolicy = .returnCacheDataElseLoad

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let iconImage = NSImage(data: data) else {
                LinkPreviewAssetCache.markWebsiteIconMissing(for: url)
                return nil
            }

            LinkPreviewAssetCache.storeWebsiteIcon(iconImage, for: url)
            return LinkPreviewAssetCache.cachedWebsiteIcon(for: url)
        } catch {
            LinkPreviewAssetCache.markWebsiteIconMissing(for: url)
            return nil
        }
    }

    private static func faviconURL(for item: ClipboardItem) -> URL? {
        guard let url = item.linkPayload?.url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme,
              scheme == "http" || scheme == "https",
              components.host != nil else {
            return nil
        }

        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
