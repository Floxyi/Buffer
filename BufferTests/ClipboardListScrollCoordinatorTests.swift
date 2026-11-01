import AppKit
import XCTest

@testable import Buffer

@MainActor
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

    func testOpenScrollRequestAppliesOncePerToken() {
        let fixture = makeScrollController()
        let scrollController = fixture.controller
        let coordinator = ClipboardListScrollCoordinator()
        scrollController.scrollTo(offset: 900)

        coordinator.applyOpenScrollRequestIfNeeded(
            request: HistoryOpenListScrollRequest(mode: .scrollToTop),
            requestToken: 1,
            scrollController: scrollController,
            context: makeScrollContext()
        )
        XCTAssertEqual(scrollController.currentScrollOffsetSnapshot(), 0, accuracy: 0.001)

        scrollController.scrollTo(offset: 500)
        coordinator.applyOpenScrollRequestIfNeeded(
            request: HistoryOpenListScrollRequest(mode: .scrollToTop),
            requestToken: 1,
            scrollController: scrollController,
            context: makeScrollContext()
        )
        XCTAssertEqual(scrollController.currentScrollOffsetSnapshot(), 500, accuracy: 0.001)
    }

    func testRestoreScrollOffsetUsesNativeControllerWithoutDeferredRetry() {
        let fixture = makeScrollController()
        let scrollController = fixture.controller
        let coordinator = ClipboardListScrollCoordinator()

        coordinator.restoreScrollOffsetForReopen(
            725,
            scrollController: scrollController
        )

        XCTAssertEqual(scrollController.currentScrollOffsetSnapshot(), 725, accuracy: 0.001)
    }

    private func makeScrollController() -> (controller: ScrollController, scrollView: NSScrollView) {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 3_000))
        let controller = ScrollController()
        controller.configure(scrollView: scrollView, interactionMode: .system)
        return (controller, scrollView)
    }

    private func makeScrollContext() -> ClipboardListScrollContext {
        let snapshotID = UUID()
        let layoutIndex = ClipboardListStructure.makeDisplayCache(
            from: [],
            sourceSnapshotID: snapshotID
        ).layoutIndex
        return ClipboardListScrollContext(
            layoutIndex: layoutIndex,
            itemExists: { _ in false },
            scrollMetrics: { .zero },
            onJumpScrollStarted: { _ in },
            onJumpScrollCompleted: { _, _ in },
            log: { _ in }
        )
    }
}
