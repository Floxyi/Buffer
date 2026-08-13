import XCTest

@testable import Buffer

final class HistoryContextMenuControllerTests: XCTestCase {
    func testSelectedClickedItemUsesCurrentSelectionTargets() {
        let controller = HistoryContextMenuController()
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")

        let targets = controller.targetItems(
            for: first.id,
            itemByID: [first.id: first, second.id: second],
            selectedIDs: [first.id, second.id],
            selectedItemsInActionOrder: [second, first]
        )

        XCTAssertEqual(targets.map(\.id), [second.id, first.id])
    }

    func testUnselectedClickedItemUsesOnlyClickedItem() {
        let controller = HistoryContextMenuController()
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")

        let targets = controller.targetItems(
            for: second.id,
            itemByID: [first.id: first, second.id: second],
            selectedIDs: [first.id],
            selectedItemsInActionOrder: [first]
        )

        XCTAssertEqual(targets.map(\.id), [second.id])
    }

    func testUnknownClickedItemProducesNoTargets() {
        let controller = HistoryContextMenuController()
        let item = ClipboardItem.text("known")

        XCTAssertTrue(
            controller.targetItems(
                for: UUID(),
                itemByID: [item.id: item],
                selectedIDs: [],
                selectedItemsInActionOrder: []
            ).isEmpty
        )
    }
}
