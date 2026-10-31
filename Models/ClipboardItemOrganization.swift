import Foundation

enum ClipboardPinState: Sendable {
    case pinned
    case unpinned

    var isPinned: Bool {
        self == .pinned
    }
}

enum ClipboardBookmarkState: Sendable {
    case bookmarked
    case notBookmarked

    var isBookmarked: Bool {
        self == .bookmarked
    }
}

struct ClipboardPinnedReorderRequest: Equatable, Sendable {
    let movingItemIDs: [UUID]
    let destination: ClipboardPinnedReorderDestination
}

enum ClipboardPinnedReorderDestination: Equatable, Sendable {
    case before(UUID)
    case end
}

struct ClipboardPinnedOrderResolver: Sendable {
    func reorderedItemIDs(
        currentItemIDs: [UUID],
        request: ClipboardPinnedReorderRequest
    ) -> [UUID]? {
        guard currentItemIDs.count > 1 else { return nil }

        let requestedIDs = Set(request.movingItemIDs)
        let movingItemIDs = currentItemIDs.filter(requestedIDs.contains)
        guard !movingItemIDs.isEmpty else { return nil }

        let movingIDSet = Set(movingItemIDs)
        var remainingItemIDs = currentItemIDs.filter { !movingIDSet.contains($0) }
        let insertionIndex = resolvedInsertionIndex(
            destination: request.destination,
            currentItemIDs: currentItemIDs,
            remainingItemIDs: remainingItemIDs,
            movingItemIDs: movingIDSet
        )
        remainingItemIDs.insert(contentsOf: movingItemIDs, at: insertionIndex)

        return remainingItemIDs == currentItemIDs ? nil : remainingItemIDs
    }

    private func resolvedInsertionIndex(
        destination: ClipboardPinnedReorderDestination,
        currentItemIDs: [UUID],
        remainingItemIDs: [UUID],
        movingItemIDs: Set<UUID>
    ) -> Int {
        switch destination {
        case .end:
            return remainingItemIDs.endIndex

        case .before(let destinationID):
            let resolvedDestinationID: UUID?
            if movingItemIDs.contains(destinationID) {
                let destinationIndex = currentItemIDs.firstIndex(of: destinationID)
                resolvedDestinationID = destinationIndex.flatMap { index in
                    currentItemIDs[currentItemIDs.index(after: index)...]
                        .first { !movingItemIDs.contains($0) }
                }
            } else {
                resolvedDestinationID = destinationID
            }

            guard let resolvedDestinationID,
                let insertionIndex = remainingItemIDs.firstIndex(of: resolvedDestinationID)
            else {
                return remainingItemIDs.endIndex
            }
            return insertionIndex
        }
    }
}

enum ClipboardItemProtectionReason: Hashable, Sendable {
    case pinned
    case bookmarked
}

struct ClipboardDeletionPartition: Equatable, Sendable {
    let deletable: [ClipboardItem]
    let protected: [ClipboardItem]
}

struct ClipboardDeletionPolicy: Sendable {
    func partition(_ items: [ClipboardItem]) -> ClipboardDeletionPartition {
        var deletable: [ClipboardItem] = []
        var protected: [ClipboardItem] = []
        deletable.reserveCapacity(items.count)
        protected.reserveCapacity(items.count)

        for item in items {
            if item.isProtectedFromDeletion {
                protected.append(item)
            } else {
                deletable.append(item)
            }
        }

        return ClipboardDeletionPartition(
            deletable: deletable,
            protected: protected
        )
    }

    func canDelete(_ item: ClipboardItem) -> Bool {
        !item.isProtectedFromDeletion
    }
}

extension ClipboardItem {
    var deletionProtectionReasons: Set<ClipboardItemProtectionReason> {
        var reasons: Set<ClipboardItemProtectionReason> = []
        if isPinned {
            reasons.insert(.pinned)
        }
        if isBookmarked {
            reasons.insert(.bookmarked)
        }
        return reasons
    }

    var isProtectedFromDeletion: Bool {
        isPinned || isBookmarked
    }
}
