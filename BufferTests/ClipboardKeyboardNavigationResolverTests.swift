import XCTest

@testable import Buffer

final class ClipboardKeyboardNavigationResolverTests: XCTestCase {
    func testResolveMetricsReturnsNilWhenItemIsAlreadyComfortablyVisible() {
        let items = [ClipboardItem.text("first"), ClipboardItem.text("second"), ClipboardItem.text("third")]
        let rows = ClipboardListStructure.displayRows(from: items)
        let resolver = ClipboardKeyboardNavigationResolver()

        let metrics = resolver.resolveMetrics(
            for: items[1].id,
            displayRows: rows,
            scrollMetrics: .init(viewportHeight: 400, contentHeight: 500, scrollOffset: 0)
        )

        XCTAssertNil(metrics)
    }

    func testResolveMetricsReturnsTargetOffsetWhenItemFallsBelowVisibleArea() {
        let items = [ClipboardItem.text("first"), ClipboardItem.text("second"), ClipboardItem.text("third")]
        let rows = ClipboardListStructure.displayRows(from: items)
        let resolver = ClipboardKeyboardNavigationResolver()

        let metrics = resolver.resolveMetrics(
            for: items[2].id,
            displayRows: rows,
            scrollMetrics: .init(viewportHeight: 120, contentHeight: 300, scrollOffset: 0)
        )

        XCTAssertEqual(metrics, ClipboardKeyboardNavigationMetrics(currentOffset: 0, targetOffset: 92))
    }

    func testResolveMetricsReturnsTargetOffsetWhenItemFallsAboveVisibleArea() {
        let items = [ClipboardItem.text("first"), ClipboardItem.text("second"), ClipboardItem.text("third")]
        let rows = ClipboardListStructure.displayRows(from: items)
        let resolver = ClipboardKeyboardNavigationResolver()

        let metrics = resolver.resolveMetrics(
            for: items[2].id,
            displayRows: rows,
            scrollMetrics: .init(viewportHeight: 120, contentHeight: 300, scrollOffset: 120)
        )

        XCTAssertEqual(metrics, ClipboardKeyboardNavigationMetrics(currentOffset: 120, targetOffset: 80))
    }
}
