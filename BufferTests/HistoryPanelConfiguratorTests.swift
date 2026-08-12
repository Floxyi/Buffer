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

    func testCloseOrdersPanelOutForReuse() {
        let panel = HistoryPanelConfigurator().makePanel()
        panel.orderFront(nil)
        XCTAssertTrue(panel.isVisible)

        panel.close()

        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(panel.isReleasedWhenClosed)
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
