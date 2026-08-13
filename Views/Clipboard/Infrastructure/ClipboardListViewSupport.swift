import Foundation
import SwiftUI

enum ClipboardListCoordinateSpace {
    static let content = "ClipboardListViewContentCoordinateSpace"
}

struct ClipboardListViewState {
    let items: [ClipboardItem]
    let itemsRevision: UInt
    let selectedIDs: Set<UUID>
    let quickPasteBadgeNumberByItemID: [UUID: Int]
    let searchResultsByItemID: [UUID: ClipboardSearchResult]
    let queryText: String
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
