import Foundation

struct HistorySessionState {
    var isApplyingProgrammaticSearchChange = false
    var pendingPreferredSelectionID: UUID?
}

struct HistoryWindowOpenPlan {
    var shouldIncrementSearchSelectionToken: Bool
    var shouldFocusSearchOnOpen: Bool
    var selectionPreference: HistorySelectionPreference
    var openListScrollRequest: HistoryOpenListScrollRequest?

    enum HistorySelectionPreference {
        case keepCurrentOrSelectTop
        case selectPreferred(UUID?)
    }
}

struct HistoryJumpToHistoryPlan {
    var searchText: String?
    var shouldRebuildFilteredItems: Bool
    var preferredSelectionID: UUID?
    var state: HistorySessionState
}

