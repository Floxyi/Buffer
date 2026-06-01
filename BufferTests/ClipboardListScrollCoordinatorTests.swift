import XCTest
@testable import Buffer

final class ClipboardListScrollCoordinatorTests: XCTestCase {
    func testResolvedKeyboardNavigationTargetOffsetSnapsNearTopToZero() {
        let offset = ClipboardKeyboardNavigationResolver.resolvedTargetOffset(
            rawTargetOffset: 20,
            maxOffset: 400
        )

        XCTAssertEqual(offset, 0)
    }

    func testResolvedKeyboardNavigationTargetOffsetClampsToMaximum() {
        let offset = ClipboardKeyboardNavigationResolver.resolvedTargetOffset(
            rawTargetOffset: 800,
            maxOffset: 250
        )

        XCTAssertEqual(offset, 250)
    }

    func testShouldHideDuringInitialOpenScrollOnlyForTopCommandWithOffset() {
        XCTAssertTrue(
            ClipboardListScrollCoordinator.shouldHideDuringInitialOpenScroll(
                for: .scrollToTop,
                currentScrollOffset: 12
            )
        )
        XCTAssertFalse(
            ClipboardListScrollCoordinator.shouldHideDuringInitialOpenScroll(
                for: .scrollToTop,
                currentScrollOffset: 0
            )
        )
        XCTAssertFalse(
            ClipboardListScrollCoordinator.shouldHideDuringInitialOpenScroll(
                for: .scrollToItem(UUID()),
                currentScrollOffset: 12
            )
        )
    }
}
