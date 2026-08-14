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
        ocrProcessingItemIDs: Set<UUID>,
        actionResolver: HistoryActionResolver
    ) -> [HistoryItemActionDescriptor] {
        let targets = targetItems(
            for: clickedItemID,
            itemByID: itemByID,
            selectedIDs: selectedIDs,
            selectedItemsInActionOrder: selectedItemsInActionOrder
        )
        return actionResolver.resolveActions(
            for: targets,
            allowsJumpToHistory: allowsJumpToHistory,
            isExtractingText: targets.contains { ocrProcessingItemIDs.contains($0.id) }
        )
    }

}
