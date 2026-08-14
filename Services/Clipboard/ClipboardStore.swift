import AppKit
import Foundation

struct ClipboardStoreMutationError: LocalizedError, Equatable, Sendable {
    let message: String

    var errorDescription: String? { message }
}

@MainActor
final class ClipboardStore: ObservableObject, ClipboardPasteContentReading {
    private struct StorageComponents {
        let assetStore: ClipboardAssetStore
        let persistence: any ClipboardHistoryPersisting
        let retentionService: ClipboardHistoryRetentionService
    }

    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var searchIndexState = ClipboardSearchIndexState.initial
    @Published private(set) var ocrProcessingItemIDs: Set<UUID> = []

    private let assetAccess: any ClipboardAssetAccessing
    private let repository: ClipboardRepository
    private let retentionService: ClipboardHistoryRetentionServicing
    private let settingsManager: SettingsManager
    private let settingsCoordinator = ClipboardStoreSettingsCoordinator()
    private let retentionScheduler = ClipboardStoreRetentionScheduler()
    private let searchIndexer: any ClipboardSearchIndexing
    private var searchIndexTask: Task<Void, Never>?
    private var searchIndexGeneration: UInt = 0
    private var mutationTail: Task<Void, Never>?

    convenience init(
        settingsManager: SettingsManager,
        storagePaths: ClipboardStoragePaths? = nil,
        searchIndexer: any ClipboardSearchIndexing = ClipboardSearchIndexer()
    ) {
        let paths = Self.resolveStoragePaths(storagePaths)
        let components = Self.makeStorageComponents(paths: paths)
        components.assetStore.ensureDirectoriesExist()
        let initialItems = Self.loadInitialItems(
            components: components,
            retentionPeriod: settingsManager.historyRetentionPeriod
        )
        components.assetStore.cleanupOrphanedAssets(referencedBy: initialItems)

        self.init(
            settingsManager: settingsManager,
            components: components,
            initialItems: initialItems,
            searchIndexer: searchIndexer
        )
    }

    convenience init(
        settingsManager: SettingsManager,
        assetStore: ClipboardAssetStore,
        persistence: any ClipboardHistoryPersisting,
        initialItems: [ClipboardItem] = [],
        searchIndexer: any ClipboardSearchIndexing = ClipboardSearchIndexer()
    ) {
        self.init(
            settingsManager: settingsManager,
            components: StorageComponents(
                assetStore: assetStore,
                persistence: persistence,
                retentionService: ClipboardHistoryRetentionService()
            ),
            initialItems: initialItems,
            searchIndexer: searchIndexer
        )
    }

    static func makeForApplication(settingsManager: SettingsManager) async -> ClipboardStore {
        let paths = resolveStoragePaths(nil)
        let components = makeStorageComponents(paths: paths)
        let loader = ClipboardStoreBootstrapper(
            assetStore: components.assetStore,
            persistence: components.persistence,
            retentionService: components.retentionService
        )

        let initialItems: [ClipboardItem]
        do {
            initialItems = try await loader.loadInitialItems(
                retentionPeriod: settingsManager.historyRetentionPeriod
            )
        } catch {
            BufferLogger.persistence.error(
                "Failed to load clipboard history: \(String(describing: error), privacy: .public)"
            )
            initialItems = []
        }

        return ClipboardStore(
            settingsManager: settingsManager,
            components: components,
            initialItems: initialItems,
            searchIndexer: ClipboardSearchIndexer()
        )
    }

    private init(
        settingsManager: SettingsManager,
        components: StorageComponents,
        initialItems: [ClipboardItem],
        searchIndexer: any ClipboardSearchIndexing
    ) {
        self.settingsManager = settingsManager
        self.searchIndexer = searchIndexer
        assetAccess = components.assetStore
        repository = ClipboardRepository(
            initialItems: initialItems,
            persistence: components.persistence,
            assetStore: components.assetStore
        )
        retentionService = components.retentionService
        applySnapshot(initialItems)

        bindSettings()
        startBackgroundRetentionCleanup()
    }

