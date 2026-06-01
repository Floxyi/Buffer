import XCTest
@testable import Buffer

final class HistoryDeleteSelectionResolverTests: XCTestCase {
    func testPreferredSelectionUsesNextVisibleItemWhenAvailable() {
        let resolver = HistoryDeleteSelectionResolver()
        let newest = ClipboardItem.text("newest")
        let middle = ClipboardItem.text("middle")
        let oldest = ClipboardItem.text("oldest")

        let preferredID = resolver.preferredSelectionID(
            afterDeleting: [middle],
            from: [newest, middle, oldest]
        )

        XCTAssertEqual(preferredID, oldest.id)
    }

    func testPreferredSelectionFallsBackToPreviousVisibleItem() {
        let resolver = HistoryDeleteSelectionResolver()
        let newest = ClipboardItem.text("newest")
        let middle = ClipboardItem.text("middle")
        let oldest = ClipboardItem.text("oldest")

        let preferredID = resolver.preferredSelectionID(
            afterDeleting: [oldest],
            from: [newest, middle, oldest]
        )

        XCTAssertEqual(preferredID, middle.id)
    }
}
