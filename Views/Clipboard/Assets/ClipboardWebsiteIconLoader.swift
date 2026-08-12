import AppKit
import Foundation
@preconcurrency import LinkPresentation

@MainActor
enum ClipboardWebsiteIconLoader {
    private static let maximumConcurrentMetadataRequests = 4
    private static let maximumConcurrentFallbackRequests = 4

    private static var metadataCache: [URL: LPLinkMetadata] = [:]
    private static var metadataWaiters: [URL: [UUID: CheckedContinuation<UnsafeLinkMetadataBox, Never>]] = [:]
    private static var queuedMetadataURLs: [URL] = []
    private static var activeMetadataProviders: [URL: LPMetadataProvider] = [:]

    private static var fallbackWaiters: [URL: [UUID: CheckedContinuation<UnsafeImageBox, Never>]] = [:]
    private static var queuedFallbackURLs: [URL] = []
    private static var activeFallbackTasks: [URL: Task<Void, Never>] = [:]

    static func metadata(for url: URL) async -> LPLinkMetadata? {
        if let cachedMetadata = metadataCache[url] {
            return cachedMetadata
        }

        let waiterID = UUID()
        let metadataBox = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: UnsafeLinkMetadataBox(value: nil))
                    return
                }

                let shouldQueue = metadataWaiters[url] == nil
                metadataWaiters[url, default: [:]][waiterID] = continuation
                if shouldQueue {
                    queuedMetadataURLs.append(url)
                    startQueuedMetadataRequestsIfPossible()
                }
            }
        } onCancel: {
            Task { @MainActor in
                cancelMetadataWaiter(waiterID, for: url)
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

        if let persistedIcon = await ClipboardWebsiteIconCache.loadPersistedIcon(for: url) {
            return persistedIcon
        }

        if hasMissingWebsiteIcon(for: url) {
            return nil
        }

        _ = await metadata(for: url)
        guard !Task.isCancelled else {
            return nil
        }

        if let cachedIcon = cachedWebsiteIcon(for: url) {
            return cachedIcon
        }

        guard let iconImage = await fallbackIcon(for: url), !Task.isCancelled else {
            if Task.isCancelled {
                return nil
            }
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

        for provider in activeMetadataProviders.values {
            provider.cancel()
        }
        activeMetadataProviders.removeAll()
        queuedMetadataURLs.removeAll()
        let pendingMetadataWaiters = metadataWaiters.values.flatMap(\.values)
        metadataWaiters.removeAll()
        for continuation in pendingMetadataWaiters {
            continuation.resume(returning: UnsafeLinkMetadataBox(value: nil))
        }

        for task in activeFallbackTasks.values {
            task.cancel()
        }
        activeFallbackTasks.removeAll()
        queuedFallbackURLs.removeAll()
        let pendingFallbackWaiters = fallbackWaiters.values.flatMap(\.values)
        fallbackWaiters.removeAll()
        for continuation in pendingFallbackWaiters {
            continuation.resume(returning: UnsafeImageBox(value: nil))
        }

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
            let iconImage = await ClipboardWebsiteIconFallbackFetcher.loadImage(from: metadata.iconProvider)
        else {
            return
        }

        storeWebsiteIcon(iconImage, for: url)
    }

    private static func startQueuedMetadataRequestsIfPossible() {
        while activeMetadataProviders.count < maximumConcurrentMetadataRequests,
            let url = queuedMetadataURLs.first
        {
            queuedMetadataURLs.removeFirst()

            guard metadataWaiters[url]?.isEmpty == false else {
                metadataWaiters.removeValue(forKey: url)
                continue
            }

            let provider = LPMetadataProvider()
            activeMetadataProviders[url] = provider
            provider.startFetchingMetadata(for: url) { metadata, error in
                let metadataBox = UnsafeLinkMetadataBox(value: metadata)
                let errorDescription = String(describing: error)

                Task { @MainActor in
                    await finishMetadataRequest(
                        for: url,
                        metadataBox: metadataBox,
                        errorDescription: errorDescription
                    )
                }
            }
        }
    }

    private static func finishMetadataRequest(
        for url: URL,
        metadataBox: UnsafeLinkMetadataBox,
        errorDescription: String
    ) async {
        guard activeMetadataProviders.removeValue(forKey: url) != nil else {
            return
        }

        let continuations =
            metadataWaiters.removeValue(forKey: url).map {
                Array($0.values)
            } ?? []
        startQueuedMetadataRequestsIfPossible()

        if let metadata = metadataBox.value {
            metadataCache[url] = metadata
            await cacheWebsiteIcon(from: metadata, for: url)
        } else {
            BufferLogger.ui.error(
                "Failed to fetch link metadata for \(url.absoluteString, privacy: .public): \(errorDescription, privacy: .public)"
            )
        }

        for continuation in continuations {
            continuation.resume(returning: metadataBox)
        }
    }

    private static func cancelMetadataWaiter(_ waiterID: UUID, for url: URL) {
        guard let continuation = metadataWaiters[url]?.removeValue(forKey: waiterID) else {
            return
        }

        continuation.resume(returning: UnsafeLinkMetadataBox(value: nil))
        guard metadataWaiters[url]?.isEmpty == true else {
            return
        }

        metadataWaiters.removeValue(forKey: url)
        queuedMetadataURLs.removeAll { $0 == url }
        activeMetadataProviders.removeValue(forKey: url)?.cancel()
        startQueuedMetadataRequestsIfPossible()
    }

    private static func fallbackIcon(for url: URL) async -> NSImage? {
        let waiterID = UUID()
        let imageBox = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: UnsafeImageBox(value: nil))
                    return
                }

                let shouldQueue = fallbackWaiters[url] == nil
                fallbackWaiters[url, default: [:]][waiterID] = continuation
                if shouldQueue {
                    queuedFallbackURLs.append(url)
                    startQueuedFallbackRequestsIfPossible()
                }
            }
        } onCancel: {
            Task { @MainActor in
                cancelFallbackWaiter(waiterID, for: url)
            }
        }

        return imageBox.value
    }

    private static func startQueuedFallbackRequestsIfPossible() {
        while activeFallbackTasks.count < maximumConcurrentFallbackRequests,
            let url = queuedFallbackURLs.first
        {
            queuedFallbackURLs.removeFirst()

            guard fallbackWaiters[url]?.isEmpty == false else {
                fallbackWaiters.removeValue(forKey: url)
                continue
            }

            activeFallbackTasks[url] = Task { @MainActor in
                let image = await ClipboardWebsiteIconFallbackFetcher.fetchIcon(for: url)
                finishFallbackRequest(for: url, image: Task.isCancelled ? nil : image)
            }
        }
    }

    private static func finishFallbackRequest(for url: URL, image: NSImage?) {
        guard activeFallbackTasks.removeValue(forKey: url) != nil else {
            return
        }

        let continuations =
            fallbackWaiters.removeValue(forKey: url).map {
                Array($0.values)
            } ?? []
        startQueuedFallbackRequestsIfPossible()
        let imageBox = UnsafeImageBox(value: image)
        for continuation in continuations {
            continuation.resume(returning: imageBox)
        }
    }

    private static func cancelFallbackWaiter(_ waiterID: UUID, for url: URL) {
        guard let continuation = fallbackWaiters[url]?.removeValue(forKey: waiterID) else {
            return
        }

        continuation.resume(returning: UnsafeImageBox(value: nil))
        guard fallbackWaiters[url]?.isEmpty == true else {
            return
        }

        fallbackWaiters.removeValue(forKey: url)
        queuedFallbackURLs.removeAll { $0 == url }
        activeFallbackTasks.removeValue(forKey: url)?.cancel()
        startQueuedFallbackRequestsIfPossible()
    }
}

private struct UnsafeLinkMetadataBox: @unchecked Sendable {
    let value: LPLinkMetadata?
}

private struct UnsafeImageBox: @unchecked Sendable {
    let value: NSImage?
}