    private static func resolveStoragePaths(_ storagePaths: ClipboardStoragePaths?) -> ClipboardStoragePaths {
        if let storagePaths {
            return storagePaths
        }

        do {
            return try ClipboardStoragePaths()
        } catch {
            BufferLogger.persistence.fault(
                "Failed to build storage paths: \(String(describing: error), privacy: .public)"
            )
            let fallbackDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "BufferFallback",
                isDirectory: true
            )
            return ClipboardStoragePaths(
                storageDirectory: fallbackDirectory,
                historyFileURL: fallbackDirectory.appendingPathComponent("history.json"),
                imagesDirectory: fallbackDirectory.appendingPathComponent("images", isDirectory: true),
                textsDirectory: fallbackDirectory.appendingPathComponent("texts", isDirectory: true)
            )
        }
    }

    private static func makeStorageComponents(paths: ClipboardStoragePaths) -> StorageComponents {
        StorageComponents(
            assetStore: ClipboardAssetStore(paths: paths),
            persistence: ClipboardHistoryPersistence(paths: paths),
            retentionService: ClipboardHistoryRetentionService()
        )
    }

    private static func loadInitialItems(
        components: StorageComponents,
        retentionPeriod: HistoryRetentionPeriod
    ) -> [ClipboardItem] {
        do {
            return try components.retentionService.prunedInitialItems(
                from: components.persistence.loadHistory(),
                retentionPeriod: retentionPeriod,
                persistence: components.persistence
            )
        } catch {
            BufferLogger.persistence.error(
                "Failed to load clipboard history: \(String(describing: error), privacy: .public)"
            )
            return []
        }
    }

    deinit {
        retentionScheduler.cancel()
        searchIndexTask?.cancel()
    }

    func add(_ item: ClipboardItem) async throws {
        let historyLimit = settingsManager.historyLimit
        let expirationCutoff = retentionService.cutoff(
            for: settingsManager.historyRetentionPeriod,
            now: Date()
        )
        try await runRepositoryMutation { repository in
            try await repository.add(
                item,
                maxItems: historyLimit,
                expirationCutoff: expirationCutoff
            )
        }
    }

    func delete(_ item: ClipboardItem) async throws {
        try await runRepositoryMutation { repository in
            try await repository.delete(item)
        }
    }

    func delete(_ items: [ClipboardItem]) async throws {
        try await runRepositoryMutation { repository in
            try await repository.delete(items)
        }
    }

    func togglePin(for item: ClipboardItem) async throws {
        try await runRepositoryMutation { repository in
            try await repository.togglePin(for: item)
        }
    }

    func updatePinState(_ pinState: ClipboardPinState, for items: [ClipboardItem]) async throws {
        try await runRepositoryMutation { repository in
            try await repository.updatePinState(pinState, for: items)
        }
    }

    func toggleBookmark(for item: ClipboardItem) async throws {
        try await runRepositoryMutation { repository in
            try await repository.toggleBookmark(for: item)
        }
    }

    func updateBookmarkState(
        _ bookmarkState: ClipboardBookmarkState,
        for items: [ClipboardItem]
    ) async throws {
        try await runRepositoryMutation { repository in
            try await repository.updateBookmarkState(bookmarkState, for: items)
        }
    }

    func setOCRText(_ text: String, for item: ClipboardItem) async throws {
        try await runRepositoryMutation { repository in
            try await repository.setOCRText(text, for: item)
        }
    }

    @discardableResult
    func beginOCRProcessing(for item: ClipboardItem) -> Bool {
        guard item.kind == .image,
            item.ocrText == nil,
            items.contains(where: { $0.id == item.id && $0.ocrText == nil }),
            !ocrProcessingItemIDs.contains(item.id)
        else {
            return false
        }

        var nextIDs = ocrProcessingItemIDs
        nextIDs.insert(item.id)
        ocrProcessingItemIDs = nextIDs
        return true
    }

    func finishOCRProcessing(for itemID: UUID) {
        guard ocrProcessingItemIDs.contains(itemID) else { return }
        var nextIDs = ocrProcessingItemIDs
        nextIDs.remove(itemID)
        ocrProcessingItemIDs = nextIDs
    }

    func isOCRProcessing(for itemID: UUID) -> Bool {
        ocrProcessingItemIDs.contains(itemID)
    }

    func moveToTop(_ item: ClipboardItem) async throws {
        try await runRepositoryMutation { repository in
            try await repository.moveToTop(item)
        }
    }

    func clear() async throws {
        try await runRepositoryMutation { repository in
            try await repository.clear()
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

    nonisolated func pasteImageData(for item: ClipboardItem) async -> Data? {
        assetAccess.imageData(for: item)
    }

    nonisolated func pasteText(for item: ClipboardItem) async -> String? {
        switch item.content {
        case .text:
            return assetAccess.fullText(for: item) ?? item.textContent
        case .color(let payload):
            return payload.originalText
        case .link(let payload):
            return payload.originalText
        case .email(let payload):
            return payload.originalText
        case .image:
            return nil
        }
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

    nonisolated func discardCapturedAssets(for item: ClipboardItem) async {
        if let imageFilename = item.imageFilename {
            assetAccess.deleteImage(named: imageFilename)
        }
        if let textFilename = item.textFilename {
            assetAccess.deleteText(named: textFilename)
        }
    }

    func fullText(for item: ClipboardItem) -> String? {
        assetAccess.fullText(for: item)
    }

    nonisolated func fullTextAsync(for item: ClipboardItem) async -> String? {
        assetAccess.fullText(for: item)
    }

    func textChunk(for item: ClipboardItem, charCount: Int) -> ClipboardTextChunk? {
        assetAccess.textChunk(for: item, charCount: charCount)
    }

    nonisolated func textChunkAsync(
        for item: ClipboardItem,
        charCount: Int
    ) async -> ClipboardTextChunk? {
        assetAccess.textChunk(for: item, charCount: charCount)
    }

    func itemSize(for item: ClipboardItem) -> Int? {
        assetAccess.itemSize(for: item)
    }

    nonisolated func itemSizeAsync(for item: ClipboardItem) async -> Int? {
        assetAccess.itemSize(for: item)
    }

    func searchableText(for item: ClipboardItem) -> String {
        searchIndexState.index.searchableText(for: item.id)
    }

    var searchIndexSnapshot: ClipboardSearchIndex {
        searchIndexState.index
    }

    var isSearchIndexReady: Bool {
        searchIndexState.isReady
    }

    func waitForSearchIndex() async {
        while let task = searchIndexTask {
            let generation = searchIndexGeneration
            await task.value

            guard generation == searchIndexGeneration, searchIndexState.isReady else {
                continue
            }
            return
        }
    }

    private func bindSettings() {
        settingsCoordinator.bind(
            settingsManager: settingsManager,
            onHistoryLimitChange: { [weak self] limit in
                Task { @MainActor [weak self] in
                    await self?.performMaintenanceMutation {
                        try await $0.trim(to: limit)
                    }
                }
            },
            onHistoryRetentionPeriodChange: { [weak self] in
                self?.runRetentionPolicyMutation()
            }
        )
    }

    private func applySnapshot(_ nextItems: [ClipboardItem]) {
        let orderedItems = Self.orderedItems(from: nextItems)
        rebuildSearchIndex(for: orderedItems)
        items = orderedItems
    }

    private func rebuildSearchIndex(for items: [ClipboardItem]) {
        searchIndexGeneration &+= 1
        let generation = searchIndexGeneration
        searchIndexState = searchIndexState.markingPending(generation: generation)
        searchIndexTask?.cancel()

        let searchIndexer = searchIndexer
        let assetAccess = assetAccess
        searchIndexTask = Task { [weak self] in
            let index = await searchIndexer.makeIndex(for: items, assetAccess: assetAccess)
            guard let self, !Task.isCancelled, searchIndexGeneration == generation else { return }
            searchIndexState = ClipboardSearchIndexState(
                generation: generation,
                index: index,
                isReady: true
            )
            searchIndexTask = nil
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
    ) async throws -> [ClipboardItem] {
        guard
            let cutoff = retentionService.cutoff(
                for: settingsManager.historyRetentionPeriod,
                now: Date()
            )
        else {
            return currentItems
        }

        return try await repository.pruneExpired(before: cutoff)
    }

    private func runRepositoryMutation(
        _ operation: @escaping @Sendable (ClipboardRepository) async throws -> [ClipboardItem]
    ) async throws {
        let previousTask = mutationTail
        let task = Task<Result<Void, ClipboardStoreMutationError>, Never> { [weak self] in
            _ = await previousTask?.value
            guard let self else { return .success(()) }

            do {
                let nextItems = try await operation(repository)
                applySnapshot(nextItems)
                return .success(())
            } catch {
                let mutationError = ClipboardStoreMutationError(message: error.localizedDescription)
                BufferLogger.persistence.error(
                    "Clipboard mutation failed: \(mutationError.message, privacy: .public)"
                )
                return .failure(mutationError)
            }
        }
        mutationTail = Task { _ = await task.value }

        switch await task.value {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }

    private func runRetentionPolicyMutation() {
        Task { @MainActor [weak self] in
            await self?.performMaintenanceMutation { [weak self] repository in
                guard let self else { return await repository.snapshot() }
                let snapshot = await repository.snapshot()
                return try await self.applyRetentionPolicyIfNeeded(to: snapshot, repository: repository)
            }
        }
    }

    private func performMaintenanceMutation(
        _ operation: @escaping @Sendable (ClipboardRepository) async throws -> [ClipboardItem]
    ) async {
        do {
            try await runRepositoryMutation(operation)
        } catch {
            // Maintenance failures are not initiated by the user, so logging is
            // the appropriate recovery path. The current in-memory snapshot stays valid.
        }
    }

    private func startBackgroundRetentionCleanup() {
        retentionScheduler.start { [weak self] in
            self?.runRetentionPolicyMutation()
        }
    }
}

private actor ClipboardStoreBootstrapper {
    private let assetStore: ClipboardAssetStore
    private let persistence: any ClipboardHistoryPersisting
    private let retentionService: ClipboardHistoryRetentionService

    init(
        assetStore: ClipboardAssetStore,
        persistence: any ClipboardHistoryPersisting,
        retentionService: ClipboardHistoryRetentionService
    ) {
        self.assetStore = assetStore
        self.persistence = persistence
        self.retentionService = retentionService
    }

    func loadInitialItems(retentionPeriod: HistoryRetentionPeriod) throws -> [ClipboardItem] {
        assetStore.ensureDirectoriesExist()
        let items = try retentionService.prunedInitialItems(
            from: persistence.loadHistory(),
            retentionPeriod: retentionPeriod,
            persistence: persistence
        )
        assetStore.cleanupOrphanedAssets(referencedBy: items)
        return items
    }
}
