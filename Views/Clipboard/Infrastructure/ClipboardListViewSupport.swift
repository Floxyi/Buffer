import Foundation
import SwiftUI

enum ClipboardListCoordinateSpace {
    static let content = "ClipboardListViewContentCoordinateSpace"
}

struct SearchResultAnimationPolicy: Sendable {
    let insertion: Animation?
    let removal: Animation?
    let usesStagger: Bool
    let usesRowOffset: Bool

    static func make(resultCount: Int, reduceMotion: Bool) -> Self {
        if reduceMotion {
            return Self(
                insertion: .easeOut(duration: 0.10),
                removal: nil,
                usesStagger: false,
                usesRowOffset: false
            )
        }
        if resultCount <= 200 {
            return Self(
                insertion: .easeOut(duration: 0.16),
                removal: .easeOut(duration: 0.08),
                usesStagger: true,
                usesRowOffset: true
            )
        }
        return Self(
            insertion: .easeOut(duration: 0.12),
            removal: nil,
            usesStagger: false,
            usesRowOffset: false
        )
    }
}

struct ClipboardListViewState {
    let items: [ClipboardItem]
    let itemsSnapshotID: UUID
    let selectedIDs: Set<UUID>
    let quickPasteBadgeNumberByItemID: [UUID: Int]
    let searchResultsByItemID: [UUID: ClipboardSearchHit]
    let queryText: String
    let committedQueryText: String
    let preparedDisplayCache: ClipboardListStructure.DisplayCache
    let allowsPinnedReordering: Bool

    var contentSnapshot: ClipboardListContentSnapshot {
        ClipboardListContentSnapshot(
            id: itemsSnapshotID,
            items: items,
            displayCache: preparedDisplayCache
        )
    }
}

/// The authoritative item payload for one query publication. Equality intentionally
/// uses the snapshot identity: the payload lets lifecycle callbacks consume the
/// exact items associated with the new query publication instead of recapturing stale
/// SwiftUI view values.
struct ClipboardListContentSnapshot: Equatable {
    let id: UUID
    let items: [ClipboardItem]
    let displayCache: ClipboardListStructure.DisplayCache

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

struct ClipboardListNavigationState {
    var openScrollRequest: HistoryOpenListScrollRequest?
    var openScrollRequestToken = 0
    var isShowingFullHistory = false
    var jumpScrollRequest: HistoryJumpToHistoryRequest?
}

struct ClipboardListActions {
    let commitSelection: () -> Void
    let selectSingle: (UUID, Int) -> Void
    let selectPreferredTopItem: () -> UUID?
    let toggleSelection: (UUID) -> Void
    let extendSelection: (UUID) -> Void
    let contextMenuActions: (UUID) -> [HistoryItemActionDescriptor]
    let performContextMenuAction: (UUID, HistoryItemAction) -> Void
    let jumpScrollStarted: (HistoryJumpToHistoryRequest) -> Void
    let jumpScrollCompleted: (HistoryJumpToHistoryRequest, Bool) -> Void
    let scrollOffsetProviderChanged: (((() -> CGFloat)?) -> Void)
    let scrollOffsetRestorerChanged: ((((CGFloat) -> Void)?) -> Void)
    let visibleItemIDsChanged: ([UUID]) -> Void
    let reorderPinnedItems: (ClipboardPinnedReorderRequest) async -> Bool
}

struct ClipboardScrollTargetFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

func clipboardListScrollID(for itemID: UUID) -> String {
    "item-\(itemID.uuidString)"
}
