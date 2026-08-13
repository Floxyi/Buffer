import Foundation

struct HistorySelectionState: Equatable {
    var selectedIDs: Set<UUID> = []
    var selectedActionOrderIDs: [UUID] = []
    var selectedIndex = 0
    var selectedID: UUID?
    var selectionAnchor: UUID?
}

struct HistorySelectionController {
    private let rangeController = HistorySelectionRangeController()
    private let deleteSelectionResolver = HistoryDeleteSelectionResolver()

    func syncSelection(
        state: HistorySelectionState,
        in filteredItems: [ClipboardItem],
        preferredID: UUID?,
        preferredTopSelectionID: UUID?
    ) -> HistorySelectionState {
        var nextState = state

        guard !filteredItems.isEmpty else {
            return clearSelection()
        }

        let validIDs = Set(filteredItems.map(\.id))
        nextState.selectedIDs = nextState.selectedIDs.intersection(validIDs)
        nextState.selectedActionOrderIDs.removeAll { !validIDs.contains($0) }

        if let preferredID,
            validIDs.contains(preferredID),
            let index = filteredItems.firstIndex(where: { $0.id == preferredID })
        {
            return applySingleSelection(
                preferredID,
                index: index,
                in: filteredItems,
                state: nextState
            )
        }

        if !nextState.selectedIDs.isEmpty {
            if nextState.selectedActionOrderIDs.isEmpty {
                nextState.selectedActionOrderIDs = selectedItems(
                    in: filteredItems,
                    selectedIDs: nextState.selectedIDs
                ).map(\.id)
            }

            if let currentSelectedID = nextState.selectedID,
                validIDs.contains(currentSelectedID),
                let index = filteredItems.firstIndex(where: { $0.id == currentSelectedID })
            {
                nextState.selectedIndex = index
            } else if let fallbackID = nextState.selectedActionOrderIDs.first
                ?? selectedItems(in: filteredItems, selectedIDs: nextState.selectedIDs).first?.id,
                let fallbackIndex = filteredItems.firstIndex(where: { $0.id == fallbackID })
            {
                nextState.selectedID = fallbackID
                nextState.selectedIndex = fallbackIndex
            }

            nextState.selectionAnchor =
                nextState.selectionAnchor.flatMap {
                    validIDs.contains($0) ? $0 : nil
                } ?? nextState.selectedID

            return nextState
        }

        let targetID = nextState.selectedID.flatMap { validIDs.contains($0) ? $0 : nil } ?? preferredTopSelectionID
        guard let targetID,
            let index = filteredItems.firstIndex(where: { $0.id == targetID })
        else {
            return nextState
        }

        return applySingleSelection(targetID, index: index, in: filteredItems, state: nextState)
    }

    func applySingleSelection(
        _ id: UUID,
        index: Int? = nil,
        in filteredItems: [ClipboardItem],
        state: HistorySelectionState
    ) -> HistorySelectionState {
        var nextState = state
        nextState.selectedIDs = [id]
        nextState.selectedActionOrderIDs = [id]
        nextState.selectionAnchor = id
        nextState.selectedID = id

        if let index {
            nextState.selectedIndex = index
        } else if let index = filteredItems.firstIndex(where: { $0.id == id }) {
            nextState.selectedIndex = index
        }

        return nextState
    }

    func clearSelection() -> HistorySelectionState {
        HistorySelectionState()
    }

    func toggleSelection(
        _ id: UUID,
        in filteredItems: [ClipboardItem],
        state: HistorySelectionState
    ) -> HistorySelectionState {
        var nextState = state

        if nextState.selectedIDs.contains(id) {
            nextState.selectedIDs.remove(id)
            nextState.selectedActionOrderIDs.removeAll { $0 == id }
        } else {
            nextState.selectedIDs.insert(id)
            nextState.selectedActionOrderIDs.append(id)
        }

        guard !nextState.selectedIDs.isEmpty else {
            return clearSelection()
        }

        if let index = filteredItems.firstIndex(where: { $0.id == id }) {
            if nextState.selectedIDs.contains(id) {
                nextState.selectedIndex = index
                nextState.selectedID = id
                nextState.selectionAnchor = id
            } else {
                nextState.selectedID = nearestSelectedID(
                    around: index,
                    in: filteredItems,
                    selectedIDs: nextState.selectedIDs
                )
                nextState.selectionAnchor = nextState.selectedID
                if let selectedID = nextState.selectedID,
                    let selectedIndex = filteredItems.firstIndex(where: { $0.id == selectedID })
                {
                    nextState.selectedIndex = selectedIndex
                }
            }
        }

        return nextState
    }

    func extendSelection(
        to targetID: UUID,
        targetIndex: Int? = nil,
        in filteredItems: [ClipboardItem],
        state: HistorySelectionState
    ) -> HistorySelectionState {
        rangeController.extendSelection(
            to: targetID,
            targetIndex: targetIndex,
            in: filteredItems,
            state: state,
            applySingleSelection: { id, items, nextState in
                applySingleSelection(id, in: items, state: nextState)
            }
        )
    }

    func selectAll(
        in filteredItems: [ClipboardItem],
        state: HistorySelectionState
    ) -> HistorySelectionState {
        guard !filteredItems.isEmpty else { return clearSelection() }

        var nextState = state
        let focusedIndex =
            filteredItems.indices.contains(state.selectedIndex)
            ? state.selectedIndex
            : 0
        let focusedID = filteredItems[focusedIndex].id
        let allIDs = filteredItems.map(\.id)

        nextState.selectedIDs = Set(allIDs)
        nextState.selectedActionOrderIDs = allIDs
        nextState.selectedIndex = focusedIndex
        nextState.selectedID = focusedID
        nextState.selectionAnchor = focusedID
        return nextState
    }

    func preferredSelectionID(
        afterDeleting items: [ClipboardItem],
        from filteredItems: [ClipboardItem]
    ) -> UUID? {
        deleteSelectionResolver.preferredSelectionID(afterDeleting: items, from: filteredItems)
    }

    func selectedItems(in filteredItems: [ClipboardItem], selectedIDs: Set<UUID>) -> [ClipboardItem] {
        filteredItems.filter { selectedIDs.contains($0.id) }
    }

    private func nearestSelectedID(
        around index: Int,
        in filteredItems: [ClipboardItem],
        selectedIDs: Set<UUID>
    ) -> UUID? {
        guard !selectedIDs.isEmpty else { return nil }

        if let next = filteredItems[index...].first(where: { selectedIDs.contains($0.id) }) {
            return next.id
        }

        if index > 0 {
            return filteredItems[0..<index].last(where: { selectedIDs.contains($0.id) })?.id
        }

        return nil
    }
}
