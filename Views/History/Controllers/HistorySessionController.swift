import Foundation

struct HistorySessionController {
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
        currentSearchText: String
    ) -> HistoryJumpToHistoryPlan {
        return HistoryJumpToHistoryPlan(
            searchText: currentSearchText.isEmpty ? nil : "",
            preferredSelectionID: itemID
        )
    }

    func clearedSearchText(currentSearchText: String, shouldKeepSearchText: Bool) -> String? {
        guard !shouldKeepSearchText, !currentSearchText.isEmpty else { return nil }
        return ""
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
