import Foundation
import SwiftUI

enum ClipboardListCoordinateSpace {
    static let content = "ClipboardListViewContentCoordinateSpace"
}

struct ClipboardListViewState {
    let items: [ClipboardItem]
    let itemsSnapshotID: UUID
    let selectedIDs: Set<UUID>
    let quickPasteBadgeNumberByItemID: [UUID: Int]
    let searchResultsByItemID: [UUID: ClipboardSearchResult]
    let queryText: String

    var contentSnapshot: ClipboardListContentSnapshot {
        ClipboardListContentSnapshot(
            id: itemsSnapshotID,
            items: items
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
