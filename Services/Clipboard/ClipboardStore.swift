import AppKit
import Foundation

@MainActor
protocol ClipboardStoreReading: AnyObject {
    var items: [ClipboardItem] { get }

    func image(for item: ClipboardItem) -> NSImage?
    func thumbnail(for item: ClipboardItem, maxPixelSize: CGFloat) -> NSImage?
    func imageDimensions(for item: ClipboardItem) -> String?
    func fullText(for item: ClipboardItem) -> String?
    func textChunk(for item: ClipboardItem, charCount: Int) -> (text: String, totalBytes: Int, reachedEOF: Bool)?
    func itemSize(for item: ClipboardItem) -> Int?
    func searchableText(for item: ClipboardItem) -> String
    func matchesSearchQuery(_ normalizedQuery: String, for item: ClipboardItem) -> Bool
}

@MainActor
final class ClipboardStore: ObservableObject, ClipboardStoreReading {
    @Published private(set) var items: [ClipboardItem] = []

    private let assetAccess: any ClipboardAssetAccessing
    private let repository: ClipboardRepository
    private let retentionService: ClipboardHistoryRetentionServicing
    private let settingsManager: SettingsManager
    private let settingsCoordinator = ClipboardStoreSettingsCoordinator()
    private let retentionScheduler = ClipboardStoreRetentionScheduler()
    private var searchIndex = ClipboardSearchIndex()
    private var mutationTask: Task<Void, Never>?

    init(settingsManager: SettingsManager, storagePaths: ClipboardStoragePaths? = nil) {
        self.settingsManager = settingsManager

        let paths: ClipboardStoragePaths
        if let storagePaths {
            paths = storagePaths
        } else {
            do {
                paths = try ClipboardStoragePaths()
            } catch {
                BufferLogger.persistence.fault(
                    "Failed to build storage paths: \(String(describing: error), privacy: .public)")
                let fallbackDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
                    "BufferFallback", isDirectory: true)
                paths = ClipboardStoragePaths(
                    storageDirectory: fallbackDirectory,
                    historyFileURL: fallbackDirectory.appendingPathComponent("history.json"),
                    imagesDirectory: fallbackDirectory.appendingPathComponent("images", isDirectory: true),
                    textsDirectory: fallbackDirectory.appendingPathComponent("texts", isDirectory: true)
                )
            }
        }

        let assetStore = ClipboardAssetStore(paths: paths)
        let persistence = ClipboardHistoryPersistence(paths: paths)
        let retentionService = ClipboardHistoryRetentionService()
        assetStore.ensureDirectoriesExist()

        let initialItems = retentionService.prunedInitialItems(
            from: persistence.loadHistory(),
            retentionPeriod: settingsManager.historyRetentionPeriod,
            persistence: persistence
        )
        assetStore.cleanupOrphanedAssets(referencedBy: initialItems)

        assetAccess = assetStore
        repository = ClipboardRepository(
            initialItems: initialItems,
            persistence: persistence,
            assetStore: assetStore
        )
        self.retentionService = retentionService
        applySnapshot(initialItems)

