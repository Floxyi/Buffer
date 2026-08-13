import AppKit
import Foundation

private final class ClipboardApplicationIconValue: @unchecked Sendable {
    let image: NSImage?

    init(_ image: NSImage?) {
        self.image = image
    }
}

/// Loads native macOS application icons without flattening their size-specific
/// representations. AppKit can therefore select the best representation for the
/// display scale and rendered size.
@MainActor
final class ClipboardApplicationIconLoader {
    typealias IconResolver = @MainActor (ClipboardItem) async -> NSImage?

    static let shared = ClipboardApplicationIconLoader()

    private struct ActiveLoad {
        let id: UUID
        let task: Task<ClipboardApplicationIconValue, Never>
    }

    private let cache: NSCache<NSString, NSImage>
    private let resolver: IconResolver
    private var missingIconKeys = Set<String>()
    private var activeLoads: [String: ActiveLoad] = [:]

    init(
        cacheLimit: Int = 120,
        resolver: IconResolver? = nil
    ) {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = cacheLimit
        self.cache = cache
        self.resolver = resolver ?? Self.resolveNativeIcon
    }

    deinit {
        for load in activeLoads.values {
            load.task.cancel()
        }
    }

    func cachedIcon(for item: ClipboardItem) -> NSImage? {
        guard let key = Self.cacheKey(for: item) else { return nil }
        return cache.object(forKey: key as NSString)
    }

    func loadIcon(for item: ClipboardItem) async -> NSImage? {
        guard let key = Self.cacheKey(for: item) else { return nil }

        if let cachedIcon = cache.object(forKey: key as NSString) {
            return cachedIcon
        }
        guard !missingIconKeys.contains(key) else { return nil }

        if let activeLoad = activeLoads[key] {
            let value = await activeLoad.task.value
            return Task.isCancelled ? nil : value.image
        }

        let loadID = UUID()
        let resolver = resolver
        let task = Task { @MainActor [weak self] in
            guard !Task.isCancelled else {
                return ClipboardApplicationIconValue(nil)
            }
            let icon = await resolver(item)
            guard !Task.isCancelled else {
                return ClipboardApplicationIconValue(nil)
            }
            guard let icon else {
                self?.missingIconKeys.insert(key)
                return ClipboardApplicationIconValue(nil)
            }
            self?.cache.setObject(icon, forKey: key as NSString)
            self?.missingIconKeys.remove(key)
            return ClipboardApplicationIconValue(icon)
        }
        activeLoads[key] = ActiveLoad(id: loadID, task: task)

        let value = await task.value
        if activeLoads[key]?.id == loadID {
            activeLoads.removeValue(forKey: key)
        }
        guard !Task.isCancelled, !task.isCancelled else { return nil }
        return value.image
    }

    func prewarmIcons(for items: [ClipboardItem], limit: Int = 80) async {
        var seenKeys = Set<String>()
        var candidates: [ClipboardItem] = []

        for item in items {
            guard let key = Self.cacheKey(for: item), seenKeys.insert(key).inserted else {
                continue
            }
            guard cache.object(forKey: key as NSString) == nil,
                !missingIconKeys.contains(key)
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
                Task { @MainActor [weak self] in
                    _ = await self?.loadIcon(for: item)
                }
            }
            for task in tasks {
                await task.value
            }
            batchStart = batchEnd
        }
    }

    func clear() {
        for load in activeLoads.values {
            load.task.cancel()
        }
        activeLoads.removeAll()
        cache.removeAllObjects()
        missingIconKeys.removeAll()
    }

    static func cacheKey(for item: ClipboardItem) -> String? {
        guard item.kind != .email else { return nil }

        if let bundlePath = item.sourceAppBundlePath, !bundlePath.isEmpty {
            return "path:\(bundlePath)"
        }
        if let bundleIdentifier = item.sourceAppBundleIdentifier, !bundleIdentifier.isEmpty {
            return "bundle:\(bundleIdentifier)"
        }
        return nil
    }

    private static func resolveNativeIcon(for item: ClipboardItem) async -> NSImage? {
        let value = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let icon: NSImage?
                if let bundlePath = item.sourceAppBundlePath, !bundlePath.isEmpty {
                    icon = NSWorkspace.shared.icon(forFile: bundlePath)
                } else if let bundleIdentifier = item.sourceAppBundleIdentifier,
                    let applicationURL = NSWorkspace.shared.urlForApplication(
                        withBundleIdentifier: bundleIdentifier
                    )
                {
                    icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
                } else {
                    icon = nil
                }

                continuation.resume(
                    returning: ClipboardApplicationIconValue(
                        icon.map(Self.preservedCopy)
                    )
                )
            }
        }
        return value.image
    }

    nonisolated static func preservedCopy(of image: NSImage) -> NSImage {
        image.copy() as? NSImage ?? image
    }
}

actor ClipboardLegacyApplicationIconCacheCleaner {
    static let shared = ClipboardLegacyApplicationIconCacheCleaner(
        directory: defaultCacheDirectory()
    )

    private let directory: URL
    private let fileManager: FileManager
    private var hasCleaned = false

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    func removeLegacyCacheIfNeeded() {
        guard !hasCleaned else { return }
        hasCleaned = true
        guard fileManager.fileExists(atPath: directory.path) else { return }

        do {
            try fileManager.removeItem(at: directory)
        } catch {
            BufferLogger.persistence.error(
                "Failed to remove legacy application icon cache: \(String(describing: error), privacy: .public)"
            )
        }
    }

    nonisolated static func defaultCacheDirectory() -> URL {
        let cachesDirectory =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        return
            cachesDirectory
            .appendingPathComponent("Buffer", isDirectory: true)
            .appendingPathComponent("ApplicationIcons", isDirectory: true)
    }
}
