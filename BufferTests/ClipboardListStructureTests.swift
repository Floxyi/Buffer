import XCTest

@testable import Buffer

final class ClipboardListStructureTests: XCTestCase {
    func testLayoutIndexMatchesLegacyGeometry() throws {
        let items = (0..<40).map { ClipboardItem.text("item-\($0)") }
        let cache = ClipboardListStructure.makeDisplayCache(from: items)

        XCTAssertEqual(
            cache.layoutIndex.contentHeight,
            ClipboardListStructure.estimatedContentHeight(for: cache.displayRows),
            accuracy: 0.001
        )

        for item in items {
            let indexedFrame = try XCTUnwrap(cache.layoutIndex.frame(for: item.id))
            let legacyFrame = try XCTUnwrap(
                ClipboardListStructure.estimatedFrame(forItemID: item.id, in: cache.displayRows)
            )
            XCTAssertEqual(indexedFrame.minY, legacyFrame.minY, accuracy: 0.001)
            XCTAssertEqual(indexedFrame.height, legacyFrame.height, accuracy: 0.001)
        }
    }

    func testLayoutIndexFindsDeepViewportWithoutIncludingPrecedingItems() throws {
        let items = (0..<10_000).map { ClipboardItem.text("item-\($0)") }
        let cache = ClipboardListStructure.makeDisplayCache(from: items)
        let targetFrame = try XCTUnwrap(cache.layoutIndex.frame(for: items[9_500].id))

        let visible = cache.layoutIndex.visibleItemEntries(
            scrollOffset: targetFrame.minY,
            viewportHeight: 220
        )

        XCTAssertEqual(visible.first?.id, items[9_500].id)
        XCTAssertLessThanOrEqual(visible.count, 7)
        XCTAssertTrue(visible.allSatisfy { $0.itemIndex >= 9_500 })
    }

    func testLayoutIndexPreservesDisplayOrderForPinnedItems() throws {
        let first = ClipboardItem.text("first")
        var pinned = ClipboardItem.text("pinned")
        pinned.isPinned = true
        let cache = ClipboardListStructure.makeDisplayCache(from: [first, pinned])

        let firstVisible = try XCTUnwrap(
            cache.layoutIndex.visibleItemEntries(scrollOffset: 0, viewportHeight: 200).first
        )
        XCTAssertEqual(firstVisible.id, pinned.id)
        XCTAssertEqual(firstVisible.itemIndex, 1)
    }

    func testRebuildsCacheWhenWeekBoundaryChanges() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let mondayReferenceDate = DateComponents(
            calendar: calendar,
            year: 2026,
            month: 5,
            day: 18,
            hour: 9
        ).date!
        let sundayReferenceDate = DateComponents(
            calendar: calendar,
            year: 2026,
            month: 5,
            day: 17,
            hour: 9
        ).date!
        let lastTuesdayItemDate = DateComponents(
            calendar: calendar,
            year: 2026,
            month: 5,
            day: 12,
            hour: 12
        ).date!

        let items = [
            ClipboardItem(
                type: .text,
                timestamp: lastTuesdayItemDate,
                textContent: "last week item"
            )
        ]

        let staleCache = ClipboardListStructure.makeDisplayCache(
            from: items,
            referenceDate: sundayReferenceDate,
            calendar: calendar
        )

        XCTAssertFalse(staleCache.matches(items: items, referenceDate: mondayReferenceDate, calendar: calendar))

        let refreshedRows = ClipboardListStructure.displayRows(
            from: items,
            referenceDate: mondayReferenceDate,
            calendar: calendar
        )
        let sectionTitle = refreshedRows.compactMap { row -> String? in
            guard case .header(let title, _) = row.kind else { return nil }
            return title
        }.first

        XCTAssertEqual(sectionTitle, "LAST WEEK")
    }
}
