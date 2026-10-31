import XCTest

@testable import Buffer

final class ClipboardListDisplayStateProjectorTests: XCTestCase {
    func testContentSnapshotCarriesDisplayCacheFromSamePublication() {
        let item = ClipboardItem.text("atomic publication")
        let snapshotID = UUID()
        let cache = ClipboardListStructure.makeDisplayCache(
            from: [item],
            sourceSnapshotID: snapshotID
        )
        let state = ClipboardListViewState(
            items: [item],
            itemsSnapshotID: snapshotID,
            selectedIDs: [],
            quickPasteBadgeNumberByItemID: [:],
            searchResultsByItemID: [:],
            queryText: "",
            committedQueryText: "",
            preparedDisplayCache: cache
        )

        let publication = state.contentSnapshot

        XCTAssertEqual(publication.id, snapshotID)
        XCTAssertEqual(publication.items.map(\.id), [item.id])
        XCTAssertTrue(publication.displayCache.matches(sourceSnapshotID: publication.id))
    }

    func testProjectionUsesCacheFromLatestPublication() {
        let unfilteredItems = [
            ClipboardItem.text("matching item"),
            ClipboardItem.text("unrelated item"),
        ]
        let filteredItems = [unfilteredItems[0]]
        let filteredSnapshotID = UUID()

        let state = ClipboardListDisplayStateProjector().project(
            items: filteredItems,
            itemsSnapshotID: filteredSnapshotID,
            cache: ClipboardListStructure.makeDisplayCache(
                from: filteredItems,
                sourceSnapshotID: filteredSnapshotID
            ),
            viewportHeight: 200
        )

        XCTAssertEqual(state.layoutIndex.entries.map(\.id), filteredItems.map(\.id))
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
