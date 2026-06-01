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

    func delete(_ itemsToDelete: [ClipboardItem]) -> [ClipboardItem] {
        let idsToDelete = Set(itemsToDelete.map(\.id))
        guard !idsToDelete.isEmpty else { return items }

        items.removeAll { item in
            let shouldDelete = idsToDelete.contains(item.id)
            if shouldDelete {
                assetStore.deleteAssociatedFiles(for: item)
            }
            return shouldDelete
        }

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

    func updatePinState(_ pinState: ClipboardPinState, for targetItems: [ClipboardItem]) -> [ClipboardItem] {
        let ids = Set(targetItems.map(\.id))
        guard !ids.isEmpty else { return items }

        let timestamp = pinState.isPinned ? Date() : nil
        var didChange = false

        for index in items.indices where ids.contains(items[index].id) {
            if items[index].isPinned != pinState.isPinned || items[index].pinnedAt != timestamp {
                items[index].isPinned = pinState.isPinned
                items[index].pinnedAt = timestamp
                didChange = true
            }
        }

        if didChange {
            persist()
        }

        return items
    }

    func setOCRText(_ text: String, for item: ClipboardItem) -> [ClipboardItem] {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return items }
        items[index] = items[index].updatingOCRText(text)
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

    func pruneExpired(before cutoff: Date) -> [ClipboardItem] {
        let expiredItems = items.filter { $0.timestamp < cutoff }
        guard !expiredItems.isEmpty else { return items }

        for item in expiredItems {
            assetStore.deleteAssociatedFiles(for: item)
        }

        items.removeAll { $0.timestamp < cutoff }
        persist()
        return items
    }

    private func persist() {
        persistence.saveHistory(items)
    }
}
