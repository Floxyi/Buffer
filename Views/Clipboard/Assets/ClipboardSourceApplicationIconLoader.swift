import AppKit
import Foundation

@MainActor
enum ClipboardSourceApplicationIconLoader {
    private static let sourceIconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 120
        return cache
    }()

    private static var missingSourceIconKeys = Set<String>()

    static func loadSourceApplicationIcon(
        for item: ClipboardItem,
        settings: SettingsManager
    ) async -> NSImage? {
        if item.kind == .link {
            guard settings.enableWebsitePreviews else {
                return nil
            }

            return await ClipboardWebsiteIconLoader.loadWebsiteIcon(for: item)
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

                if ClipboardWebsiteIconLoader.cachedWebsiteIcon(for: url) != nil ||
                    ClipboardWebsiteIconLoader.hasMissingWebsiteIcon(for: url) {
                    continue
                }
            } else if sourceIconCache.object(forKey: key as NSString) != nil || missingSourceIconKeys.contains(key) {
                continue
            }

            _ = await loadSourceApplicationIcon(for: item, settings: settings)

            loadedCount += 1
            if loadedCount >= limit {
                return
            }
        }
    }

    static func clearCaches() {
        clearSourceApplicationIconCache()
        ClipboardWebsiteIconLoader.clear()
    }

    static func clearSourceApplicationIconCache() {
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
}
