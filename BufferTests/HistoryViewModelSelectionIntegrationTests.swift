import XCTest
@testable import Buffer

@MainActor
final class HistoryViewModelSelectionIntegrationTests: XCTestCase {
    func testJumpToFirstItemSelectsNewestVisibleItem() async {
        let viewModel = await makeSelectionHistoryViewModel()
        let oldest = viewModel.filteredItems.last!

        viewModel.selectSingle(oldest.id)
        viewModel.jumpToFirstItem()

        XCTAssertEqual(viewModel.selectedItem?.id, viewModel.filteredItems.first?.id)
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertTrue(viewModel.scrollTrigger)
    }

    func testJumpToLastItemSelectsOldestVisibleItem() async {
        let viewModel = await makeSelectionHistoryViewModel()
        let newest = viewModel.filteredItems.first!

        viewModel.selectSingle(newest.id)
        viewModel.jumpToLastItem()

        XCTAssertEqual(viewModel.selectedItem?.id, viewModel.filteredItems.last?.id)
        XCTAssertEqual(viewModel.selectedIndex, viewModel.filteredItems.count - 1)
        XCTAssertTrue(viewModel.scrollTrigger)
    }

    func testExtendSelectionToFirstItemSelectsRangeToNewestVisibleItem() async {
        let viewModel = await makeSelectionHistoryViewModel()
        let middle = viewModel.filteredItems[1]

        viewModel.selectSingle(middle.id)
        viewModel.extendSelectionToFirstItem()

        XCTAssertEqual(viewModel.selectedID, viewModel.filteredItems.first?.id)
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertEqual(viewModel.selectedIDs, Set(viewModel.filteredItems.prefix(2).map(\.id)))
        XCTAssertTrue(viewModel.scrollTrigger)
    }

    func testExtendSelectionToLastItemSelectsRangeToOldestVisibleItem() async {
        let viewModel = await makeSelectionHistoryViewModel()
        let middle = viewModel.filteredItems[1]

        viewModel.selectSingle(middle.id)
        viewModel.extendSelectionToLastItem()

        XCTAssertEqual(viewModel.selectedID, viewModel.filteredItems.last?.id)
        XCTAssertEqual(viewModel.selectedIndex, viewModel.filteredItems.count - 1)
        XCTAssertEqual(viewModel.selectedIDs, Set(viewModel.filteredItems.suffix(2).map(\.id)))
        XCTAssertTrue(viewModel.scrollTrigger)
    }

    func testCommandToggleSelectionTracksActionOrderAndRemovesDeselectedItems() async {
        let viewModel = await makeSelectionHistoryViewModel()
        let newest = viewModel.filteredItems[0]
        let middle = viewModel.filteredItems[1]
        let oldest = viewModel.filteredItems[2]

        viewModel.selectSingle(middle.id)
        viewModel.toggleSelection(oldest.id)
        viewModel.toggleSelection(newest.id)

        XCTAssertEqual(viewModel.selectedItemsInActionOrder.map(\.id), [middle.id, oldest.id, newest.id])
        XCTAssertEqual(viewModel.selectedItemsInVisualOrder.map(\.id), [newest.id, middle.id, oldest.id])

        viewModel.toggleSelection(oldest.id)

        XCTAssertEqual(viewModel.selectedItemsInActionOrder.map(\.id), [middle.id, newest.id])
        XCTAssertEqual(viewModel.selectedIDs, Set([middle.id, newest.id]))
    }

    func testShiftRangeSelectionAppendsNewItemsInGestureDirection() async {
        let viewModel = await makeSelectionHistoryViewModel()
        let newest = viewModel.filteredItems[0]
        let middle = viewModel.filteredItems[1]
        let oldest = viewModel.filteredItems[2]

        viewModel.selectSingle(middle.id)
        viewModel.extendSelectionTo(oldest.id)
        XCTAssertEqual(viewModel.selectedItemsInActionOrder.map(\.id), [middle.id, oldest.id])

        viewModel.selectSingle(middle.id)
        viewModel.extendSelectionTo(newest.id)
        XCTAssertEqual(viewModel.selectedItemsInActionOrder.map(\.id), [middle.id, newest.id])
    }

    func testKeyboardExtendAppendsNewEdgeItemInExtensionDirection() async {
        let viewModel = await makeSelectionHistoryViewModel()
        let newest = viewModel.filteredItems[0]
        let middle = viewModel.filteredItems[1]
        let oldest = viewModel.filteredItems[2]

        viewModel.selectSingle(middle.id)
        viewModel.extendSelectionUp()
        XCTAssertEqual(viewModel.selectedItemsInActionOrder.map(\.id), [middle.id, newest.id])

        viewModel.selectSingle(middle.id)
        viewModel.extendSelectionDown()
        XCTAssertEqual(viewModel.selectedItemsInActionOrder.map(\.id), [middle.id, oldest.id])
    }

    func testContextMenuTargetingUsesSelectionScopeForSelectedRowsAndSingleScopeOtherwise() async {
        let viewModel = await makeSelectionHistoryViewModel()
        let newest = viewModel.filteredItems[0]
        let middle = viewModel.filteredItems[1]
        let oldest = viewModel.filteredItems[2]

        viewModel.selectSingle(middle.id)
        viewModel.toggleSelection(newest.id)

        XCTAssertEqual(
            viewModel.contextMenuTargetItems(for: newest.id).map(\.id),
            [middle.id, newest.id]
        )
        XCTAssertEqual(
            viewModel.contextMenuTargetItems(for: oldest.id).map(\.id),
            [oldest.id]
        )
    }
}
