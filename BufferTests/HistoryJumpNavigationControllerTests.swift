import XCTest
@testable import Buffer

final class HistoryJumpNavigationControllerTests: XCTestCase {
    func testPendingJumpFailureRetriesWithNewGeneration() {
        let controller = HistoryJumpNavigationController()
        let itemID = UUID()
        let initial = controller.beginJump(
            to: itemID,
            state: HistoryNavigationState()
        )
        let request = try! XCTUnwrap(initial.jumpToHistoryState.request)

        let retried = controller.completeJumpScroll(
            request,
            succeeded: false,
            state: initial
        )

        XCTAssertEqual(retried.jumpToHistoryFailureCount, 1)
        XCTAssertEqual(retried.jumpToHistoryState.itemID, itemID)
        XCTAssertEqual(retried.jumpToHistoryState.request?.generation, request.generation + 1)
    }

    func testPendingJumpStopsAfterRetryLimit() {
        let controller = HistoryJumpNavigationController()
        let itemID = UUID()
        var state = controller.beginJump(to: itemID, state: HistoryNavigationState())

        for _ in 0..<3 {
            let request = try! XCTUnwrap(state.jumpToHistoryState.request)
            state = controller.completeJumpScroll(request, succeeded: false, state: state)
        }

        XCTAssertEqual(state.jumpToHistoryState, .idle)
        XCTAssertEqual(state.jumpToHistoryFailureCount, 0)
    }

    func testScrollingFailureReturnsToIdleWithoutRetry() {
        let controller = HistoryJumpNavigationController()
        let itemID = UUID()
        let pending = controller.beginJump(to: itemID, state: HistoryNavigationState())
        let request = try! XCTUnwrap(pending.jumpToHistoryState.request)
        let scrolling = controller.markJumpScrollStarted(request, state: pending)

        let completed = controller.completeJumpScroll(request, succeeded: false, state: scrolling)

        XCTAssertEqual(completed.jumpToHistoryState, .idle)
        XCTAssertEqual(completed.jumpToHistoryFailureCount, 0)
    }

    func testRequestKeyboardNavigationClearsRequestWhenTargetIsOutOfBounds() {
        let controller = HistoryJumpNavigationController()
        let items = [ClipboardItem.text("only")]
        let initial = HistoryNavigationState(
            jumpToHistoryState: .idle,
            jumpToHistoryGenerationCounter: 0,
            jumpToHistoryFailureCount: 0,
            keyboardNavigationRequest: HistoryKeyboardNavigationRequest(itemID: items[0].id, targetIndex: 0, generation: 1),
            keyboardNavigationGenerationCounter: 1
        )

        let state = controller.requestKeyboardNavigation(
            by: 1,
            selectedIndex: 0,
            filteredItems: items,
            state: initial
        )

        XCTAssertNil(state.keyboardNavigationRequest)
    }
}
