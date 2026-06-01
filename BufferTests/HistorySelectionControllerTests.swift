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
}