        bindSettings()
        startBackgroundRetentionCleanup()
    }

    deinit {
        retentionScheduler.cancel()
    }

    func add(_ item: ClipboardItem) {
        runRepositoryMutation { [self] repository in
            let nextItems = await repository.add(item, maxItems: self.settingsManager.historyLimit)
            return await self.applyRetentionPolicyIfNeeded(to: nextItems, repository: repository)
        }
    }

    func delete(_ item: ClipboardItem) {
        runRepositoryMutation { repository in
            await repository.delete(item)
        }
    }

    func delete(_ items: [ClipboardItem]) {
        runRepositoryMutation { repository in
            await repository.delete(items)
        }
    }

    func togglePin(for item: ClipboardItem) {
        runRepositoryMutation { repository in
            await repository.togglePin(for: item)
        }
    }

    func updatePinState(_ pinState: ClipboardPinState, for items: [ClipboardItem]) {
        runRepositoryMutation { repository in
            await repository.updatePinState(pinState, for: items)
        }
    }

    func setOCRText(_ text: String, for item: ClipboardItem) {
        runRepositoryMutation { repository in
            await repository.setOCRText(text, for: item)
        }
    }

    func moveToTop(_ item: ClipboardItem) {
        runRepositoryMutation { repository in
            await repository.moveToTop(item)
        }
    }

    func clear() {
        runRepositoryMutation { repository in
            await repository.clear()
        }
    }

    func image(for item: ClipboardItem) -> NSImage? {
        assetAccess.image(for: item)
    }

    func thumbnail(for item: ClipboardItem, maxPixelSize: CGFloat) -> NSImage? {
        assetAccess.thumbnail(for: item, maxPixelSize: maxPixelSize)
    }

    func imageDimensions(for item: ClipboardItem) -> String? {
        assetAccess.imageDimensions(for: item)
    }

    nonisolated func imageAsync(for item: ClipboardItem) async -> NSImage? {
        assetAccess.image(for: item)
    }

    nonisolated func thumbnailAsync(for item: ClipboardItem, maxPixelSize: CGFloat) async -> NSImage? {
        assetAccess.thumbnail(for: item, maxPixelSize: maxPixelSize)
    }

    nonisolated func imageDimensionsAsync(for item: ClipboardItem) async -> String? {
        assetAccess.imageDimensions(for: item)
    }

    func saveImage(_ data: Data) -> String? {
        assetAccess.saveImage(data)
    }

    func saveText(_ text: String) -> String? {
        assetAccess.saveText(text)
    }

    nonisolated func saveImageAsync(_ data: Data) async -> String? {
        BufferPerformanceDiagnostics.measure(.clipboardCapture) {
            assetAccess.saveImage(data)
        }
    }

    nonisolated func saveTextAsync(_ text: String) async -> String? {
        BufferPerformanceDiagnostics.measure(.clipboardCapture) {
            assetAccess.saveText(text)
        }
    }

    nonisolated func discardCapturedImage(named filename: String) async {
        assetAccess.deleteImage(named: filename)
    }

    nonisolated func discardCapturedText(named filename: String) async {
        assetAccess.deleteText(named: filename)
    }

    func fullText(for item: ClipboardItem) -> String? {
        assetAccess.fullText(for: item)
    }

    func textChunk(for item: ClipboardItem, charCount: Int) -> (text: String, totalBytes: Int, reachedEOF: Bool)? {
        assetAccess.textChunk(for: item, charCount: charCount)
    }

    nonisolated func textChunkAsync(
        for item: ClipboardItem,
        charCount: Int
    ) async -> (text: String, totalBytes: Int, reachedEOF: Bool)? {
        assetAccess.textChunk(for: item, charCount: charCount)
    }

    func itemSize(for item: ClipboardItem) -> Int? {
        assetAccess.itemSize(for: item)
    }

    nonisolated func itemSizeAsync(for item: ClipboardItem) async -> Int? {
        assetAccess.itemSize(for: item)
    }

    func searchableText(for item: ClipboardItem) -> String {
        if searchIndex.hasEntry(for: item.id) {
            return searchIndex.searchableText(for: item.id)
        }

        let text = ClipboardItemTypeRegistry.searchableText(for: item, store: self)
        searchIndex.store(text, for: item)
        return text
    }

    func matchesSearchQuery(_ normalizedQuery: String, for item: ClipboardItem) -> Bool {
        if searchIndex.hasEntry(for: item.id) {
            return searchIndex.matches(normalizedQuery, for: item.id)
        }

        return ClipboardSearchIndex.normalize(searchableText(for: item)).contains(normalizedQuery)
    }

    private func bindSettings() {
        settingsCoordinator.bind(
            settingsManager: settingsManager,
            onHistoryLimitChange: { [weak self] limit in
                self?.runRepositoryMutation { repository in
                    await repository.trim(to: limit)
                }
            },
            onHistoryRetentionPeriodChange: { [weak self] in
                self?.runRetentionPolicyMutation()
            }
        )
    }

    private func applySnapshot(_ nextItems: [ClipboardItem]) {
        let orderedItems = Self.orderedItems(from: nextItems)
        items = orderedItems
        searchIndex.rebuild(using: orderedItems) { [self] item in
            ClipboardItemTypeRegistry.searchableText(for: item, store: self)
        }
    }

    private nonisolated static func orderedItems(from items: [ClipboardItem]) -> [ClipboardItem] {
        let pinnedItems = items.filter(\.isPinned)
        let unpinnedItems = items.filter { !$0.isPinned }
        return pinnedItems + unpinnedItems
    }

    private func applyRetentionPolicyIfNeeded(
        to currentItems: [ClipboardItem],
        repository: ClipboardRepository
    ) async -> [ClipboardItem] {
        guard
            let cutoff = retentionService.cutoff(
                for: settingsManager.historyRetentionPeriod,
                now: Date()
            )
        else {
            return currentItems
        }

        return await repository.pruneExpired(before: cutoff)
    }

    private func runRepositoryMutation(
        _ operation: @escaping @Sendable (ClipboardRepository) async -> [ClipboardItem]
    ) {
        let previousTask = mutationTask
        mutationTask = Task { [weak self] in
            _ = await previousTask?.value
            guard let self else { return }
            let nextItems = await operation(repository)
            applySnapshot(nextItems)
        }
    }

    private func runRetentionPolicyMutation() {
        runRepositoryMutation { [weak self] repository in
            guard let self else { return await repository.snapshot() }
            let snapshot = await repository.snapshot()
            return await self.applyRetentionPolicyIfNeeded(to: snapshot, repository: repository)
        }
    }

    private func startBackgroundRetentionCleanup() {
        retentionScheduler.start { [weak self] in
            self?.runRetentionPolicyMutation()
        }
    }
}
