import Foundation

struct HistorySelectionRangeController {
    func extendSelection(
        to targetID: UUID,
        in filteredItems: [ClipboardItem],
        state: HistorySelectionState,
        applySingleSelection: (UUID, [ClipboardItem], HistorySelectionState) -> HistorySelectionState
    ) -> HistorySelectionState {
        guard let anchorID = state.selectionAnchor else {
            return applySingleSelection(targetID, filteredItems, state)
        }

        guard let anchorIndex = filteredItems.firstIndex(where: { $0.id == anchorID }),
              let targetIndex = filteredItems.firstIndex(where: { $0.id == targetID }) else {
            return state
        }

        var nextState = state
        let direction = targetIndex >= anchorIndex ? 1 : -1
        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        let rangeIDs = Set(filteredItems[range].map(\.id))
        let previousSelection = nextState.selectedIDs

        nextState.selectedIDs = rangeIDs
        nextState.selectedActionOrderIDs.removeAll { !rangeIDs.contains($0) }

        let steppedIndices = stride(from: anchorIndex, through: targetIndex, by: direction)
        for index in steppedIndices {
            let id = filteredItems[index].id
            if !previousSelection.contains(id) && !nextState.selectedActionOrderIDs.contains(id) {
                nextState.selectedActionOrderIDs.append(id)
            }
        }

        nextState.selectedIndex = targetIndex
        nextState.selectedID = targetID
        return nextState
    }

    func extendSelectionUp(
        in filteredItems: [ClipboardItem],
        state: HistorySelectionState,
        applySingleSelection: (UUID, [ClipboardItem], HistorySelectionState) -> HistorySelectionState
    ) -> HistorySelectionState {
        guard state.selectedIndex > 0 else { return state }

        let currentItem = filteredItems[state.selectedIndex]
        let previousIndex = state.selectedIndex - 1
        let previousItem = filteredItems[previousIndex]

        guard !state.selectedIDs.isEmpty else {
            return applySingleSelection(currentItem.id, filteredItems, state)
        }

        var nextState = state
        nextState.selectedIDs.insert(previousItem.id)
        if !nextState.selectedActionOrderIDs.contains(previousItem.id) {
            nextState.selectedActionOrderIDs.append(previousItem.id)
        }
        nextState.selectionAnchor = nextState.selectionAnchor ?? currentItem.id
        nextState.selectedIndex = previousIndex
        nextState.selectedID = previousItem.id
        return nextState
    }

    func extendSelectionDown(
        in filteredItems: [ClipboardItem],
        state: HistorySelectionState,
        applySingleSelection: (UUID, [ClipboardItem], HistorySelectionState) -> HistorySelectionState
    ) -> HistorySelectionState {
        guard state.selectedIndex < filteredItems.count - 1 else { return state }

        let currentItem = filteredItems[state.selectedIndex]
        let nextIndex = state.selectedIndex + 1
        let nextItem = filteredItems[nextIndex]

        guard !state.selectedIDs.isEmpty else {
            return applySingleSelection(currentItem.id, filteredItems, state)
        }

        var nextState = state
        nextState.selectedIDs.insert(nextItem.id)
        if !nextState.selectedActionOrderIDs.contains(nextItem.id) {
            nextState.selectedActionOrderIDs.append(nextItem.id)
        }
        nextState.selectionAnchor = nextState.selectionAnchor ?? currentItem.id
        nextState.selectedIndex = nextIndex
        nextState.selectedID = nextItem.id
        return nextState
    }
}
