import XCTest
@testable import Buffer

final class SettingsLoadedStateTests: XCTestCase {
    func testLoadsPersistedValuesIntoGroupedState() {
        let defaults = makeTestDefaults()
        defaults.set(250, forKey: SettingsKey.historyLimit.rawValue)
        defaults.set(false, forKey: SettingsKey.keepSearchTextAfterPaste.rawValue)
        defaults.set(true, forKey: SettingsKey.keepSearchTextAfterClosing.rawValue)
        defaults.set(HistoryWindowOpenBehavior.keepLastSelection.rawValue, forKey: SettingsKey.historyWindowOpenBehavior.rawValue)
        defaults.set(MenuBarIcon.tray.rawValue, forKey: SettingsKey.menuBarIcon.rawValue)

        let state = SettingsLoadedState.load(
            from: UserDefaultsSettingsStore(defaults: defaults),
            launchAtLoginController: FakeLaunchAtLoginController()
        )

        XCTAssertEqual(state.historyLimit, 250)
        XCTAssertEqual(state.persistedHistoryLimit, 250)
        XCTAssertFalse(state.keepSearchTextAfterPaste)
        XCTAssertTrue(state.keepSearchTextAfterClosing)
        XCTAssertEqual(state.historyWindowOpenBehavior, .keepLastSelection)
        XCTAssertEqual(state.menuBarIcon, .tray)
    }

    func testDefaultsMatchSettingsDefaults() {
        XCTAssertEqual(SettingsLoadedState.defaults.historyLimit, SettingsDefaults.defaultHistoryLimit)
        XCTAssertEqual(SettingsLoadedState.defaults.quickPasteEntryCount, SettingsDefaults.defaultQuickPasteSettings.entryCount)
        XCTAssertEqual(SettingsLoadedState.defaults.menuBarIcon, SettingsDefaults.defaultMenuBarIcon)
    }
}
