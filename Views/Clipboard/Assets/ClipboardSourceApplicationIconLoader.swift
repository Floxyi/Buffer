import AppKit
import Foundation

private final class ClipboardResolvedApplicationIcon: @unchecked Sendable {
    let image: NSImage?

    init(_ image: NSImage?) {
        self.image = image
    }
}

@MainActor
enum ClipboardSourceApplicationIconLoader {
    private static let sourceIconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 120
        return cache
    }()

    private static var missingSourceIconKeys = Set<String>()
    private static var inFlightLocalIconLoads: [String: Task<ClipboardResolvedApplicationIcon, Never>] = [:]
    private static let applicationIconDiskStore: ClipboardIconDiskStore = {
        let cachesDirectory =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return ClipboardIconDiskStore(
            directory: cachesDirectory
                .appendingPathComponent("Buffer", isDirectory: true)
                .appendingPathComponent("ApplicationIcons", isDirectory: true)
        )
    }()

    static func loadSourceApplicationIcon(
        for item: ClipboardItem,
        settings: SettingsManager
    ) async -> NSImage? {
        guard item.kind != .email else { return nil }

        if let cachedIcon = cachedSourceApplicationIcon(for: item, settings: settings) {
            return cachedIcon
        }

        if item.kind == .link {
            guard settings.enableWebsitePreviews else {
                return nil
            }

            return await ClipboardWebsiteIconLoader.loadWebsiteIcon(for: item)
        }

        return await loadLocalSourceApplicationIcon(for: item, settings: settings)
    }

    /// Resolves only the capturing application's icon. Link rows use this as their
    /// stable fallback while their independently keyed favicon request is pending.
    static func loadLocalSourceApplicationIcon(
        for item: ClipboardItem,
        settings: SettingsManager
    ) async -> NSImage? {
        guard item.kind != .email else { return nil }

        guard let key = sourceIconCacheKey(for: item) else {
            return nil
        }

        if let cachedIcon = sourceIconCache.object(forKey: key as NSString) {
            return cachedIcon
        }

        if missingSourceIconKeys.contains(key) {
            return nil
        }

        if let inFlight = inFlightLocalIconLoads[key] {
            return await inFlight.value.image
        }

        let task = Task { @MainActor in
            if let data = await applicationIconDiskStore.loadData(forKey: key),
               let persistedImage = await ClipboardIconImageCodec.decode(data).image {
                persistedImage.size = NSSize(width: 14, height: 14)
                return ClipboardResolvedApplicationIcon(persistedImage)
            }

            let resolved = ClipboardResolvedApplicationIcon(
                await loadSourceApplicationIconWithoutCache(for: item)
            )
            if resolved.image != nil,
               let data = await ClipboardIconImageCodec.pngData(
                    from: ClipboardIconImageValue(resolved.image)
               ) {
                await applicationIconDiskStore.store(data, forKey: key)
            }
            return resolved
        }
        inFlightLocalIconLoads[key] = task
        let iconImage = await task.value.image
        inFlightLocalIconLoads[key] = nil
        guard let iconImage else {
            missingSourceIconKeys.insert(key)
            return nil
        }

        sourceIconCache.setObject(iconImage, forKey: key as NSString)
        missingSourceIconKeys.remove(key)
        return iconImage
    }

    static func cachedSourceApplicationIcon(
        for item: ClipboardItem,
        settings: SettingsManager
    ) -> NSImage? {
        guard item.kind != .email else { return nil }

        if item.kind == .link {
            guard settings.enableWebsitePreviews,
                let url = item.linkPayload?.url
            else {
                return nil
            }

            return ClipboardWebsiteIconLoader.cachedWebsiteIcon(for: url)
        }

        return cachedLocalSourceApplicationIcon(for: item)
    }

    static func cachedDisplayIcon(
        for item: ClipboardItem,
        settings: SettingsManager
    ) -> NSImage? {
        guard item.kind != .email else { return nil }

        if item.kind == .link {
            if settings.enableWebsitePreviews,
                let url = item.linkPayload?.url,
                let websiteIcon = ClipboardWebsiteIconLoader.cachedWebsiteIcon(for: url)
            {
                return websiteIcon
            }
        }

        return cachedLocalSourceApplicationIcon(for: item)
    }

    static func prewarmSourceIcons(
        for items: [ClipboardItem],
        settings: SettingsManager,
        limit: Int = 40
    ) async {
        var seenKeys = Set<String>()
        var candidates: [ClipboardItem] = []

        for item in items {
            if Task.isCancelled {
                return
            }

            guard item.kind != .email else { continue }

            let key: String
            if item.kind == .link {
                guard settings.enableWebsitePreviews,
                    let websiteKey = websiteIconCacheKey(for: item)
                else {
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

                if ClipboardWebsiteIconLoader.cachedWebsiteIcon(for: url) != nil
                    || ClipboardWebsiteIconLoader.hasMissingWebsiteIcon(for: url)
                {
                    continue
                }
            } else if sourceIconCache.object(forKey: key as NSString) != nil || missingSourceIconKeys.contains(key) {
                continue
            }

            candidates.append(item)
            if candidates.count >= limit {
                break
            }
        }

        let maximumConcurrentLoads = 8
        var batchStart = 0
        while batchStart < candidates.count, !Task.isCancelled {
            let batchEnd = min(candidates.count, batchStart + maximumConcurrentLoads)
            let batch = Array(candidates[batchStart..<batchEnd])

            let tasks = batch.map { item in
                Task { @MainActor in
                    _ = await loadSourceApplicationIcon(for: item, settings: settings)
                }
            }
            for task in tasks {
                await task.value
            }

            batchStart = batchEnd
        }
    }

    static func prewarmLocalSourceIcons(
        for items: [ClipboardItem],
        settings: SettingsManager,
        limit: Int = 80
    ) async {
        var seenKeys = Set<String>()
        var candidates: [ClipboardItem] = []
        for item in items {
            guard let key = sourceIconCacheKey(for: item), seenKeys.insert(key).inserted else {
                continue
            }
            candidates.append(item)
            if candidates.count >= limit { break }
        }

        for item in candidates {
            guard !Task.isCancelled else { return }
            _ = await loadLocalSourceApplicationIcon(for: item, settings: settings)
        }
    }

    static func clearCaches() {
        clearSourceApplicationIconCache()
        ClipboardWebsiteIconLoader.clear()
    }

    static func clearSourceApplicationIconCache() {
        for task in inFlightLocalIconLoads.values {
            task.cancel()
        }
        inFlightLocalIconLoads.removeAll()
        sourceIconCache.removeAllObjects()
        missingSourceIconKeys.removeAll()
    }

    static func sourceIconCacheKey(for item: ClipboardItem) -> String? {
        if let bundlePath = item.sourceAppBundlePath, !bundlePath.isEmpty {
            return "path:\(bundlePath)"
        }

        if let bundleIdentifier = item.sourceAppBundleIdentifier, !bundleIdentifier.isEmpty {
            return "bundle:\(bundleIdentifier)"
        }

        return nil
    }

    static func websiteIconCacheKey(for item: ClipboardItem) -> String? {
        item.linkPayload?.url.host.map { "website:\($0.lowercased())" }
    }

    private static func loadSourceApplicationIconWithoutCache(for item: ClipboardItem) async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let resolvedIcon: NSImage?

                if let bundlePath = item.sourceAppBundlePath, !bundlePath.isEmpty {
                    resolvedIcon = NSWorkspace.shared.icon(forFile: bundlePath)
                } else if let bundleIdentifier = item.sourceAppBundleIdentifier,
                    let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
                {
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

    private static func cachedLocalSourceApplicationIcon(for item: ClipboardItem) -> NSImage? {
        guard let key = sourceIconCacheKey(for: item) else {
            return nil
        }

        return sourceIconCache.object(forKey: key as NSString)
    }
}
