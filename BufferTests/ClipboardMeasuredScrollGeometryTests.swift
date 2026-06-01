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
