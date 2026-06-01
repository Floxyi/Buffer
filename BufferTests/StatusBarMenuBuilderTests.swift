import XCTest
@testable import Buffer

@MainActor
final class StatusBarMenuBuilderTests: XCTestCase {
    func testBuildsExpectedMenuTitles() {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let builder = StatusBarMenuBuilder()
        let target = ActionTarget()

        let menu = builder.makeMenu(
            settings: settings,
            isPaused: false,
            target: target,
            pauseAction: #selector(ActionTarget.performAction),
            clearHistoryAction: #selector(ActionTarget.performAction),
            showSettingsAction: #selector(ActionTarget.performAction),
            quitAction: #selector(ActionTarget.performAction)
        )

        XCTAssertEqual(menu.items.map(\.title), [
            "Shortcut: ⇧⌘V",
            "",
            "Pause Capture",
            "Clear History",
            "",
            "Settings...",
            "",
            "Quit Buffer"
        ])
    }

    private final class ActionTarget: NSObject {
        @objc func performAction() {}
    }
}
