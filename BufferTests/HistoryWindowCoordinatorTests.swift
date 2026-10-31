import XCTest

@testable import Buffer

@MainActor
final class HistoryWindowCoordinatorTests: XCTestCase {
    func testToggleWithHotkeyPresentsWindowAndSuppressesQuickPaste() {
        let controller = RecordingHistoryWindowController()
        let coordinator = HistoryWindowCoordinator {
            controller
        }

        coordinator.toggle(trigger: .hotkey)

        XCTAssertEqual(controller.showCalls.count, 1)
        XCTAssertEqual(
            controller.showCalls.last,
            .init(focusSearch: true, activateApp: true, suppressQuickPasteUntilModifiersReleased: true)
        )
        XCTAssertEqual(controller.closeCallCount, 0)
    }

    func testToggleClosesVisibleWindow() {
        let controller = RecordingHistoryWindowController()
        controller.isWindowVisible = true
        let coordinator = HistoryWindowCoordinator {
            controller
        }

        coordinator.toggle(trigger: .hotkey)

        XCTAssertEqual(controller.showCalls.count, 0)
        XCTAssertEqual(controller.closeCallCount, 1)
    }

    func testPresentUsesExplicitIntentValues() {
        let controller = RecordingHistoryWindowController()
        let coordinator = HistoryWindowCoordinator {
            controller
        }

        coordinator.present(
            HistoryWindowPresentationIntent(
                trigger: .statusBar,
                focusSearch: false,
                activateApp: false
            )
        )

        XCTAssertEqual(
            controller.showCalls.last,
            .init(focusSearch: false, activateApp: false, suppressQuickPasteUntilModifiersReleased: false)
        )
    }

    func testRestoreDefaultLayoutForwardsToResolvedController() {
        let controller = RecordingHistoryWindowController()
        let coordinator = HistoryWindowCoordinator {
            controller
        }

        coordinator.present(.standard(for: .statusBar))
        coordinator.restoreDefaultLayout()

        XCTAssertEqual(controller.restoreDefaultLayoutCallCount, 1)
    }

    func testConfigurationChangeClosesAndDiscardsResolvedController() {
        let firstController = RecordingHistoryWindowController()
        let secondController = RecordingHistoryWindowController()
        var controllers = [firstController, secondController]
        let coordinator = HistoryWindowCoordinator {
            controllers.removeFirst()
        }

        coordinator.present(.standard(for: .statusBar))
        coordinator.invalidateForConfigurationChange()
        coordinator.present(.standard(for: .statusBar))

        XCTAssertEqual(firstController.closeCallCount, 1)
        XCTAssertEqual(firstController.showCalls.count, 1)
        XCTAssertEqual(secondController.showCalls.count, 1)
    }
}

@MainActor
private final class RecordingHistoryWindowController: HistoryWindowControlling {
    struct ShowCall: Equatable {
        let focusSearch: Bool
        let activateApp: Bool
        let suppressQuickPasteUntilModifiersReleased: Bool
    }

    var isWindowVisible = false
    private(set) var showCalls: [ShowCall] = []
    private(set) var closeCallCount = 0
    private(set) var restoreDefaultLayoutCallCount = 0

    func showHistoryWindow(
        focusSearch: Bool,
        activateApp: Bool,
        suppressQuickPasteUntilModifiersReleased: Bool
    ) {
        showCalls.append(
            ShowCall(
                focusSearch: focusSearch,
                activateApp: activateApp,
                suppressQuickPasteUntilModifiersReleased: suppressQuickPasteUntilModifiersReleased
            )
        )
        isWindowVisible = true
    }

    func close() {
        closeCallCount += 1
        isWindowVisible = false
    }

    func restoreDefaultLayout() {
        restoreDefaultLayoutCallCount += 1
    }
}
