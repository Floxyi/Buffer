import Foundation

struct HistorySessionController {
    func handleSearchTextChange(state: HistorySessionState) -> (shouldRebuildFilteredItems: Bool, state: HistorySessionState) {
        guard state.isApplyingProgrammaticSearchChange else {
            return (true, state)
        }

        var nextState = state
        nextState.isApplyingProgrammaticSearchChange = false
        return (false, nextState)
    }

    func makeWindowOpenPlan(
        searchText: String,
        focusSearch: Bool,
        currentSelectionIsEmpty: Bool,
        selectedID: UUID?,
        filteredItems: [ClipboardItem],
        historyWindowOpenBehavior: HistoryWindowOpenBehavior
    ) -> HistoryWindowOpenPlan {
        let preferredTopSelectionID = preferredTopSelectionID(
            in: filteredItems,
            historyWindowOpenBehavior: historyWindowOpenBehavior
        )

        switch historyWindowOpenBehavior {
        case .keepLastSelection:
            return HistoryWindowOpenPlan(
                shouldIncrementSearchSelectionToken: !searchText.isEmpty,
                shouldFocusSearchOnOpen: focusSearch,
                selectionPreference: currentSelectionIsEmpty
                    ? .selectPreferred(selectedID ?? preferredTopSelectionID)
                    : .keepCurrentOrSelectTop,
                openListScrollRequest: nil
            )
        case .selectFirstNonPinnedItem, .selectAnyFirstItem:
            return HistoryWindowOpenPlan(
                shouldIncrementSearchSelectionToken: !searchText.isEmpty,
                shouldFocusSearchOnOpen: focusSearch,
                selectionPreference: .selectPreferred(preferredTopSelectionID),
                openListScrollRequest: HistoryOpenListScrollRequest(mode: .scrollToTop)
            )
        }
    }

    func makeJumpToHistoryPlan(
        for itemID: UUID,
        currentSearchText: String,
        state: HistorySessionState
    ) -> HistoryJumpToHistoryPlan {
        guard !currentSearchText.isEmpty else {
            return HistoryJumpToHistoryPlan(
                searchText: nil,
                shouldRebuildFilteredItems: false,
                preferredSelectionID: itemID,
                state: state
            )
        }

        var nextState = state
        nextState.isApplyingProgrammaticSearchChange = true

        return HistoryJumpToHistoryPlan(
            searchText: "",
            shouldRebuildFilteredItems: true,
            preferredSelectionID: itemID,
            state: nextState
        )
    }

    func clearedSearchText(currentSearchText: String, shouldKeepSearchText: Bool) -> String? {
        guard !shouldKeepSearchText, !currentSearchText.isEmpty else { return nil }
        return ""
    }

    func setPendingPreferredSelectionID(
        _ preferredSelectionID: UUID?,
        state: HistorySessionState
    ) -> HistorySessionState {
        var nextState = state
        nextState.pendingPreferredSelectionID = preferredSelectionID
        return nextState
    }

    func consumePendingPreferredSelectionID(
        state: HistorySessionState
    ) -> (preferredSelectionID: UUID?, state: HistorySessionState) {
        var nextState = state
        let preferredSelectionID = nextState.pendingPreferredSelectionID
        nextState.pendingPreferredSelectionID = nil
        return (preferredSelectionID, nextState)
    }

    func preferredTopSelectionID(
        in filteredItems: [ClipboardItem],
        historyWindowOpenBehavior: HistoryWindowOpenBehavior
    ) -> UUID? {
        if historyWindowOpenBehavior == .selectFirstNonPinnedItem {
            return filteredItems.first(where: { !$0.isPinned })?.id ?? filteredItems.first?.id
        }

        return filteredItems.first?.id
    }
}
