import XCTest

@testable import Buffer

final class ClipboardListDisplayStateProjectorTests: XCTestCase {
    func testUsesCachedRowsWhenCacheMatches() {
        let item = ClipboardItem.text("first")
        let cache = ClipboardListStructure.makeDisplayCache(from: [item])
        let projector = ClipboardListDisplayStateProjector()

        let state = projector.project(
            items: [item],
            cache: cache,
            viewportHeight: 400
        )

        XCTAssertEqual(state.displayRows.map(\.id), cache.displayRows.map(\.id))
        XCTAssertEqual(state.contentTrailingPadding, ClipboardListStructure.LayoutMetrics.contentPadding)
    }

    func testAddsScrollbarPaddingWhenContentExceedsViewport() {
        let items = (0..<30).map { ClipboardItem.text("item-\($0)") }
        let projector = ClipboardListDisplayStateProjector()

        let state = projector.project(
            items: items,
            cache: .empty,
            viewportHeight: 120
        )

        XCTAssertEqual(
            state.contentTrailingPadding,
            ClipboardListStructure.LayoutMetrics.scrollbarWidth + 2
                * ClipboardListStructure.LayoutMetrics.contentPadding
        )
    }
}
