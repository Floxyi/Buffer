import AppKit
import Foundation
@preconcurrency import LinkPresentation

@MainActor
enum ClipboardWebsiteIconLoader {
    private static var metadataCache: [URL: LPLinkMetadata] = [:]
    private static var metadataWaiters: [URL: [CheckedContinuation<UnsafeLinkMetadataBox, Never>]] = [:]
    private static var activeMetadataProviders: [URL: LPMetadataProvider] = [:]

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

    static func loadWebsiteIcon(for item: ClipboardItem) async -> NSImage? {
        guard let url = item.linkPayload?.url else {
            return nil
        }

        if let cachedIcon = cachedWebsiteIcon(for: url) {
            return cachedIcon
        }

        if hasMissingWebsiteIcon(for: url) {
            return nil
        }

        _ = await metadata(for: url)
        if let cachedIcon = cachedWebsiteIcon(for: url) {
            return cachedIcon
        }

        guard let iconImage = await ClipboardWebsiteIconFallbackFetcher.fetchIcon(for: url) else {
            markWebsiteIconMissing(for: url)
            return nil
        }

        storeWebsiteIcon(iconImage, for: url)
        return cachedWebsiteIcon(for: url)
    }

    static func cachedWebsiteIcon(for url: URL) -> NSImage? {
        ClipboardWebsiteIconCache.cachedIcon(for: url)
    }

    static func hasMissingWebsiteIcon(for url: URL) -> Bool {
        ClipboardWebsiteIconCache.hasMarkedMissingIcon(for: url)
    }

    static func markWebsiteIconMissing(for url: URL) {
        ClipboardWebsiteIconCache.markMissing(for: url)
    }

    static func storeWebsiteIcon(_ image: NSImage, for url: URL) {
        ClipboardWebsiteIconCache.store(image, for: url)
    }

    static func clear() {
        metadataCache.removeAll()
        let pendingURLs = Array(metadataWaiters.keys)
        for url in pendingURLs {
            let continuations = metadataWaiters.removeValue(forKey: url) ?? []
            continuations.forEach { $0.resume(returning: UnsafeLinkMetadataBox(value: nil)) }
        }
        activeMetadataProviders.removeAll()
        ClipboardWebsiteIconCache.clear()
    }

    static func faviconURL(for item: ClipboardItem) -> URL? {
        ClipboardWebsiteIconFallbackFetcher.faviconURL(for: item)
    }

    static func faviconURL(for url: URL) -> URL? {
        ClipboardWebsiteIconFallbackFetcher.faviconURL(for: url)
    }

    private static func cacheWebsiteIcon(from metadata: LPLinkMetadata, for url: URL) async {
        guard cachedWebsiteIcon(for: url) == nil,
              let iconImage = await ClipboardWebsiteIconFallbackFetcher.loadImage(from: metadata.iconProvider) else {
            return
        }

        storeWebsiteIcon(iconImage, for: url)
    }
}

private struct UnsafeLinkMetadataBox: @unchecked Sendable {
    let value: LPLinkMetadata?
}
