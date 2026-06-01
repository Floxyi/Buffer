import XCTest

@testable import Buffer

final class HistorySelectionQueryTests: XCTestCase {
    func testSelectedItemsInActionOrderFollowActionIDs() {
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")
        let third = ClipboardItem.text("third")

        let query = HistorySelectionQuery(
            filteredItems: [first, second, third],
            selectedIDs: [first.id, third.id],
            selectedActionOrderIDs: [third.id, first.id],
            selectedID: third.id,
            searchText: "",
            totalItemCount: 3
        )

        XCTAssertEqual(query.selectedItem?.id, third.id)
        XCTAssertEqual(query.selectedItemsInActionOrder.map(\.id), [third.id, first.id])
        XCTAssertEqual(query.selectionCount, 2)
        XCTAssertTrue(query.isShowingFullHistory)
    }

    func testIsShowingFullHistoryRequiresEmptySearchAndFullItemCount() {
        let item = ClipboardItem.text("first")

        XCTAssertFalse(
            HistorySelectionQuery(
                filteredItems: [item],
                selectedIDs: [],
                selectedActionOrderIDs: [],
                selectedID: nil,
                searchText: "needle",
                totalItemCount: 1
            ).isShowingFullHistory
        )

        XCTAssertFalse(
            HistorySelectionQuery(
                filteredItems: [],
                selectedIDs: [],
                selectedActionOrderIDs: [],
                selectedID: nil,
                searchText: "",
                totalItemCount: 1
            ).isShowingFullHistory
        )
    }
}
