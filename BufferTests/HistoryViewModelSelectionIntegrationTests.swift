import XCTest

@testable import Buffer

@MainActor
final class HistoryViewModelSelectionIntegrationTests: XCTestCase {
    func testIndexedPointerSelectionPublishesExactItemBeforeReturning() async {
        let viewModel = await makeSelectionHistoryViewModel()
        let targetIndex = 2
        let target = viewModel.filteredItems[targetIndex]

        viewModel.selectSingle(target.id, at: targetIndex)

        XCTAssertEqual(viewModel.selectedIndex, targetIndex)
        XCTAssertEqual(viewModel.selectedID, target.id)
        XCTAssertEqual(viewModel.selectedIDs, [target.id])
    }

    func testIndexedPointerSelectionResolvesStaleIndexByIdentity() async {
        let viewModel = await makeSelectionHistoryViewModel()
        let target = viewModel.filteredItems[2]

        viewModel.selectSingle(target.id, at: 0)

        XCTAssertEqual(viewModel.selectedIndex, 2)
        XCTAssertEqual(viewModel.selectedID, target.id)
        XCTAssertEqual(viewModel.selectedIDs, [target.id])
    }

    func testArrowDownPublishesSingleSelectionBeforeReturning() async {
        let viewModel = await makeSelectionHistoryViewModel()
        let target = viewModel.filteredItems[1]

        viewModel.navigateDown()

        XCTAssertEqual(viewModel.selectedIndex, 1)
        XCTAssertEqual(viewModel.selectedID, target.id)
        XCTAssertEqual(viewModel.selectedIDs, [target.id])
        XCTAssertEqual(viewModel.keyboardScrollRequest?.itemID, target.id)
        XCTAssertEqual(viewModel.keyboardScrollRequest?.targetIndex, 1)
    }

    func testTenRapidArrowDownEventsCommitTenSelectionsWithoutCallbacks() async {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let items = (0..<12).map { index in
            ClipboardItem(
                type: .text,
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                textContent: "item-\(index)"
            )
        }
        await populateStore(store, with: items)
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)

        for _ in 0..<10 {
            viewModel.navigateDown()
        }

