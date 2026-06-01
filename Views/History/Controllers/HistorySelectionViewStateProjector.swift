import Foundation

struct HistorySelectionViewStateProjector {
    func project(_ selectionState: HistorySelectionState) -> HistorySelectionViewState {
        HistorySelectionViewState(
            selectedIDs: selectionState.selectedIDs,
            selectedActionOrderIDs: selectionState.selectedActionOrderIDs,
            selectedIndex: selectionState.selectedIndex,
            selectedID: selectionState.selectedID
        )
    }
}
