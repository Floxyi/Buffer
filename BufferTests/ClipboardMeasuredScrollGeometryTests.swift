import XCTest

@testable import Buffer

final class ClipboardMeasuredScrollGeometryTests: XCTestCase {
    func testAttemptCountAndProxyBehaviorVaryByAlignment() {
        XCTAssertEqual(ClipboardMeasuredScrollGeometry.attemptCount(for: .centered), 16)
        XCTAssertEqual(ClipboardMeasuredScrollGeometry.attemptCount(for: .visible), 5)

        XCTAssertTrue(
            ClipboardMeasuredScrollGeometry.shouldUseProxyScroll(
                alignment: .centered,
                measuredTargetFrame: nil,
                attempt: 0
            )
        )
        XCTAssertTrue(
            ClipboardMeasuredScrollGeometry.shouldUseProxyScroll(
                alignment: .centered,
                measuredTargetFrame: CGRect(x: 0, y: 0, width: 10, height: 10),
                attempt: 2
            )
        )
        XCTAssertFalse(
            ClipboardMeasuredScrollGeometry.shouldUseProxyScroll(
                alignment: .centered,
                measuredTargetFrame: CGRect(x: 0, y: 0, width: 10, height: 10),
                attempt: 4
            )
        )
        XCTAssertFalse(
            ClipboardMeasuredScrollGeometry.shouldUseProxyScroll(
                alignment: .visible,
                measuredTargetFrame: CGRect(x: 0, y: 0, width: 10, height: 10),
                attempt: 3
            )
        )
        XCTAssertTrue(
            ClipboardMeasuredScrollGeometry.shouldUseProxyScroll(
                alignment: .visible,
                measuredTargetFrame: nil,
                attempt: 2
            )
        )
    }

    func testEstimatedTargetOffsetUsesDifferentVisualAnchors() {
        XCTAssertEqual(
            ClipboardMeasuredScrollGeometry.estimatedTargetOffset(
                estimatedMidY: 200,
                viewportHeight: 100,
                alignment: .centered
            ),
            150
        )
        XCTAssertEqual(
            ClipboardMeasuredScrollGeometry.estimatedTargetOffset(
                estimatedMidY: 200,
                viewportHeight: 100,
                alignment: .visible
            ),
            165
        )
    }

    func testVisibleAlignmentReturnsAlreadyVisibleWhenFrameFitsViewport() {
        let target = ClipboardMeasuredScrollGeometry.exactTarget(
            measuredTargetFrame: CGRect(x: 0, y: 40, width: 0, height: 20),
            viewportHeight: 100,
            currentOffset: 20,
            contentHeight: 400,
            alignment: .visible
        )

        switch target {
        case .alreadyVisible:
            XCTAssertTrue(true)
        case .scrollTo:
            XCTFail("Expected alreadyVisible")
        }
    }

    func testCenteredAlignmentClampsTargetOffset() {
        let target = ClipboardMeasuredScrollGeometry.exactTarget(
            measuredTargetFrame: CGRect(x: 0, y: 380, width: 0, height: 40),
            viewportHeight: 100,
            currentOffset: 0,
            contentHeight: 400,
            alignment: .centered
        )

        switch target {
        case .alreadyVisible:
            XCTFail("Expected scroll target")
        case .scrollTo(let offset):
            XCTAssertEqual(offset, 300)
        }
    }

    func testVisibleAlignmentScrollsUpWhenTargetIsAboveViewport() {
        let target = ClipboardMeasuredScrollGeometry.exactTarget(
            measuredTargetFrame: CGRect(x: 0, y: 18, width: 0, height: 10),
            viewportHeight: 100,
            currentOffset: 40,
            contentHeight: 400,
            alignment: .visible
        )

        guard case .scrollTo(let offset) = target else {
            return XCTFail("Expected scroll target")
        }
        XCTAssertEqual(offset, 8)
    }

    func testVisibleAlignmentScrollsDownWhenTargetIsBelowViewport() {
        let target = ClipboardMeasuredScrollGeometry.exactTarget(
            measuredTargetFrame: CGRect(x: 0, y: 120, width: 0, height: 20),
            viewportHeight: 100,
            currentOffset: 40,
            contentHeight: 400,
            alignment: .visible
        )

        guard case .scrollTo(let offset) = target else {
            return XCTFail("Expected scroll target")
        }
        XCTAssertEqual(offset, 50)
    }
}

@MainActor
final class ClipboardScrollbarInteractionViewTests: XCTestCase {
    func testThumbPositionDoesNotAnimateOrLagWhenScrollDirectionReverses() throws {
        let view = ScrollbarThumbInteractionView(
            frame: NSRect(x: 0, y: 0, width: 8, height: 300)
        )
        view.layoutSubtreeIfNeeded()

        view.updateMetrics(
            viewportHeight: 500,
            contentHeight: 10_000,
            scrollbarWidth: 4,
            scrollOffset: 8_000,
            onScroll: { _ in }
        )
        view.updateMetrics(
            viewportHeight: 500,
            contentHeight: 10_000,
            scrollbarWidth: 4,
            scrollOffset: 120,
            onScroll: { _ in }
        )

        let thumbLayer = try XCTUnwrap(view.layer?.sublayers?.first)
        let expectedFrame = ScrollbarMetrics.make(
            trackHeight: view.bounds.height,
            viewportHeight: 500,
            contentHeight: 10_000,
            scrollOffset: 120,
            dragProgress: nil
        ).thumbRect

        XCTAssertEqual(thumbLayer.frame.minY, expectedFrame.minY, accuracy: 0.001)
        XCTAssertEqual(thumbLayer.frame.height, expectedFrame.height, accuracy: 0.001)
        XCTAssertTrue(thumbLayer.animationKeys()?.isEmpty ?? true)
    }
}