        XCTAssertEqual(viewModel.selectedIndex, 10)
        XCTAssertEqual(viewModel.selectedID, viewModel.filteredItems[10].id)
        XCTAssertEqual(viewModel.keyboardScrollRequest?.generation, 10)
    }

    func testAlternatingArrowNavigationUsesLatestCommittedIndex() async {
        let viewModel = await makeSelectionHistoryViewModel()

        viewModel.navigateDown()
        viewModel.navigateDown()
        viewModel.navigateUp()
        viewModel.navigateDown()

        XCTAssertEqual(viewModel.selectedIndex, 2)
        XCTAssertEqual(viewModel.selectedID, viewModel.filteredItems[2].id)
    }

    func testBoundaryArrowIsNoOpAndDoesNotCreateScrollRequest() async {
        let viewModel = await makeSelectionHistoryViewModel()
        let initialID = viewModel.selectedID

        viewModel.navigateUp()

        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertEqual(viewModel.selectedID, initialID)
        XCTAssertNil(viewModel.keyboardScrollRequest)
    }

    func testFilteredItemsChangeInvalidatesKeyboardScrollRequest() async {
        let viewModel = await makeSelectionHistoryViewModel()
        viewModel.navigateDown()
        XCTAssertNotNil(viewModel.keyboardScrollRequest)

        viewModel.searchText = "newest"

        XCTAssertNil(viewModel.keyboardScrollRequest)
        XCTAssertEqual(viewModel.selectedID, viewModel.filteredItems.first?.id)
    }

    func testJumpToFirstItemSelectsNewestVisibleItem() async {
        let viewModel = await makeSelectionHistoryViewModel()
        let oldest = viewModel.filteredItems.last!

        viewModel.selectSingle(oldest.id)
        viewModel.jumpToFirstItem()

        XCTAssertEqual(viewModel.selectedItem?.id, viewModel.filteredItems.first?.id)
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertEqual(viewModel.keyboardScrollRequest?.targetIndex, 0)
    }

    func testJumpToLastItemSelectsOldestVisibleItem() async {
        let viewModel = await makeSelectionHistoryViewModel()
        let newest = viewModel.filteredItems.first!

        viewModel.selectSingle(newest.id)
        viewModel.jumpToLastItem()

        XCTAssertEqual(viewModel.selectedItem?.id, viewModel.filteredItems.last?.id)
        XCTAssertEqual(viewModel.selectedIndex, viewModel.filteredItems.count - 1)
        XCTAssertEqual(viewModel.keyboardScrollRequest?.targetIndex, viewModel.filteredItems.count - 1)
    }

    func testExtendSelectionToFirstItemSelectsRangeToNewestVisibleItem() async {
        let viewModel = await makeSelectionHistoryViewModel()
        let middle = viewModel.filteredItems[1]

        viewModel.selectSingle(middle.id)
        viewModel.extendSelectionToFirstItem()

        XCTAssertEqual(viewModel.selectedID, viewModel.filteredItems.first?.id)
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertEqual(viewModel.selectedIDs, Set(viewModel.filteredItems.prefix(2).map(\.id)))
        XCTAssertEqual(viewModel.keyboardScrollRequest?.targetIndex, 0)
    }

    func testExtendSelectionToLastItemSelectsRangeToOldestVisibleItem() async {
        let viewModel = await makeSelectionHistoryViewModel()
        let middle = viewModel.filteredItems[1]

        viewModel.selectSingle(middle.id)
        viewModel.extendSelectionToLastItem()

        XCTAssertEqual(viewModel.selectedID, viewModel.filteredItems.last?.id)
        XCTAssertEqual(viewModel.selectedIndex, viewModel.filteredItems.count - 1)
        XCTAssertEqual(viewModel.selectedIDs, Set(viewModel.filteredItems.suffix(2).map(\.id)))
        XCTAssertEqual(viewModel.keyboardScrollRequest?.targetIndex, viewModel.filteredItems.count - 1)
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

    func testKeyboardRangeShrinksAndReversesAcrossAnchor() async {
        let viewModel = await makeSelectionHistoryViewModel()
        let newest = viewModel.filteredItems[0]
        let middle = viewModel.filteredItems[1]
        let oldest = viewModel.filteredItems[2]

        viewModel.selectSingle(middle.id)
        viewModel.extendSelectionDown()
        XCTAssertEqual(viewModel.selectedItemsInActionOrder.map(\.id), [middle.id, oldest.id])

        viewModel.extendSelectionUp()
        XCTAssertEqual(viewModel.selectedIDs, [middle.id])
        XCTAssertEqual(viewModel.selectedID, middle.id)

        viewModel.extendSelectionUp()
        XCTAssertEqual(viewModel.selectedItemsInActionOrder.map(\.id), [middle.id, newest.id])
        XCTAssertEqual(viewModel.selectedID, newest.id)

        viewModel.extendSelectionDown()
        XCTAssertEqual(viewModel.selectedIDs, [middle.id])
        XCTAssertEqual(viewModel.keyboardScrollRequest?.targetIndex, 1)
        XCTAssertEqual(viewModel.keyboardScrollRequest?.generation, 4)
    }

    func testKeyboardRangeBoundaryIsNoOpWithoutNewScrollRequest() async {
        let viewModel = await makeSelectionHistoryViewModel()

        viewModel.extendSelectionUp()

        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertNil(viewModel.keyboardScrollRequest)
    }

    func testSelectAllUsesFilteredItemsAndPlainArrowCollapsesSelection() async {
        let viewModel = await makeSelectionHistoryViewModel()
        viewModel.searchText = "e"

        viewModel.selectAllItems()

        XCTAssertEqual(viewModel.selectedIDs, Set(viewModel.filteredItems.map(\.id)))
        XCTAssertEqual(viewModel.selectedItemsInActionOrder.map(\.id), viewModel.filteredItems.map(\.id))

        viewModel.navigateDown()

        XCTAssertEqual(viewModel.selectedIDs, [viewModel.filteredItems[1].id])
        XCTAssertEqual(viewModel.selectedIndex, 1)
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
