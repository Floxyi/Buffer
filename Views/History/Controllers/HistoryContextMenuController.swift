import Foundation

struct HistoryContextMenuController {
    func targetItems(
        for clickedItemID: UUID,
        itemByID: [UUID: ClipboardItem],
        selectedIDs: Set<UUID>,
        selectedItemsInActionOrder: [ClipboardItem]
    ) -> [ClipboardItem] {
        if selectedIDs.contains(clickedItemID) {
            return selectedItemsInActionOrder
        }

        guard let item = itemByID[clickedItemID] else {
            return []
        }

        return [item]
    }

    func actions(
        for clickedItemID: UUID,
        itemByID: [UUID: ClipboardItem],
        selectedIDs: Set<UUID>,
        selectedItemsInActionOrder: [ClipboardItem],
        allowsJumpToHistory: Bool,
        isExtractingText: Bool,
        actionResolver: HistoryActionResolver
    ) -> [HistoryItemActionDescriptor] {
        actionResolver.resolveActions(
            for: targetItems(
                for: clickedItemID,
                itemByID: itemByID,
                selectedIDs: selectedIDs,
                selectedItemsInActionOrder: selectedItemsInActionOrder
            ),
            allowsJumpToHistory: allowsJumpToHistory,
            isExtractingText: isExtractingText
        )
    }

}
