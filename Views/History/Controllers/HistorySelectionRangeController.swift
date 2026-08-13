import Foundation

struct HistorySelectionRangeController {
    func extendSelection(
        to targetID: UUID,
        targetIndex: Int? = nil,
        in filteredItems: [ClipboardItem],
        state: HistorySelectionState,
        applySingleSelection: (UUID, [ClipboardItem], HistorySelectionState) -> HistorySelectionState
    ) -> HistorySelectionState {
        guard let anchorID = state.selectionAnchor else {
            return applySingleSelection(targetID, filteredItems, state)
        }

        guard let anchorIndex = filteredItems.firstIndex(where: { $0.id == anchorID }),
              let resolvedTargetIndex = resolvedIndex(
                  for: targetID,
                  proposedIndex: targetIndex,
                  in: filteredItems
              ) else {
            return state
        }

        if let adjacentState = extendCanonicalRangeByOneItem(
            from: anchorIndex,
            to: resolvedTargetIndex,
            in: filteredItems,
            state: state
        ) {
            return adjacentState
        }

        var nextState = state
        let orderedRangeIDs = orderedRangeIDs(
            from: anchorIndex,
            through: resolvedTargetIndex,
            in: filteredItems
        )
        nextState.selectedIDs = Set(orderedRangeIDs)
        nextState.selectedActionOrderIDs = orderedRangeIDs
        nextState.selectedIndex = resolvedTargetIndex
        nextState.selectedID = targetID
        return nextState
    }

    private func extendCanonicalRangeByOneItem(
        from anchorIndex: Int,
        to targetIndex: Int,
        in filteredItems: [ClipboardItem],
        state: HistorySelectionState
    ) -> HistorySelectionState? {
        guard let focusedID = state.selectedID,
              let focusedIndex = resolvedIndex(
                  for: focusedID,
                  proposedIndex: state.selectedIndex,
                  in: filteredItems
              ),
              abs(targetIndex - focusedIndex) == 1,
              isCanonicalRange(
                  state,
                  anchorIndex: anchorIndex,
                  focusedIndex: focusedIndex
              ) else {
            return nil
        }

        var nextState = state
        let focusedDistance = abs(focusedIndex - anchorIndex)
        let targetDistance = abs(targetIndex - anchorIndex)

        if targetDistance > focusedDistance {
            let targetID = filteredItems[targetIndex].id
            nextState.selectedIDs.insert(targetID)
            nextState.selectedActionOrderIDs.append(targetID)
        } else {
            nextState.selectedIDs.remove(focusedID)
            nextState.selectedActionOrderIDs.removeLast()
        }

        nextState.selectedIndex = targetIndex
        nextState.selectedID = filteredItems[targetIndex].id
        return nextState
    }

    private func isCanonicalRange(
        _ state: HistorySelectionState,
        anchorIndex: Int,
        focusedIndex: Int
    ) -> Bool {
        let expectedCount = abs(focusedIndex - anchorIndex) + 1
        return state.selectedIDs.count == expectedCount
            && state.selectedActionOrderIDs.count == expectedCount
            && state.selectedActionOrderIDs.first == state.selectionAnchor
            && state.selectedActionOrderIDs.last == state.selectedID
    }

    private func orderedRangeIDs(
        from anchorIndex: Int,
        through targetIndex: Int,
        in filteredItems: [ClipboardItem]
    ) -> [UUID] {
        let direction = targetIndex >= anchorIndex ? 1 : -1
        return stride(from: anchorIndex, through: targetIndex, by: direction).map {
            filteredItems[$0].id
        }
    }

    private func resolvedIndex(
        for id: UUID,
        proposedIndex: Int?,
        in filteredItems: [ClipboardItem]
    ) -> Int? {
        if let proposedIndex,
           filteredItems.indices.contains(proposedIndex),
           filteredItems[proposedIndex].id == id {
            return proposedIndex
        }

        return filteredItems.firstIndex(where: { $0.id == id })
    }
}
