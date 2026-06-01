import XCTest

@testable import Buffer

final class ClipboardMeasuredScrollGeometryTests: XCTestCase {
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
}
