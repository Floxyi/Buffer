import XCTest
@testable import Buffer

@MainActor
final class ClipboardKeyboardNavigationCoordinatorTests: XCTestCase {
    func testCommitCompletesSynchronouslyWhenNoScrollIsRequired() {
        let coordinator = ClipboardKeyboardNavigationCoordinator()
        let item = ClipboardItem.text("item")
        let request = HistoryKeyboardNavigationRequest(
            itemID: item.id,
            targetIndex: 0,
            generation: 1
        )
        var completedRequest: HistoryKeyboardNavigationRequest?

        coordinator.scheduleCommit(
            for: request,
            scrollController: ScrollController(),
            resolveMetrics: { _ in nil },
            onComplete: { completedRequest = $0 }
        )

        XCTAssertEqual(completedRequest, request)
    }
}
