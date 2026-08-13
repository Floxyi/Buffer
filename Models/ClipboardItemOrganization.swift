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
