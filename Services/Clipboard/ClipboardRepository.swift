import Foundation

struct ClipboardRepositoryMutation: Sendable {
    let historyRevision: UInt64
    let snapshot: [ClipboardItem]
    let searchChangeSet: ClipboardSearchChangeSet

    static func unchanged(
        _ snapshot: [ClipboardItem],
        historyRevision: UInt64
    ) -> ClipboardRepositoryMutation {
        ClipboardRepositoryMutation(
            historyRevision: historyRevision,
            snapshot: snapshot,
            searchChangeSet: ClipboardSearchChangeSet(
                historyRevision: historyRevision,
                changes: []
            )
        )
    }
}

actor ClipboardRepository {
    private var items: [ClipboardItem]
    private let persistence: any ClipboardHistoryPersisting
    private let assetStore: ClipboardAssetStore
    private let deletionPolicy = ClipboardDeletionPolicy()
    // This revision tracks changes that can invalidate a search result. Pure pin/order
    // mutations intentionally keep it stable so they require no search-database write.
    private var searchHistoryRevision: UInt64 = 0

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

    func currentHistoryRevision() -> UInt64 {
        searchHistoryRevision
    }

    func add(
        _ item: ClipboardItem,
        maxItems: Int,
        expirationCutoff: Date?
    ) throws -> ClipboardRepositoryMutation {
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
            let changes =
                [ClipboardSearchChange.insert(item)]
                + removedItems.map { ClipboardSearchChange.remove($0.id) }
            return try commit(
                nextItems,
                removingAssetsFor: removedItems,
                searchChangeSet: ClipboardSearchChangeSet(changes: changes)
            )
        } catch {
            assetStore.deleteAssociatedFiles(for: item)
            throw error
        }
    }

    func delete(_ item: ClipboardItem) throws -> ClipboardRepositoryMutation {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
            deletionPolicy.canDelete(items[index])
        else {
            return .unchanged(items, historyRevision: searchHistoryRevision)
        }

        var nextItems = items
        let removed = nextItems.remove(at: index)
        return try commit(
            nextItems,
            removingAssetsFor: [removed],
            searchChangeSet: ClipboardSearchChangeSet(changes: [.remove(removed.id)])
        )
    }

    func delete(_ itemsToDelete: [ClipboardItem]) throws -> ClipboardRepositoryMutation {
        let requestedIDs = Set(itemsToDelete.map(\.id))
        guard !requestedIDs.isEmpty else { return .unchanged(items, historyRevision: searchHistoryRevision) }

        let removedItems = items.filter {
            requestedIDs.contains($0.id) && deletionPolicy.canDelete($0)
        }
        let removedIDs = Set(removedItems.map(\.id))
        let nextItems = items.filter { !removedIDs.contains($0.id) }
        return try commit(
            nextItems,
            removingAssetsFor: removedItems,
            searchChangeSet: ClipboardSearchChangeSet(
                changes: removedItems.map { .remove($0.id) }
            )
        )
    }

    func togglePin(for item: ClipboardItem) throws -> ClipboardRepositoryMutation {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return .unchanged(items, historyRevision: searchHistoryRevision)
        }

        var nextItems = items
        nextItems[index].isPinned.toggle()
        nextItems[index].pinnedAt = nextItems[index].isPinned ? Date() : nil
        return try commit(nextItems)
    }

    func updatePinState(
        _ pinState: ClipboardPinState,
        for targetItems: [ClipboardItem]
    ) throws -> ClipboardRepositoryMutation {
        let ids = Set(targetItems.map(\.id))
        guard !ids.isEmpty else { return .unchanged(items, historyRevision: searchHistoryRevision) }

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

        guard nextItems != items else { return .unchanged(items, historyRevision: searchHistoryRevision) }
        return try commit(nextItems)
    }

    func reorderPinnedItems(
        _ request: ClipboardPinnedReorderRequest
    ) throws -> ClipboardRepositoryMutation {
        let pinnedIndices = items.indices.filter { items[$0].isPinned }
        let pinnedItems = pinnedIndices.map { items[$0] }
        guard
            let reorderedIDs = ClipboardPinnedOrderResolver().reorderedItemIDs(
                currentItemIDs: pinnedItems.map(\.id),
                request: request
            )
        else {
            return .unchanged(items, historyRevision: searchHistoryRevision)
        }

        let pinnedItemByID = Dictionary(uniqueKeysWithValues: pinnedItems.map { ($0.id, $0) })
        var nextItems = items
        for (index, itemID) in zip(pinnedIndices, reorderedIDs) {
            guard let item = pinnedItemByID[itemID] else {
                assertionFailure("Resolved pin order contains an unknown item")
                return .unchanged(items, historyRevision: searchHistoryRevision)
            }
            nextItems[index] = item
        }

        return try commit(nextItems)
    }

    func toggleBookmark(for item: ClipboardItem) throws -> ClipboardRepositoryMutation {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return .unchanged(items, historyRevision: searchHistoryRevision)
        }

        var nextItems = items
        nextItems[index].isBookmarked.toggle()
        nextItems[index].bookmarkedAt = nextItems[index].isBookmarked ? Date() : nil
        return try commit(
            nextItems,
            searchChangeSet: ClipboardSearchChangeSet(
                changes: [.updateMetadata(nextItems[index])]
            )
        )
    }

    func updateBookmarkState(
        _ bookmarkState: ClipboardBookmarkState,
        for targetItems: [ClipboardItem]
    ) throws -> ClipboardRepositoryMutation {
        let ids = Set(targetItems.map(\.id))
        guard !ids.isEmpty else { return .unchanged(items, historyRevision: searchHistoryRevision) }

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

        guard nextItems != items else { return .unchanged(items, historyRevision: searchHistoryRevision) }
        let updatedItems = nextItems.filter { ids.contains($0.id) }
        return try commit(
            nextItems,
            searchChangeSet: ClipboardSearchChangeSet(
                changes: updatedItems.map(ClipboardSearchChange.updateMetadata)
            )
        )
    }

    func setOCRText(_ text: String, for item: ClipboardItem) throws -> ClipboardRepositoryMutation {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return .unchanged(items, historyRevision: searchHistoryRevision)
        }
        var nextItems = items
        nextItems[index] = nextItems[index].updatingOCRText(text)
        return try commit(
            nextItems,
            searchChangeSet: ClipboardSearchChangeSet(
                changes: [.updateOCR(itemID: nextItems[index].id, text: nextItems[index].ocrText)]
            )
        )
    }

    func moveToTop(_ item: ClipboardItem) throws -> ClipboardRepositoryMutation {
        guard let index = items.firstIndex(where: { $0.id == item.id }), index != 0 else {
            return .unchanged(items, historyRevision: searchHistoryRevision)
        }
        var nextItems = items
        let removed = nextItems.remove(at: index)
        nextItems.insert(removed, at: 0)
        return try commit(nextItems)
    }

    func clear() throws -> ClipboardRepositoryMutation {
        let partition = deletionPolicy.partition(items)
        return try commit(
            partition.protected,
            removingAssetsFor: partition.deletable,
            searchChangeSet: ClipboardSearchChangeSet(changes: [.reset])
        )
    }

    func trim(to maxItems: Int) throws -> ClipboardRepositoryMutation {
        var nextItems = items
        var removedItems: [ClipboardItem] = []
        while nextItems.count > maxItems {
            if let index = nextItems.lastIndex(where: deletionPolicy.canDelete) {
                removedItems.append(nextItems.remove(at: index))
            } else {
                break
            }
        }

        guard nextItems != items else { return .unchanged(items, historyRevision: searchHistoryRevision) }
        return try commit(
            nextItems,
            removingAssetsFor: removedItems,
            searchChangeSet: ClipboardSearchChangeSet(
                changes: removedItems.map { .remove($0.id) }
            )
        )
    }

    func pruneExpired(before cutoff: Date) throws -> ClipboardRepositoryMutation {
        let expiredItems = items.filter {
            $0.timestamp < cutoff && deletionPolicy.canDelete($0)
        }
        guard !expiredItems.isEmpty else { return .unchanged(items, historyRevision: searchHistoryRevision) }

        let expiredIDs = Set(expiredItems.map(\.id))
        let nextItems = items.filter { !expiredIDs.contains($0.id) }
        return try commit(
            nextItems,
            removingAssetsFor: expiredItems,
            searchChangeSet: ClipboardSearchChangeSet(
                changes: expiredItems.map { .remove($0.id) }
            )
        )
    }

    private func commit(
        _ nextItems: [ClipboardItem],
        removingAssetsFor removedItems: [ClipboardItem] = [],
        searchChangeSet: ClipboardSearchChangeSet = .none
    ) throws -> ClipboardRepositoryMutation {
        try persistence.saveHistory(nextItems)
        items = nextItems
        if !searchChangeSet.isEmpty {
            searchHistoryRevision &+= 1
        }
        for item in removedItems {
            assetStore.deleteAssociatedFiles(for: item)
        }
        let resolvedChangeSet = ClipboardSearchChangeSet(
            historyRevision: searchHistoryRevision,
            changes: searchChangeSet.changes
        )
        return ClipboardRepositoryMutation(
            historyRevision: searchHistoryRevision,
            snapshot: items,
            searchChangeSet: resolvedChangeSet
        )
    }
}
