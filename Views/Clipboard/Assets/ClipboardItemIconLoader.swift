import AppKit
import Foundation

/// Resolves the icon shown by a clipboard row. Native application icons and
/// website icons intentionally retain separate loading and persistence policies.
@MainActor
enum ClipboardItemIconLoader {
    static func cachedLeadingIcon(
        for item: ClipboardItem,
        settings: SettingsManager,
        applicationIconLoader: ClipboardApplicationIconLoader = .shared
    ) -> NSImage? {
        guard item.kind != .email else { return nil }

        if item.kind == .link,
            settings.enableWebsitePreviews,
            let url = item.linkPayload?.url,
            let websiteIcon = ClipboardWebsiteIconLoader.cachedWebsiteIcon(for: url)
        {
            return websiteIcon
        }

        return applicationIconLoader.cachedIcon(for: item)
    }

    static func loadApplicationIcon(
        for item: ClipboardItem,
        applicationIconLoader: ClipboardApplicationIconLoader = .shared
    ) async -> NSImage? {
        guard item.kind != .email else { return nil }
        return await applicationIconLoader.loadIcon(for: item)
    }

    static func loadPreferredLeadingIcon(
        for item: ClipboardItem,
        settings: SettingsManager,
        applicationIconLoader: ClipboardApplicationIconLoader = .shared
    ) async -> NSImage? {
        guard item.kind != .email else { return nil }

        if item.kind == .link, settings.enableWebsitePreviews {
            return await ClipboardWebsiteIconLoader.loadWebsiteIcon(for: item)
                ?? applicationIconLoader.cachedIcon(for: item)
        }

        return await applicationIconLoader.loadIcon(for: item)
    }

    static func prewarmPreferredIcons(
        for items: [ClipboardItem],
        settings: SettingsManager,
        applicationIconLoader: ClipboardApplicationIconLoader = .shared,
        limit: Int = 80
    ) async {
        var seenKeys = Set<String>()
        var candidates: [ClipboardItem] = []

        for item in items where item.kind != .email {
            let key: String
            if item.kind == .link, settings.enableWebsitePreviews {
                guard let websiteKey = websiteIconCacheKey(for: item) else { continue }
                key = websiteKey
            } else {
                guard let applicationKey = ClipboardApplicationIconLoader.cacheKey(for: item) else {
                    continue
                }
                key = applicationKey
            }

            guard seenKeys.insert(key).inserted else { continue }
            guard !hasResolvedIcon(for: item, settings: settings, applicationIconLoader: applicationIconLoader)
            else {
                continue
            }

            candidates.append(item)
            if candidates.count >= limit { break }
        }

        let maximumConcurrentLoads = 8
        var batchStart = 0
        while batchStart < candidates.count, !Task.isCancelled {
            let batchEnd = min(candidates.count, batchStart + maximumConcurrentLoads)
            let tasks = candidates[batchStart..<batchEnd].map { item in
                Task { @MainActor in
                    _ = await loadPreferredLeadingIcon(
                        for: item,
                        settings: settings,
                        applicationIconLoader: applicationIconLoader
                    )
                }
            }
            for task in tasks {
                await task.value
            }
            batchStart = batchEnd
        }
    }

    static func clearCaches(applicationIconLoader: ClipboardApplicationIconLoader = .shared) {
        applicationIconLoader.clear()
        ClipboardWebsiteIconLoader.clear()
    }

    static func websiteIconCacheKey(for item: ClipboardItem) -> String? {
        item.linkPayload?.url.host.map { "website:\($0.lowercased())" }
    }

    private static func hasResolvedIcon(
        for item: ClipboardItem,
        settings: SettingsManager,
        applicationIconLoader: ClipboardApplicationIconLoader
    ) -> Bool {
        if item.kind == .link, settings.enableWebsitePreviews,
            let url = item.linkPayload?.url
        {
            return ClipboardWebsiteIconLoader.cachedWebsiteIcon(for: url) != nil
                || ClipboardWebsiteIconLoader.hasMissingWebsiteIcon(for: url)
        }

        return applicationIconLoader.cachedIcon(for: item) != nil
    }
}
