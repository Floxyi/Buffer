import Foundation

@MainActor
struct HistoryVisibleItemsUpdate {
    var filteredItems: [ClipboardItem]
    var preferredSelectionID: UUID?
    var sessionState: HistorySessionState
}

@MainActor
struct HistoryVisibleItemsController {
    private let itemFilter = HistoryItemFilter()

    func initialFilteredItems(
        from items: [ClipboardItem],
        store: ClipboardStore
    ) -> [ClipboardItem] {
        rebuildFilteredItems(from: items, searchText: "", store: store)
    }

    func rebuildFilteredItems(
        from items: [ClipboardItem],
        searchText: String,
        store: ClipboardStore
    ) -> [ClipboardItem] {
        itemFilter.filteredItems(from: items, query: searchText, store: store)
    }

    func handleStoreItemsChange(
        items: [ClipboardItem],
        searchText: String,
        store: ClipboardStore,
        sessionState: HistorySessionState
    ) -> HistoryVisibleItemsUpdate {
        var nextState = sessionState
        let preferredSelectionID = nextState.pendingPreferredSelectionID
        nextState.pendingPreferredSelectionID = nil

        return HistoryVisibleItemsUpdate(
            filteredItems: rebuildFilteredItems(
                from: items,
                searchText: searchText,
                store: store
            ),
            preferredSelectionID: preferredSelectionID,
            sessionState: nextState
        )
    }
}
