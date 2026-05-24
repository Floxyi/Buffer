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

    func testBehaviourPreferencesPersistChanges() {
        let defaults = makeTestDefaults()
        let settings = SettingsManager(
            defaults: defaults,
            launchAtLoginController: FakeLaunchAtLoginController()
        )

        settings.setKeepSearchTextAfterPaste(true)
        settings.setKeepSearchTextAfterClosing(false)
        settings.setHistoryWindowOpenBehavior(.keepLastSelection)
        settings.setQuickPasteEnabled(false)
        settings.setQuickPasteNumberingStart(.normalEntries)
        settings.setQuickPasteEntryCount(10)
        settings.setTextDetailFontStyle(.regular)
        settings.setTextDetailFontSize(.large)
        settings.setEnableWebsitePreviews(false)

        XCTAssertTrue(settings.keepSearchTextAfterPaste)
        XCTAssertFalse(settings.keepSearchTextAfterClosing)
        XCTAssertEqual(settings.historyWindowOpenBehavior, .keepLastSelection)
        XCTAssertFalse(settings.quickPasteEnabled)
        XCTAssertEqual(settings.quickPasteNumberingStart, .normalEntries)
        XCTAssertEqual(settings.quickPasteEntryCount, SettingsManager.quickPasteEntryCountRange.upperBound)
        XCTAssertEqual(settings.textDetailFontStyle, .regular)
        XCTAssertEqual(settings.textDetailFontSize, .large)
        XCTAssertFalse(settings.enableWebsitePreviews)
        XCTAssertTrue(defaults.bool(forKey: "keepSearchTextAfterPaste"))
        XCTAssertFalse(defaults.bool(forKey: "keepSearchTextAfterClosing"))
        XCTAssertEqual(
            defaults.string(forKey: "historyWindowOpenBehavior"),
            HistoryWindowOpenBehavior.keepLastSelection.rawValue
        )
        XCTAssertNil(defaults.object(forKey: "keepHistoryWindowSelectionOnReopen"))
        XCTAssertFalse(defaults.bool(forKey: "quickPasteEnabled"))
        XCTAssertEqual(
            defaults.string(forKey: "quickPasteNumberingStart"),
            QuickPasteNumberingStart.normalEntries.rawValue
        )
        XCTAssertEqual(defaults.integer(forKey: "quickPasteEntryCount"), SettingsManager.quickPasteEntryCountRange.upperBound)
        XCTAssertEqual(defaults.string(forKey: "textDetailFontStyle"), TextDetailFontStyle.regular.rawValue)
        XCTAssertEqual(defaults.integer(forKey: "textDetailFontSize"), TextDetailFontSize.large.rawValue)
        XCTAssertFalse(defaults.bool(forKey: "enableWebsitePreviews"))
    }

    func testKeepSearchTextAfterClosingDefaultsToDisabled() {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )

        XCTAssertFalse(settings.keepSearchTextAfterClosing)
        XCTAssertEqual(settings.historyWindowOpenBehavior, .selectFirstNonPinnedItem)
    }

    func testLegacyKeepLastSelectionValueMigratesToUnifiedReopenBehavior() {
        let defaults = makeTestDefaults()
        defaults.set(HistoryWindowOpenBehavior.keepLastSelection.rawValue, forKey: "historyWindowOpenBehavior")

        let settings = SettingsManager(
            defaults: defaults,
            launchAtLoginController: FakeLaunchAtLoginController()
        )

        XCTAssertEqual(settings.historyWindowOpenBehavior, .keepLastSelection)
    }

    func testLegacyDedicatedToggleMigratesToUnifiedReopenBehavior() {
        let defaults = makeTestDefaults()
        defaults.set(true, forKey: "keepHistoryWindowSelectionOnReopen")
        defaults.set(HistoryWindowOpenBehavior.selectAnyFirstItem.rawValue, forKey: "historyWindowOpenBehavior")

        let settings = SettingsManager(
            defaults: defaults,
            launchAtLoginController: FakeLaunchAtLoginController()
        )

        XCTAssertEqual(settings.historyWindowOpenBehavior, .keepLastSelection)
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

    func testHistoryLimitIsClampedAndPersistedAsInteger() {
        let defaults = makeTestDefaults()
        let settings = SettingsManager(
            defaults: defaults,
            launchAtLoginController: FakeLaunchAtLoginController()
        )

        settings.setHistoryLimit(0)
        XCTAssertEqual(settings.historyLimit, SettingsManager.historyLimitRange.lowerBound)
        XCTAssertEqual(defaults.integer(forKey: "historyLimit"), SettingsManager.historyLimitRange.lowerBound)

        settings.setHistoryLimit(25_000)
        XCTAssertEqual(settings.historyLimit, SettingsManager.historyLimitRange.upperBound)
        XCTAssertEqual(defaults.integer(forKey: "historyLimit"), SettingsManager.historyLimitRange.upperBound)
    }

    func testQuickPasteEntryCountIsClamped() {
        let defaults = makeTestDefaults()
        let settings = SettingsManager(
            defaults: defaults,
            launchAtLoginController: FakeLaunchAtLoginController()
        )

        settings.setQuickPasteEntryCount(0)
        XCTAssertEqual(settings.quickPasteEntryCount, SettingsManager.quickPasteEntryCountRange.lowerBound)
        XCTAssertEqual(defaults.integer(forKey: "quickPasteEntryCount"), SettingsManager.quickPasteEntryCountRange.lowerBound)

        settings.setQuickPasteEntryCount(25)
        XCTAssertEqual(settings.quickPasteEntryCount, SettingsManager.quickPasteEntryCountRange.upperBound)
        XCTAssertEqual(defaults.integer(forKey: "quickPasteEntryCount"), SettingsManager.quickPasteEntryCountRange.upperBound)
    }
}
