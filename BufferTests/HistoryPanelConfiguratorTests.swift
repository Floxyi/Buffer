import XCTest
import SwiftUI
@testable import Buffer

@MainActor
final class HistoryPanelConfiguratorTests: XCTestCase {
    func testConfigureAppliesPanelAppearanceAndSizing() {
        let configurator = HistoryPanelConfigurator()
        let panel = configurator.makePanel()
        let observer = configurator.configure(panel) {}
        defer { NotificationCenter.default.removeObserver(observer) }

        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertEqual(panel.minSize, HistoryWindowStyle.panelSize)
        XCTAssertEqual(panel.maxSize, HistoryWindowStyle.panelSize)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertFalse(panel.isMovable)
        XCTAssertFalse(panel.isMovableByWindowBackground)
        XCTAssertTrue(panel.hasShadow)
        XCTAssertTrue(panel.titlebarAppearsTransparent)
        XCTAssertEqual(panel.titleVisibility, .hidden)
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
