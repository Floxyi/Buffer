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

    func testVisiblePrewarmItemsTracksVisibleRowsWithOverscan() {
        let items = (0..<40).map { ClipboardItem.text("item-\($0)") }
        let rows = ClipboardListStructure.displayRows(from: items)

        let result = ClipboardListAssetPrewarmer.visiblePrewarmItems(
            from: items,
            displayRows: rows,
            scrollOffset: 520,
            viewportHeight: 220
        )

        XCTAssertEqual(result.first?.textContent, "item-0")
        XCTAssertEqual(result.last?.textContent, "item-27")
        XCTAssertEqual(result.count, 28)
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

    func testPrioritizedVisiblePrewarmPlanLoadsVisibleThenDownwardLookahead() throws {
        let items = (0..<100).map { ClipboardItem.text("item-\($0)") }
        let rows = ClipboardListStructure.displayRows(from: items)
        let scrollOffset = CGFloat(1_000)
        let viewportHeight = CGFloat(220)
        let visibleIDs = ClipboardListStructure.visibleItemIDs(
            in: rows,
            scrollOffset: scrollOffset,
            viewportHeight: viewportHeight,
            overscan: 0
        )
        let itemIndexByID = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($1.id, $0) })
        let visibleIndices = visibleIDs.compactMap { itemIndexByID[$0] }
        let lastVisibleIndex = try XCTUnwrap(visibleIndices.max())

        let plan = ClipboardListAssetPrewarmer.prioritizedVisiblePrewarmPlan(
            from: items,
            displayRows: rows,
            scrollOffset: scrollOffset,
            viewportHeight: viewportHeight,
            direction: .downward
        )

        XCTAssertEqual(Array(plan.items.prefix(visibleIDs.count)).map(\.id), visibleIDs)
        XCTAssertEqual(plan.items[visibleIDs.count].id, items[lastVisibleIndex + 1].id)
        XCTAssertGreaterThan(plan.items.count, visibleIDs.count + 40)
    }

    func testPrioritizedKeyboardPrewarmLoadsTargetThenDownwardLookahead() {
        let items = (0..<200).map { ClipboardItem.text("item-\($0)") }
        let request = HistoryKeyboardNavigationRequest(
            itemID: items[50].id,
            targetIndex: 50,
            generation: 1
        )

        let result = ClipboardListAssetPrewarmer.prioritizedKeyboardNavigationPrewarmItems(
            for: request,
            in: items,
            direction: .downward
        )

        XCTAssertEqual(result.first?.id, items[50].id)
        XCTAssertEqual(result[1].id, items[51].id)
        XCTAssertEqual(result[120].id, items[170].id)
        XCTAssertEqual(result.last?.id, items[38].id)
    }

    func testPrioritizedKeyboardPrewarmLoadsTargetThenUpwardLookahead() {
        let items = (0..<200).map { ClipboardItem.text("item-\($0)") }
        let request = HistoryKeyboardNavigationRequest(
            itemID: items[150].id,
            targetIndex: 150,
            generation: 1
        )

        let result = ClipboardListAssetPrewarmer.prioritizedKeyboardNavigationPrewarmItems(
            for: request,
            in: items,
            direction: .upward
        )

        XCTAssertEqual(result.first?.id, items[150].id)
        XCTAssertEqual(result[1].id, items[149].id)
        XCTAssertEqual(result[120].id, items[30].id)
        XCTAssertEqual(result.last?.id, items[162].id)
    }
}
