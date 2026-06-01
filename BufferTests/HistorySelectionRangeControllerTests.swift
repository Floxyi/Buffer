import XCTest
@testable import Buffer

final class HistorySelectionRangeControllerTests: XCTestCase {
    func testExtendSelectionBuildsRangeFromAnchorToTarget() {
        let controller = HistorySelectionRangeController()
        let newest = ClipboardItem.text("newest")
        let middle = ClipboardItem.text("middle")
        let oldest = ClipboardItem.text("oldest")
        let items = [newest, middle, oldest]
        let state = HistorySelectionState(
            selectedIDs: [newest.id],
            selectedActionOrderIDs: [newest.id],
            selectedIndex: 0,
            selectedID: newest.id,
            selectionAnchor: newest.id
        )

        let extended = controller.extendSelection(
            to: oldest.id,
            in: items,
            state: state,
            applySingleSelection: { id, filteredItems, selectionState in
                var nextState = selectionState
                nextState.selectedIDs = [id]
                nextState.selectedActionOrderIDs = [id]
                nextState.selectedIndex = filteredItems.firstIndex(where: { $0.id == id }) ?? 0
                nextState.selectedID = id
                nextState.selectionAnchor = id
                return nextState
            }
        )

        XCTAssertEqual(extended.selectedIDs, Set([newest.id, middle.id, oldest.id]))
        XCTAssertEqual(extended.selectedID, oldest.id)
        XCTAssertEqual(extended.selectedIndex, 2)
    }
}
