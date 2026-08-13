import SwiftUI
import XCTest

@testable import Buffer

@MainActor
final class HistoryPanelConfiguratorTests: XCTestCase {
    func testMakePanelCreatesBorderlessNonactivatingPopup() {
        let panel = HistoryPanelConfigurator().makePanel()

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.styleMask.contains(.titled))
        XCTAssertFalse(panel.styleMask.contains(.closable))
        XCTAssertFalse(panel.styleMask.contains(.miniaturizable))
        XCTAssertFalse(panel.styleMask.contains(.resizable))
        XCTAssertNil(panel.standardWindowButton(.closeButton))
        XCTAssertNil(panel.standardWindowButton(.miniaturizeButton))
        XCTAssertNil(panel.standardWindowButton(.zoomButton))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.isReleasedWhenClosed)
    }

    func testConfigureAppliesPanelAppearanceAndSizing() {
        let configurator = HistoryPanelConfigurator()
        let panel = configurator.makePanel()
        let observer = configurator.configure(panel) {}
        defer { NotificationCenter.default.removeObserver(observer) }

        XCTAssertEqual(panel.level, .popUpMenu)
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.isExcludedFromWindowsMenu)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.transient))
        XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))
        XCTAssertEqual(panel.minSize, HistoryWindowStyle.panelSize)
        XCTAssertEqual(panel.maxSize, HistoryWindowStyle.panelSize)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertFalse(panel.isMovable)
        XCTAssertFalse(panel.isMovableByWindowBackground)
        XCTAssertTrue(panel.hasShadow)
    }

    func testConfigurationControlsSizingAndWindowCapabilities() {
        let minimumSize = NSSize(width: 640, height: 400)
        let maximumSize = NSSize(width: 1_200, height: 900)
        let configurator = HistoryPanelConfigurator(
            configuration: HistoryWindowConfiguration(
                contentSize: NSSize(width: 900, height: 600),
                minimumSize: minimumSize,
                maximumSize: maximumSize,
                allowsResizing: true,
                allowsMoving: true,
                appearance: BufferAppearanceConfiguration(
                    mode: .dark,
                    surfaceStyle: .opaque
                )
            )
        )
        let panel = configurator.makePanel()
        let observer = configurator.configure(panel) {}
        defer { NotificationCenter.default.removeObserver(observer) }

        XCTAssertTrue(panel.styleMask.contains(.resizable))
        XCTAssertEqual(panel.minSize, minimumSize)
        XCTAssertEqual(panel.maxSize, maximumSize)
        XCTAssertTrue(panel.isMovable)
        XCTAssertTrue(panel.isMovableByWindowBackground)
        XCTAssertEqual(panel.appearance?.name, .darkAqua)
    }

    func testCloseOrdersPanelOutForReuse() {
        let panel = HistoryPanelConfigurator().makePanel()
        panel.orderFront(nil)
        XCTAssertTrue(panel.isVisible)

        panel.close()

        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(panel.isReleasedWhenClosed)
    }

    func testProgrammaticPasteDismissalDoesNotTriggerClickOutsideHandling() {
        let panel = HistoryPanelConfigurator().makePanel()
        var clickOutsideCount = 0
        panel.onClickOutside = { clickOutsideCount += 1 }
        panel.dismissesWhenResigningKey = false

        panel.resignKey()

        XCTAssertEqual(clickOutsideCount, 0)
    }

    func testNativeAlertAttachesToBorderlessHistoryPanel() {
        let panel = HistoryPanelConfigurator().makePanel()
        panel.orderFront(nil)
        defer { panel.close() }

        let alert = NSAlert()
        alert.messageText = "Permission Required"
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: panel)

        let attachedSheet = panel.attachedSheet
        XCTAssertNotNil(attachedSheet)
        if let attachedSheet {
            panel.endSheet(attachedSheet)
        }
    }

    func testMakeContentConfigurationReturnsAnimatedEffectContainer() {
        let configurator = HistoryPanelConfigurator()
        let configuration = configurator.makeContentConfiguration(
            rootView: Color.clear,
            frame: NSRect(x: 0, y: 0, width: 120, height: 80)
        )

        XCTAssertEqual(configuration.containerView.subviews.count, 1)
        XCTAssertTrue(configuration.containerView.subviews[0] === configuration.animatedContentView)
        XCTAssertEqual(configuration.animatedContentView.subviews.count, 1)
    }
}

