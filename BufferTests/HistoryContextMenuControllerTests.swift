import XCTest
@testable import Buffer

final class HistoryContextMenuControllerTests: XCTestCase {
    func testSelectedClickedItemUsesCurrentSelectionTargets() {
        let controller = HistoryContextMenuController()
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")

        let targets = controller.targetItems(
            for: first.id,
            filteredItems: [first, second],
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
            filteredItems: [first, second],
            selectedIDs: [first.id],
            selectedItemsInActionOrder: [first]
        )

        XCTAssertEqual(targets.map(\.id), [second.id])
    }

    func testShouldShowUnpinRequiresAllTargetsPinned() {
        let controller = HistoryContextMenuController()
        var pinned = ClipboardItem.text("pinned")
        pinned.isPinned = true
        pinned.pinnedAt = Date()
        let plain = ClipboardItem.text("plain")

        XCTAssertTrue(
            controller.shouldShowUnpin(
                for: pinned.id,
                filteredItems: [pinned],
                selectedIDs: [],
                selectedItemsInActionOrder: []
            )
        )
        XCTAssertFalse(
            controller.shouldShowUnpin(
                for: plain.id,
                filteredItems: [pinned, plain],
                selectedIDs: [pinned.id, plain.id],
                selectedItemsInActionOrder: [pinned, plain]
            )
        )
    }
}
