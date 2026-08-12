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

    func testKeyboardScrollRequestsReceiveIncreasingGenerations() {
        let controller = HistoryJumpNavigationController()
        let item = ClipboardItem.text("only")
        let first = controller.makeKeyboardScrollRequest(
            itemID: item.id,
            targetIndex: 0,
            state: HistoryNavigationState()
        )
        let second = controller.makeKeyboardScrollRequest(
            itemID: item.id,
            targetIndex: 0,
            state: first
        )

        XCTAssertEqual(first.keyboardScrollRequest?.generation, 1)
        XCTAssertEqual(second.keyboardScrollRequest?.generation, 2)
    }
}
