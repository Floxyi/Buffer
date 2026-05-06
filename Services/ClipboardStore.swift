import AppKit
import Combine
import Foundation

actor ClipboardRepository {
    private var items: [ClipboardItem]
    private let persistence: ClipboardHistoryPersistence
    private let assetStore: ClipboardAssetStore

    init(initialItems: [ClipboardItem], persistence: ClipboardHistoryPersistence, assetStore: ClipboardAssetStore) {
        self.items = initialItems
        self.persistence = persistence
        self.assetStore = assetStore
    }

    func snapshot() -> [ClipboardItem] {
        items
    }

    func add(_ item: ClipboardItem, maxItems: Int) -> [ClipboardItem] {
        items.insert(item, at: 0)

        if items.count > maxItems {
            if let indexToRemove = items.lastIndex(where: { !$0.isPinned }) {
                let removed = items.remove(at: indexToRemove)
                assetStore.deleteAssociatedFiles(for: removed)
            } else if let removed = items.popLast() {
                assetStore.deleteAssociatedFiles(for: removed)
            }
        }

        persist()
        return items
    }

    func delete(_ item: ClipboardItem) -> [ClipboardItem] {
        items.removeAll { $0.id == item.id }
        assetStore.deleteAssociatedFiles(for: item)
        persist()
        return items
    }

    func togglePin(for item: ClipboardItem) -> [ClipboardItem] {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return items }

        items[index].isPinned.toggle()
        items[index].pinnedAt = items[index].isPinned ? Date() : nil
        persist()
        return items
    }

    func setOCRText(_ text: String, for item: ClipboardItem) -> [ClipboardItem] {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return items }
        items[index].ocrText = text
        persist()
        return items
    }

    func moveToTop(_ item: ClipboardItem) -> [ClipboardItem] {
        guard let index = items.firstIndex(where: { $0.id == item.id }), index != 0 else { return items }
        let removed = items.remove(at: index)
        items.insert(removed, at: 0)
        persist()
        return items
    }

    func clear() -> [ClipboardItem] {
        for item in items {
            assetStore.deleteAssociatedFiles(for: item)
        }
        items.removeAll()
        persist()
        return items
    }

    func trim(to maxItems: Int) -> [ClipboardItem] {
        guard items.count > maxItems else { return items }

        while items.count > maxItems {
            if let index = items.lastIndex(where: { !$0.isPinned }) {
                let removed = items.remove(at: index)
                assetStore.deleteAssociatedFiles(for: removed)
            } else {
                break
            }
        }

        persist()
        return items
    }

    private func persist() {
        persistence.saveHistory(items)
    }
}

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private(set) var currentMaxItems: Int
    private let assetStore: ClipboardAssetStore
    private let repository: ClipboardRepository
    private let settingsManager: SettingsManager
    private var cancellables: Set<AnyCancellable> = []
    private var searchCache: [UUID: String] = [:]

    init(settingsManager: SettingsManager, storagePaths: ClipboardStoragePaths? = nil) {
        self.settingsManager = settingsManager

        let paths: ClipboardStoragePaths
        if let storagePaths {
            paths = storagePaths
        } else {
            do {
                paths = try ClipboardStoragePaths()
            } catch {
                BufferLogger.persistence.fault("Failed to build storage paths: \(String(describing: error), privacy: .public)")
                let fallbackDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BufferFallback", isDirectory: true)
                paths = ClipboardStoragePaths(
                    storageDirectory: fallbackDirectory,
                    historyFileURL: fallbackDirectory.appendingPathComponent("history.json"),
                    imagesDirectory: fallbackDirectory.appendingPathComponent("images", isDirectory: true),
                    textsDirectory: fallbackDirectory.appendingPathComponent("texts", isDirectory: true)
                )
            }
        }

        self.currentMaxItems = settingsManager.historyLimit.rawValue

        let assetStore = ClipboardAssetStore(paths: paths)
        let persistence = ClipboardHistoryPersistence(paths: paths)
        assetStore.ensureDirectoriesExist()

        let initialItems = persistence.loadHistory()
        assetStore.cleanupOrphanedAssets(referencedBy: initialItems)

        self.assetStore = assetStore
        self.repository = ClipboardRepository(
            initialItems: initialItems,
            persistence: persistence,
            assetStore: assetStore
        )
        self.items = initialItems

        bindSettings()
    }

    func add(_ item: ClipboardItem) {
        Task {
            let nextItems = await repository.add(item, maxItems: currentMaxItems)
            applySnapshot(nextItems)
        }
    }

    func delete(_ item: ClipboardItem) {
        Task {
            let nextItems = await repository.delete(item)
            applySnapshot(nextItems)
        }
    }

    func togglePin(for item: ClipboardItem) {
        Task {
            let nextItems = await repository.togglePin(for: item)
            applySnapshot(nextItems)
        }
    }

    func setOCRText(_ text: String, for item: ClipboardItem) {
        Task {
            let nextItems = await repository.setOCRText(text, for: item)
            applySnapshot(nextItems)
        }
    }

    func moveToTop(_ item: ClipboardItem) {
        Task {
            let nextItems = await repository.moveToTop(item)
            applySnapshot(nextItems)
        }
    }

    func clear() {
        Task {
            let nextItems = await repository.clear()
            applySnapshot(nextItems)
        }
    }

    func image(for item: ClipboardItem) -> NSImage? {
        assetStore.image(for: item)
    }

    func saveImage(_ data: Data) -> String? {
        assetStore.saveImage(data)
    }

    func saveText(_ text: String) -> String? {
        assetStore.saveText(text)
    }

    func fullText(for item: ClipboardItem) -> String? {
        assetStore.fullText(for: item)
    }

    func textChunk(for item: ClipboardItem, charCount: Int) -> (text: String, totalBytes: Int, reachedEOF: Bool)? {
        assetStore.textChunk(for: item, charCount: charCount)
    }

    func itemSize(for item: ClipboardItem) -> Int? {
        assetStore.itemSize(for: item)
    }

    func searchableText(for item: ClipboardItem) -> String {
        if let cached = searchCache[item.id] {
            return cached
        }

        let value: String
        switch item.type {
        case .text:
            if item.isFileBacked {
                value = fullText(for: item) ?? item.textContent ?? ""
            } else {
                value = item.textContent ?? ""
            }
        case .image:
            value = item.ocrText ?? ""
        }

        searchCache[item.id] = value
        return value
    }

    private func bindSettings() {
        settingsManager.$historyLimit
            .removeDuplicates()
            .sink { [weak self] limit in
                guard let self else { return }
                self.currentMaxItems = limit.rawValue
                Task {
                    let trimmed = await self.repository.trim(to: limit.rawValue)
                    self.applySnapshot(trimmed)
                }
            }
            .store(in: &cancellables)
    }

    private func applySnapshot(_ nextItems: [ClipboardItem]) {
        items = nextItems
        let validIDs = Set(nextItems.map(\.id))
        searchCache = searchCache.filter { validIDs.contains($0.key) }
    }
}
