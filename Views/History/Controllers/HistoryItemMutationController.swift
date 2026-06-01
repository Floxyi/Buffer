import Foundation

@MainActor
struct HistoryItemMutationController {
    func togglePinForSelectedItems(
        _ items: [ClipboardItem],
        selectedID: UUID?,
        store: ClipboardStore,
        syncSelection: (UUID?) -> Void
    ) {
        guard !items.isEmpty else { return }

        let pinState: ClipboardPinState = items.allSatisfy(\.isPinned) ? .unpinned : .pinned
        let preferredID = selectedID ?? items.first?.id
        store.updatePinState(pinState, for: items)
        syncSelection(preferredID)
    }

    func deleteSelectedItems(
        _ items: [ClipboardItem],
        filteredItems: [ClipboardItem],
        selectionController: HistorySelectionController,
        store: ClipboardStore,
        setPendingPreferredSelectionID: (UUID?) -> Void
    ) {
        guard !items.isEmpty else { return }

        setPendingPreferredSelectionID(
            selectionController.preferredSelectionID(afterDeleting: items, from: filteredItems)
        )
        store.delete(items)
    }

    func togglePin(
        for item: ClipboardItem,
        selectSingle: (UUID) -> Void,
        store: ClipboardStore,
        syncSelection: (UUID?) -> Void
    ) {
        selectSingle(item.id)
        store.togglePin(for: item)
        syncSelection(item.id)
    }

    func delete(
        _ item: ClipboardItem,
        filteredItems: [ClipboardItem],
        selectionController: HistorySelectionController,
        selectSingle: (UUID) -> Void,
        store: ClipboardStore,
        setPendingPreferredSelectionID: (UUID?) -> Void
    ) {
        selectSingle(item.id)
        setPendingPreferredSelectionID(
            selectionController.preferredSelectionID(afterDeleting: [item], from: filteredItems)
        )
        store.delete(item)
    }

    func deleteContextMenuTarget(
        _ targets: [ClipboardItem],
        filteredItems: [ClipboardItem],
        selectionController: HistorySelectionController,
        store: ClipboardStore,
        setPendingPreferredSelectionID: (UUID?) -> Void
    ) {
        guard !targets.isEmpty else { return }

        setPendingPreferredSelectionID(
            selectionController.preferredSelectionID(afterDeleting: targets, from: filteredItems)
        )
        store.delete(targets)
    }

    func togglePinForContextMenuTarget(
        _ targets: [ClipboardItem],
        clickedItemID: UUID,
        selectedIDs: Set<UUID>,
        selectedID: UUID?,
        store: ClipboardStore,
        syncSelection: (UUID?) -> Void
    ) {
        guard !targets.isEmpty else { return }

        let pinState: ClipboardPinState = targets.allSatisfy(\.isPinned) ? .unpinned : .pinned
        let preferredID = selectedIDs.contains(clickedItemID) ? (selectedID ?? clickedItemID) : clickedItemID
        store.updatePinState(pinState, for: targets)
        syncSelection(preferredID)
    }
}
