import XCTest

@testable import Buffer

final class ClipboardListDisplayStateProjectorTests: XCTestCase {
    func testProjectionUsesLatestItemsWhenCacheBelongsToPreviousQuery() {
        let unfilteredItems = [
            ClipboardItem.text("matching item"),
            ClipboardItem.text("unrelated item"),
        ]
        let filteredItems = [unfilteredItems[0]]
        let previousSnapshotID = UUID()
        let filteredSnapshotID = UUID()

        let state = ClipboardListDisplayStateProjector().project(
            items: filteredItems,
            itemsSnapshotID: filteredSnapshotID,
            cache: ClipboardListStructure.makeDisplayCache(
                from: unfilteredItems,
                sourceSnapshotID: previousSnapshotID
            ),
            viewportHeight: 200
        )

        XCTAssertEqual(state.layoutIndex.entries.map(\.id), [filteredItems[0].id])
    }

    func testUsesCachedRows() {
        let item = ClipboardItem.text("first")
        let snapshotID = UUID()
        let cache = ClipboardListStructure.makeDisplayCache(
            from: [item],
            sourceSnapshotID: snapshotID
        )
        let projector = ClipboardListDisplayStateProjector()

        let state = projector.project(
            items: [item],
            itemsSnapshotID: snapshotID,
            cache: cache,
            viewportHeight: 400
        )

        XCTAssertEqual(state.displayRows.map(\.id), cache.displayRows.map(\.id))
        XCTAssertEqual(state.contentTrailingPadding, ClipboardListStructure.LayoutMetrics.contentPadding)
    }

    func testAddsScrollbarPaddingWhenContentExceedsViewport() {
        let items = (0..<30).map { ClipboardItem.text("item-\($0)") }
        let projector = ClipboardListDisplayStateProjector()
        let snapshotID = UUID()

        let state = projector.project(
            items: items,
            itemsSnapshotID: snapshotID,
            cache: ClipboardListStructure.makeDisplayCache(
                from: items,
                sourceSnapshotID: snapshotID
            ),
            viewportHeight: 120
        )

        XCTAssertEqual(
            state.contentTrailingPadding,
            ClipboardListStructure.LayoutMetrics.scrollbarWidth + 2
                * ClipboardListStructure.LayoutMetrics.contentPadding
        )
    }
}