@MainActor
final class ClickModifierDetectorTests: XCTestCase {
    func testSingleClickRoutesOnlyPrimaryInteraction() throws {
        let view = ClickModifierDetector.ClickView()
        var primaryModifiers: NSEvent.ModifierFlags?
        var doubleClickCount = 0
        view.onClickWithModifiers = { primaryModifiers = $0 }
        view.onDoubleClick = { doubleClickCount += 1 }

        view.mouseDown(with: try mouseDownEvent(clickCount: 1, modifiers: .command))

        XCTAssertEqual(primaryModifiers, .command)
        XCTAssertEqual(doubleClickCount, 0)
    }

    func testDoubleClickRoutesOnlyCommitInteraction() throws {
        let view = ClickModifierDetector.ClickView()
        var primaryClickCount = 0
        var doubleClickCount = 0
        view.onClickWithModifiers = { _ in primaryClickCount += 1 }
        view.onDoubleClick = { doubleClickCount += 1 }

        view.mouseDown(with: try mouseDownEvent(clickCount: 2))

        XCTAssertEqual(primaryClickCount, 0)
        XCTAssertEqual(doubleClickCount, 1)
    }

    func testPointerMovementIsForwarded() throws {
        let view = ClickModifierDetector.ClickView()
        var pointerMoveCount = 0
        view.onPointerMoved = { pointerMoveCount += 1 }

        view.mouseMoved(with: try mouseEvent(type: .mouseMoved))

        XCTAssertEqual(pointerMoveCount, 1)
    }

    private func mouseDownEvent(
        clickCount: Int,
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try mouseEvent(
            type: .leftMouseDown,
            clickCount: clickCount,
            modifiers: modifiers
        )
    }

    private func mouseEvent(
        type: NSEvent.EventType,
        clickCount: Int = 0,
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: clickCount,
                pressure: 1
            )
        )
    }
}

@MainActor
final class ClipboardListHoverCoordinatorTests: XCTestCase {
    func testScrollClearsActiveHoverAndSuppressesSyntheticEnterEvents() {
        let coordinator = ClipboardListHoverCoordinator()
        let firstItemID = UUID()
        let secondItemID = UUID()
        var clearedItemIDs: [UUID] = []

        XCTAssertTrue(
            coordinator.activate(itemID: firstItemID) {
                clearedItemIDs.append(firstItemID)
            }
        )

        coordinator.suppressUntilPointerMoves()

        XCTAssertEqual(clearedItemIDs, [firstItemID])
        XCTAssertFalse(
            coordinator.activate(itemID: secondItemID) {
                clearedItemIDs.append(secondItemID)
            }
        )
        XCTAssertEqual(clearedItemIDs, [firstItemID])
    }

    func testPointerMovementReenablesHoverAfterScroll() {
        let coordinator = ClipboardListHoverCoordinator()
        let itemID = UUID()
        var clearCount = 0

        coordinator.suppressUntilPointerMoves()

        XCTAssertTrue(
            coordinator.activateFromPointerMovement(itemID: itemID) {
                clearCount += 1
            }
        )

        coordinator.suppressUntilPointerMoves()
        XCTAssertEqual(clearCount, 1)
    }

    func testActivatingAnotherRowClearsOnlyPreviousHover() {
        let coordinator = ClipboardListHoverCoordinator()
        let firstItemID = UUID()
        let secondItemID = UUID()
        var firstClearCount = 0
        var secondClearCount = 0

        coordinator.activate(itemID: firstItemID) {
            firstClearCount += 1
        }
        coordinator.activate(itemID: secondItemID) {
            secondClearCount += 1
        }

        XCTAssertEqual(firstClearCount, 1)
        XCTAssertEqual(secondClearCount, 0)

        coordinator.deactivate(itemID: firstItemID)
        coordinator.suppressUntilPointerMoves()

        XCTAssertEqual(firstClearCount, 1)
        XCTAssertEqual(secondClearCount, 1)
    }
}
