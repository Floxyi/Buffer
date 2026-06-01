import XCTest
@testable import Buffer

final class ClipboardKeyboardNavigationCoordinatorTests: XCTestCase {
    func testShouldPreferImmediateScrollWhenRequestsAreCloseTogether() {
        XCTAssertTrue(
            ClipboardKeyboardNavigationCoordinator.shouldPreferImmediateScroll(
                currentTimestamp: 10.05,
                previousTimestamp: 10.0
            )
        )
    }

    func testShouldNotPreferImmediateScrollWhenRequestsAreFarApart() {
        XCTAssertFalse(
            ClipboardKeyboardNavigationCoordinator.shouldPreferImmediateScroll(
                currentTimestamp: 10.25,
                previousTimestamp: 10.0
            )
        )
    }
}
