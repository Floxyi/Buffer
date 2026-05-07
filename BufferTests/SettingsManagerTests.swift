import XCTest
@testable import Buffer

@MainActor
final class SettingsManagerTests: XCTestCase {
    func testSetHotkeyPersistsChanges() {
        let defaults = makeTestDefaults()
        let launchController = FakeLaunchAtLoginController()
        let settings = SettingsManager(defaults: defaults, launchAtLoginController: launchController)

        let modifiers = HotkeyModifiers(shift: true, command: false, option: true, control: true)
        settings.setHotkey(keyCode: 42, modifiers: modifiers)

        XCTAssertEqual(settings.hotkeyKeyCode, 42)
        XCTAssertEqual(settings.hotkeyModifiers, modifiers)
        XCTAssertEqual(defaults.integer(forKey: "hotkeyKeyCode"), 42)
        XCTAssertEqual(defaults.array(forKey: "hotkeyModifiers") as? [String], modifiers.toArray())
    }

    func testExcludedAppsStaySortedAndMatchByBundleIdentifier() {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )

        settings.addExcludedApp(ExcludedApp(name: "Zed", bundleIdentifier: "app.zed", bundlePath: "/Applications/Zed.app"))
        settings.addExcludedApp(ExcludedApp(name: "Alpha", bundleIdentifier: "app.alpha", bundlePath: "/Applications/Alpha.app"))

        XCTAssertEqual(settings.excludedApps.map(\.name), ["Alpha", "Zed"])
        XCTAssertTrue(settings.shouldExcludeCapture(from: SourceApplicationInfo(
            name: "Alpha",
            bundleIdentifier: "app.alpha",
            bundlePath: "/Applications/Other.app"
        )))
    }

    func testInitialSelectionPreferencePersistsChanges() {
        let defaults = makeTestDefaults()
        let settings = SettingsManager(
            defaults: defaults,
            launchAtLoginController: FakeLaunchAtLoginController()
        )

        settings.setPreferInitialSelectionFromFirstNonPinnedItem(true)

        XCTAssertTrue(settings.preferInitialSelectionFromFirstNonPinnedItem)
        XCTAssertTrue(defaults.bool(forKey: "preferInitialSelectionFromFirstNonPinnedItem"))
    }

    func testBehaviourPreferencesPersistChanges() {
        let defaults = makeTestDefaults()
        let settings = SettingsManager(
            defaults: defaults,
            launchAtLoginController: FakeLaunchAtLoginController()
        )

        settings.setKeepSearchTextAfterPaste(true)
        settings.setTextDetailFontStyle(.regular)
        settings.setTextDetailFontSize(.large)

        XCTAssertTrue(settings.keepSearchTextAfterPaste)
        XCTAssertEqual(settings.textDetailFontStyle, .regular)
        XCTAssertEqual(settings.textDetailFontSize, .large)
        XCTAssertTrue(defaults.bool(forKey: "keepSearchTextAfterPaste"))
        XCTAssertEqual(defaults.string(forKey: "textDetailFontStyle"), TextDetailFontStyle.regular.rawValue)
        XCTAssertEqual(defaults.integer(forKey: "textDetailFontSize"), TextDetailFontSize.large.rawValue)
    }

    func testHistoryRetentionPreferencePersistsChanges() {
        let defaults = makeTestDefaults()
        let settings = SettingsManager(
            defaults: defaults,
            launchAtLoginController: FakeLaunchAtLoginController()
        )

        settings.setHistoryRetentionPeriod(.oneWeek)

        XCTAssertEqual(settings.historyRetentionPeriod, .oneWeek)
        XCTAssertEqual(defaults.string(forKey: "historyRetentionPeriod"), HistoryRetentionPeriod.oneWeek.rawValue)
    }
}
