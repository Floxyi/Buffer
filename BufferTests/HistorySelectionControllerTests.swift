import XCTest

@testable import Buffer

final class HistorySelectionControllerTests: XCTestCase {
    func testPreferredSelectionAfterDeletingUsesNextVisibleItem() {
        let controller = HistorySelectionController()
        let newest = ClipboardItem.text("newest")
        let middle = ClipboardItem.text("middle")
        let oldest = ClipboardItem.text("oldest")
        let filteredItems = [newest, middle, oldest]

        let preferredID = controller.preferredSelectionID(
            afterDeleting: [middle],
            from: filteredItems
        )

        XCTAssertEqual(preferredID, oldest.id)
    }

    func testExtendSelectionBuildsRangeFromAnchorToTarget() {
        let controller = HistorySelectionController()
        let newest = ClipboardItem.text("newest")
        let middle = ClipboardItem.text("middle")
        let oldest = ClipboardItem.text("oldest")
        let filteredItems = [newest, middle, oldest]

        let initial = controller.applySingleSelection(newest.id, in: filteredItems, state: HistorySelectionState())
        let extended = controller.extendSelection(
            to: oldest.id,
            in: filteredItems,
            state: initial
        )

        XCTAssertEqual(extended.selectedIDs, Set([newest.id, middle.id, oldest.id]))
        XCTAssertEqual(extended.selectedID, oldest.id)
        XCTAssertEqual(extended.selectedIndex, 2)
    }

    func testSyncSelectionReanchorsWhenFilterRemovesRangeAnchor() {
        let controller = HistorySelectionController()
        let items = (0..<5).map { ClipboardItem.text("item-\($0)") }
        var state = controller.applySingleSelection(
            items[2].id,
            index: 2,
            in: items,
            state: HistorySelectionState()
        )
        state = controller.extendSelection(
            to: items[4].id,
            targetIndex: 4,
            in: items,
            state: state
        )

        let filteredItems = [items[3], items[4]]
        let synced = controller.syncSelection(
            state: state,
            in: filteredItems,
            preferredID: nil,
            preferredTopSelectionID: filteredItems.first?.id
        )

        XCTAssertEqual(synced.selectedIDs, Set(filteredItems.map(\.id)))
        XCTAssertEqual(synced.selectedID, items[4].id)
        XCTAssertEqual(synced.selectedIndex, 1)
        XCTAssertEqual(synced.selectionAnchor, items[4].id)
    }
}
