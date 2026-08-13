import XCTest

@testable import Buffer

@MainActor
final class ClipboardKeyboardNavigationCoordinatorTests: XCTestCase {
    func testRouterDeliversRequestSynchronously() {
        let router = HistoryKeyboardScrollRouter()
        let request = HistoryKeyboardScrollRequest(itemID: UUID(), targetIndex: 4, generation: 7)
        var receivedRequest: HistoryKeyboardScrollRequest?
        router.register { receivedRequest = $0 }

        router.submit(request)

        XCTAssertEqual(receivedRequest, request)
    }

    func testStaleRegistrationCannotUnregisterReplacement() {
        let router = HistoryKeyboardScrollRouter()
        let staleRegistrationID = router.register { _ in }
        var receivedGeneration: UInt?
        router.register { receivedGeneration = $0.generation }

        router.unregister(staleRegistrationID)
        router.submit(
            HistoryKeyboardScrollRequest(itemID: UUID(), targetIndex: 0, generation: 3)
        )

        XCTAssertEqual(receivedGeneration, 3)
    }

    func testAlreadyVisibleRequestCompletesViewportOperationWithoutScrolling() {
        let coordinator = ClipboardKeyboardNavigationCoordinator()
        let item = ClipboardItem.text("item")
        let request = HistoryKeyboardScrollRequest(
            itemID: item.id,
            targetIndex: 0,
            generation: 1
        )

        let result = coordinator.scrollSelectedItemIntoView(
            request: request,
            targetFrameExists: true,
            scrollController: ScrollController(),
            resolveMetrics: { _ in nil }
        )

        XCTAssertEqual(result, .alreadyVisible)
    }

    func testOlderGenerationCannotApplyAfterNewerRequest() {
        let coordinator = ClipboardKeyboardNavigationCoordinator()
        let item = ClipboardItem.text("item")
        let newer = HistoryKeyboardScrollRequest(itemID: item.id, targetIndex: 2, generation: 2)
        let older = HistoryKeyboardScrollRequest(itemID: item.id, targetIndex: 1, generation: 1)

        _ = coordinator.scrollSelectedItemIntoView(
            request: newer,
            targetFrameExists: true,
            scrollController: ScrollController(),
            resolveMetrics: { _ in nil }
        )
        let result = coordinator.scrollSelectedItemIntoView(
            request: older,
            targetFrameExists: true,
            scrollController: ScrollController(),
            resolveMetrics: { _ in nil }
        )

        XCTAssertEqual(result, .stale)
    }

    func testInvalidatedRequestCannotApply() {
        let coordinator = ClipboardKeyboardNavigationCoordinator()
        let request = HistoryKeyboardScrollRequest(itemID: UUID(), targetIndex: 0, generation: 1)
        _ = coordinator.scrollSelectedItemIntoView(
            request: request,
            targetFrameExists: true,
            scrollController: ScrollController(),
            resolveMetrics: { _ in nil }
        )
        coordinator.invalidateCurrentRequest()

        let result = coordinator.scrollSelectedItemIntoView(
            request: request,
            targetFrameExists: true,
            scrollController: ScrollController(),
            resolveMetrics: { _ in nil }
        )

        XCTAssertEqual(result, .stale)
    }
}
