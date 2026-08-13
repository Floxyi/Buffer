import Foundation

struct HistoryDeleteRequest: Equatable, Sendable {
    let items: [ClipboardItem]
    let preferredSelectionID: UUID?

    var selectionCount: Int { items.count }
}

@MainActor
struct HistoryItemMutationController {
    func makeDeleteRequest(
        for items: [ClipboardItem],
        in filteredItems: [ClipboardItem],
        selectionController: HistorySelectionController
    ) -> HistoryDeleteRequest? {
        guard !items.isEmpty else { return nil }

        return HistoryDeleteRequest(
            items: items,
            preferredSelectionID: selectionController.preferredSelectionID(
                afterDeleting: items,
                from: filteredItems
            )
        )
    }

    func delete(
        _ request: HistoryDeleteRequest,
        store: ClipboardStore,
        setPendingPreferredSelectionID: (UUID?) -> Void
    ) {
        guard !request.items.isEmpty else { return }

        setPendingPreferredSelectionID(request.preferredSelectionID)
        store.delete(request.items)
    }

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
        guard let request = makeDeleteRequest(
            for: [item],
            in: filteredItems,
            selectionController: selectionController
        ) else { return }
        delete(
            request,
            store: store,
            setPendingPreferredSelectionID: setPendingPreferredSelectionID
        )
    }

    func deleteContextMenuTarget(
        _ targets: [ClipboardItem],
        filteredItems: [ClipboardItem],
        selectionController: HistorySelectionController,
        store: ClipboardStore,
        setPendingPreferredSelectionID: (UUID?) -> Void
    ) {
        guard let request = makeDeleteRequest(
            for: targets,
            in: filteredItems,
            selectionController: selectionController
        ) else { return }
        delete(
            request,
            store: store,
            setPendingPreferredSelectionID: setPendingPreferredSelectionID
        )
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
