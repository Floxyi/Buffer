import Foundation

actor ClipboardRepository {
    private var items: [ClipboardItem]
    private let persistence: any ClipboardHistoryPersisting
    private let assetStore: ClipboardAssetStore
    private let deletionPolicy = ClipboardDeletionPolicy()

    init(
        initialItems: [ClipboardItem],
        persistence: any ClipboardHistoryPersisting,
        assetStore: ClipboardAssetStore
    ) {
        self.items = initialItems
        self.persistence = persistence
        self.assetStore = assetStore
    }

    func snapshot() -> [ClipboardItem] {
        items
    }

    func add(
        _ item: ClipboardItem,
        maxItems: Int,
        expirationCutoff: Date?
    ) throws -> [ClipboardItem] {
        var nextItems = items
        nextItems.insert(item, at: 0)

        var removedItems: [ClipboardItem] = []
        if let expirationCutoff {
            let expiredItems = nextItems.filter {
                $0.timestamp < expirationCutoff && deletionPolicy.canDelete($0)
            }
            let expiredIDs = Set(expiredItems.map(\.id))
            nextItems.removeAll { expiredIDs.contains($0.id) }
            removedItems.append(contentsOf: expiredItems)
        }

        while nextItems.count > maxItems {
            if let indexToRemove = nextItems.lastIndex(where: deletionPolicy.canDelete) {
                removedItems.append(nextItems.remove(at: indexToRemove))
            } else {
                break
            }
        }

        do {
            return try commit(nextItems, removingAssetsFor: removedItems)
        } catch {
            assetStore.deleteAssociatedFiles(for: item)
            throw error
        }
    }

    func delete(_ item: ClipboardItem) throws -> [ClipboardItem] {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
            deletionPolicy.canDelete(items[index])
        else {
            return items
        }

        var nextItems = items
        let removed = nextItems.remove(at: index)
        return try commit(nextItems, removingAssetsFor: [removed])
    }

    func delete(_ itemsToDelete: [ClipboardItem]) throws -> [ClipboardItem] {
        let requestedIDs = Set(itemsToDelete.map(\.id))
        guard !requestedIDs.isEmpty else { return items }

        let removedItems = items.filter {
            requestedIDs.contains($0.id) && deletionPolicy.canDelete($0)
        }
        let removedIDs = Set(removedItems.map(\.id))
        let nextItems = items.filter { !removedIDs.contains($0.id) }
        return try commit(nextItems, removingAssetsFor: removedItems)
    }

    func togglePin(for item: ClipboardItem) throws -> [ClipboardItem] {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return items }

        var nextItems = items
        nextItems[index].isPinned.toggle()
        nextItems[index].pinnedAt = nextItems[index].isPinned ? Date() : nil
        return try commit(nextItems)
    }

    func updatePinState(_ pinState: ClipboardPinState, for targetItems: [ClipboardItem]) throws -> [ClipboardItem] {
        let ids = Set(targetItems.map(\.id))
        guard !ids.isEmpty else { return items }

        let timestamp = Date()
        var nextItems = items

        for index in nextItems.indices where ids.contains(nextItems[index].id) {
            let needsUpdate =
                nextItems[index].isPinned != pinState.isPinned
                || (pinState.isPinned && nextItems[index].pinnedAt == nil)
                || (!pinState.isPinned && nextItems[index].pinnedAt != nil)
            guard needsUpdate else { continue }

            nextItems[index].isPinned = pinState.isPinned
            nextItems[index].pinnedAt = pinState.isPinned ? timestamp : nil
        }

        guard nextItems != items else { return items }
        return try commit(nextItems)
    }

    func toggleBookmark(for item: ClipboardItem) throws -> [ClipboardItem] {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return items }

        var nextItems = items
        nextItems[index].isBookmarked.toggle()
        nextItems[index].bookmarkedAt = nextItems[index].isBookmarked ? Date() : nil
        return try commit(nextItems)
    }

    func updateBookmarkState(
        _ bookmarkState: ClipboardBookmarkState,
        for targetItems: [ClipboardItem]
    ) throws -> [ClipboardItem] {
        let ids = Set(targetItems.map(\.id))
        guard !ids.isEmpty else { return items }

        let timestamp = Date()
        var nextItems = items

        for index in nextItems.indices where ids.contains(nextItems[index].id) {
            let needsUpdate =
                nextItems[index].isBookmarked != bookmarkState.isBookmarked
                || (bookmarkState.isBookmarked && nextItems[index].bookmarkedAt == nil)
                || (!bookmarkState.isBookmarked && nextItems[index].bookmarkedAt != nil)
            guard needsUpdate else { continue }

            nextItems[index].isBookmarked = bookmarkState.isBookmarked
            nextItems[index].bookmarkedAt = bookmarkState.isBookmarked ? timestamp : nil
        }

        guard nextItems != items else { return items }
        return try commit(nextItems)
    }

    func setOCRText(_ text: String, for item: ClipboardItem) throws -> [ClipboardItem] {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return items }
        var nextItems = items
        nextItems[index] = nextItems[index].updatingOCRText(text)
        return try commit(nextItems)
    }

    func moveToTop(_ item: ClipboardItem) throws -> [ClipboardItem] {
        guard let index = items.firstIndex(where: { $0.id == item.id }), index != 0 else { return items }
        var nextItems = items
        let removed = nextItems.remove(at: index)
        nextItems.insert(removed, at: 0)
        return try commit(nextItems)
    }

    func clear() throws -> [ClipboardItem] {
        let partition = deletionPolicy.partition(items)
        return try commit(partition.protected, removingAssetsFor: partition.deletable)
    }

    func trim(to maxItems: Int) throws -> [ClipboardItem] {
        var nextItems = items
        var removedItems: [ClipboardItem] = []
        while nextItems.count > maxItems {
            if let index = nextItems.lastIndex(where: deletionPolicy.canDelete) {
                removedItems.append(nextItems.remove(at: index))
            } else {
                break
            }
        }

        guard nextItems != items else { return items }
        return try commit(nextItems, removingAssetsFor: removedItems)
    }

    func pruneExpired(before cutoff: Date) throws -> [ClipboardItem] {
        let expiredItems = items.filter {
            $0.timestamp < cutoff && deletionPolicy.canDelete($0)
        }
        guard !expiredItems.isEmpty else { return items }

        let expiredIDs = Set(expiredItems.map(\.id))
        let nextItems = items.filter { !expiredIDs.contains($0.id) }
        return try commit(nextItems, removingAssetsFor: expiredItems)
    }

    private func commit(
        _ nextItems: [ClipboardItem],
        removingAssetsFor removedItems: [ClipboardItem] = []
    ) throws -> [ClipboardItem] {
        try persistence.saveHistory(nextItems)
        items = nextItems
        for item in removedItems {
            assetStore.deleteAssociatedFiles(for: item)
        }
        return items
    }
}
