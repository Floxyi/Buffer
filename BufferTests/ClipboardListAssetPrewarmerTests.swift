import XCTest
@testable import Buffer

final class ClipboardListAssetPrewarmerTests: XCTestCase {
    func testVisiblePrewarmItemsLimitsToLeadingWindow() {
        let items = (0..<200).map { ClipboardItem.text("item-\($0)") }

        let result = ClipboardListAssetPrewarmer.visiblePrewarmItems(from: items)

        XCTAssertEqual(result.count, 160)
        XCTAssertEqual(result.first?.textContent, "item-0")
        XCTAssertEqual(result.last?.textContent, "item-159")
    }

    func testKeyboardNavigationPrewarmItemsReturnsNearbyRange() {
        let items = (0..<30).map { ClipboardItem.text("item-\($0)") }
        let request = HistoryKeyboardNavigationRequest(
            itemID: items[14].id,
            targetIndex: 14,
            generation: 1
        )

        let result = ClipboardListAssetPrewarmer.keyboardNavigationPrewarmItems(
            for: request,
            in: items
        )

        XCTAssertEqual(result.count, 17)
        XCTAssertEqual(result.first?.textContent, "item-6")
        XCTAssertEqual(result.last?.textContent, "item-22")
    }
}
