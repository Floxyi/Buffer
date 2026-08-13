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

    func testAdjacentRangeMovementGrowsShrinksAndCrossesAnchor() {
        let controller = HistorySelectionController()
        let items = (0..<5).map { ClipboardItem.text("item-\($0)") }
        var state = controller.applySingleSelection(
            items[2].id,
            index: 2,
            in: items,
            state: HistorySelectionState()
        )

        state = controller.extendSelection(
            to: items[3].id,
            targetIndex: 3,
            in: items,
            state: state
        )
        XCTAssertEqual(state.selectedActionOrderIDs, [items[2].id, items[3].id])

        state = controller.extendSelection(
            to: items[2].id,
            targetIndex: 2,
            in: items,
            state: state
        )
        XCTAssertEqual(state.selectedIDs, [items[2].id])

        state = controller.extendSelection(
            to: items[1].id,
            targetIndex: 1,
            in: items,
            state: state
        )
        XCTAssertEqual(state.selectedActionOrderIDs, [items[2].id, items[1].id])
        XCTAssertEqual(state.selectionAnchor, items[2].id)
        XCTAssertEqual(state.selectedID, items[1].id)
    }

    func testRangeExtensionReplacesNoncontiguousCommandSelection() {
        let controller = HistorySelectionController()
        let items = (0..<5).map { ClipboardItem.text("item-\($0)") }
        var state = controller.applySingleSelection(
            items[0].id,
            index: 0,
            in: items,
            state: HistorySelectionState()
        )
        state = controller.toggleSelection(items[4].id, in: items, state: state)

        state = controller.extendSelection(
            to: items[2].id,
            targetIndex: 2,
            in: items,
            state: state
        )

        XCTAssertEqual(state.selectedIDs, Set([items[2].id, items[3].id, items[4].id]))
        XCTAssertEqual(state.selectedActionOrderIDs, [items[4].id, items[3].id, items[2].id])
    }

    func testDeselectingCommandAnchorReanchorsToRemainingFocusedItem() {
        let controller = HistorySelectionController()
        let items = (0..<3).map { ClipboardItem.text("item-\($0)") }
        var state = controller.applySingleSelection(
            items[0].id,
            index: 0,
            in: items,
            state: HistorySelectionState()
        )
        state = controller.toggleSelection(items[2].id, in: items, state: state)

        state = controller.toggleSelection(items[2].id, in: items, state: state)

        XCTAssertEqual(state.selectedID, items[0].id)
        XCTAssertEqual(state.selectedIndex, 0)
        XCTAssertEqual(state.selectionAnchor, items[0].id)
    }
}
