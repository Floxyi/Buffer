import Foundation

struct HistoryContextMenuController {
    func targetItems(
        for clickedItemID: UUID,
        filteredItems: [ClipboardItem],
        selectedIDs: Set<UUID>,
        selectedItemsInActionOrder: [ClipboardItem]
    ) -> [ClipboardItem] {
        let itemsByID = Dictionary(uniqueKeysWithValues: filteredItems.map { ($0.id, $0) })

        if selectedIDs.contains(clickedItemID) {
            return selectedItemsInActionOrder
        }

        guard let item = itemsByID[clickedItemID] else {
            return []
        }

        return [item]
    }

    func visualTargetItems(
        for clickedItemID: UUID,
        filteredItems: [ClipboardItem],
        selectedIDs: Set<UUID>,
        selectedItemsInActionOrder: [ClipboardItem]
    ) -> [ClipboardItem] {
        let targetIDs = Set(
            targetItems(
                for: clickedItemID,
                filteredItems: filteredItems,
                selectedIDs: selectedIDs,
                selectedItemsInActionOrder: selectedItemsInActionOrder
            ).map(\.id)
        )
        return filteredItems.filter { targetIDs.contains($0.id) }
    }

    func actions(
        for clickedItemID: UUID,
        filteredItems: [ClipboardItem],
        selectedIDs: Set<UUID>,
        selectedItemsInActionOrder: [ClipboardItem],
        searchText: String,
        isExtractingText: Bool,
        actionResolver: HistoryActionResolver
    ) -> [HistoryItemActionDescriptor] {
        actionResolver.resolveActions(
            for: targetItems(
                for: clickedItemID,
                filteredItems: filteredItems,
                selectedIDs: selectedIDs,
                selectedItemsInActionOrder: selectedItemsInActionOrder
            ),
            allowsJumpToHistory: !searchText.isEmpty,
            isExtractingText: isExtractingText
        )
    }

    func shouldShowUnpin(
        for clickedItemID: UUID,
        filteredItems: [ClipboardItem],
        selectedIDs: Set<UUID>,
        selectedItemsInActionOrder: [ClipboardItem]
    ) -> Bool {
        let targets = targetItems(
            for: clickedItemID,
            filteredItems: filteredItems,
            selectedIDs: selectedIDs,
            selectedItemsInActionOrder: selectedItemsInActionOrder
        )
        return !targets.isEmpty && targets.allSatisfy(\.isPinned)
    }
}
