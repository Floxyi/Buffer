import XCTest
@testable import Buffer

@MainActor
final class HistoryListScrollRestorationCoordinatorTests: XCTestCase {
    func testRestoreRunsImmediatelyWhenRestorerExists() {
        let coordinator = HistoryListScrollRestorationCoordinator()
        var restoredOffset: CGFloat?

        coordinator.setOffsetProvider { 84 }
        coordinator.captureCurrentOffset()
        coordinator.setOffsetRestorer { restoredOffset = $0 }
        coordinator.restoreIfNeeded(for: .keepLastSelection)

        XCTAssertEqual(restoredOffset, 84)
    }

    func testRestoreDefersUntilRestorerArrives() {
        let coordinator = HistoryListScrollRestorationCoordinator()
        var restoredOffset: CGFloat?

        coordinator.setOffsetProvider { 42 }
        coordinator.captureCurrentOffset()
        coordinator.restoreIfNeeded(for: .keepLastSelection)
        coordinator.setOffsetRestorer { restoredOffset = $0 }

        XCTAssertEqual(restoredOffset, 42)
    }

    func testRestoreDoesNothingForNonKeepLastSelectionBehavior() {
        let coordinator = HistoryListScrollRestorationCoordinator()
        var restoredOffset: CGFloat?

        coordinator.setOffsetProvider { 42 }
        coordinator.captureCurrentOffset()
        coordinator.setOffsetRestorer { restoredOffset = $0 }
        coordinator.restoreIfNeeded(for: .selectAnyFirstItem)

        XCTAssertNil(restoredOffset)
    }
}
