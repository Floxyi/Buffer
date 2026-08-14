import AppKit
import Combine
import Foundation

extension Notification.Name {
    /// Posted by AppKit when the system app-icon style or tint changes.
    static let workspaceIconAppearanceConfigurationDidChange = Notification.Name(
        "NSWorkspaceIconAppearanceConfigurationDidChangeNotification"
    )
}

private final class ClipboardApplicationIconValue: @unchecked Sendable {
    let image: NSImage?

    init(_ image: NSImage?) {
        self.image = image
    }
}

enum ClipboardApplicationIconAppearance: String, Sendable {
    case light
    case dark

    @MainActor
    static var current: Self {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .dark : .light
    }

    var appKitName: NSAppearance.Name {
        self == .dark ? .darkAqua : .aqua
    }
}

/// Loads native macOS application icons without flattening their size-specific
/// representations. AppKit can therefore select the best representation for the
/// display scale and rendered size.
@MainActor
final class ClipboardApplicationIconLoader: ObservableObject {
    typealias IconResolver = @MainActor (ClipboardItem) async -> NSImage?
    typealias AppearanceIconResolver =
        @MainActor (
            ClipboardItem,
            ClipboardApplicationIconAppearance
        ) async -> NSImage?

    static let shared = ClipboardApplicationIconLoader()

    @Published private(set) var iconRevision = UInt(0)

    private struct ActiveLoad {
        let id: UUID
        let task: Task<ClipboardApplicationIconValue, Never>
    }

    private let cache: NSCache<NSString, NSImage>
    private let resolver: AppearanceIconResolver
    private var missingIconKeys = Set<String>()
    private var activeLoads: [String: ActiveLoad] = [:]
    private var iconAppearanceCancellable: AnyCancellable?

    init(
        cacheLimit: Int = 120,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        resolver: IconResolver? = nil
    ) {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = cacheLimit
        self.cache = cache
        if let resolver {
            self.resolver = { item, _ in await resolver(item) }
        } else {
            self.resolver = Self.resolveNativeIcon
        }
        observeIconAppearanceChanges(in: notificationCenter)
    }

    init(
        cacheLimit: Int = 120,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        appearanceResolver: @escaping AppearanceIconResolver
    ) {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = cacheLimit
        self.cache = cache
        self.resolver = appearanceResolver
        observeIconAppearanceChanges(in: notificationCenter)
    }

    deinit {
        for load in activeLoads.values {
            load.task.cancel()
        }
    }

    func cachedIcon(
        for item: ClipboardItem,
        appearance: ClipboardApplicationIconAppearance = .current
    ) -> NSImage? {
        guard let key = Self.resolvedCacheKey(for: item, appearance: appearance) else {
            return nil
        }
        return cache.object(forKey: key as NSString)
    }

    func loadIcon(
        for item: ClipboardItem,
        appearance: ClipboardApplicationIconAppearance = .current
    ) async -> NSImage? {
        guard let key = Self.resolvedCacheKey(for: item, appearance: appearance) else {
            return nil
        }

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
            let icon = await resolver(item, appearance)
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

    func prewarmIcons(
        for items: [ClipboardItem],
        appearance: ClipboardApplicationIconAppearance = .current,
        limit: Int = 80
    ) async {
        guard limit > 0 else { return }
        var seenKeys = Set<String>()
        var candidates: [ClipboardItem] = []

        for item in items {
            guard let key = Self.resolvedCacheKey(for: item, appearance: appearance),
                seenKeys.insert(key).inserted
            else {
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
                    _ = await self?.loadIcon(for: item, appearance: appearance)
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
        iconRevision &+= 1
    }

    static func cacheKey(for item: ClipboardItem) -> String? {
        guard item.kind != .email else { return nil }

        if let bundleIdentifier = item.normalizedSourceAppBundleIdentifier {
            return "bundle:\(bundleIdentifier)"
        }
        if let bundlePath = item.sourceAppBundlePath, !bundlePath.isEmpty {
            return "path:\(bundlePath)"
        }
        return nil
    }

    private static func resolvedCacheKey(
        for item: ClipboardItem,
        appearance: ClipboardApplicationIconAppearance
    ) -> String? {
        cacheKey(for: item).map { "\($0)|appearance:\(appearance.rawValue)" }
    }

    private func observeIconAppearanceChanges(in notificationCenter: NotificationCenter) {
        iconAppearanceCancellable = notificationCenter.publisher(
            for: .workspaceIconAppearanceConfigurationDidChange
        )
        .sink { [weak self] _ in
            self?.clear()
        }
    }

    private static func resolveNativeIcon(
        for item: ClipboardItem,
        appearance: ClipboardApplicationIconAppearance
    ) async -> NSImage? {
        let value = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let icon: NSImage?
                var appearanceIcon: NSImage?
                let drawingAppearance = NSAppearance(named: appearance.appKitName)
                drawingAppearance?.performAsCurrentDrawingAppearance {
                    if let bundleIdentifier = item.normalizedSourceAppBundleIdentifier,
                        let applicationURL = NSWorkspace.shared.urlForApplication(
                            withBundleIdentifier: bundleIdentifier
                        )
                    {
                        appearanceIcon = NSWorkspace.shared.icon(forFile: applicationURL.path)
                    } else if let bundlePath = item.sourceAppBundlePath, !bundlePath.isEmpty,
                        FileManager.default.fileExists(atPath: bundlePath)
                    {
                        appearanceIcon = NSWorkspace.shared.icon(forFile: bundlePath)
                    }
                }
                icon = appearanceIcon

                continuation.resume(
                    // Keep the IconServices-backed image live. On macOS 26,
                    // generated renditions for legacy app icons can update in
                    // place after the system icon appearance changes.
                    returning: ClipboardApplicationIconValue(icon)
                )
            }
        }
        return value.image
    }

    nonisolated static func preservedCopy(of image: NSImage) -> NSImage {
        image.copy() as? NSImage ?? image
    }

    nonisolated static func logicalSizeCopy(of image: NSImage, size: CGFloat) -> NSImage {
        let copy = preservedCopy(of: image)
        copy.size = NSSize(width: size, height: size)
        return copy
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
