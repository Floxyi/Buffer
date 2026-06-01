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

        settings.setSearchBehavior(
            SearchBehaviorSettings(
                keepSearchTextAfterPaste: true,
                keepSearchTextAfterClosing: false,
                confirmDeleteWithKeyboardShortcut: false
            )
        )
        settings.setHistoryWindowOpenBehavior(.keepLastSelection)
        settings.setQuickPasteSettings(
            QuickPasteSettings(
                enabled: false,
                numberingStart: .normalEntries,
                entryCount: 10
            )
        )
        settings.setTextDetailSettings(
            TextDetailSettings(style: .regular, size: .large)
        )
        settings.setPrivacySettings(
            PrivacySettings(
                historyRetentionPeriod: settings.historyRetentionPeriod,
                enableWebsitePreviews: false
            )
        )

        XCTAssertTrue(settings.keepSearchTextAfterPaste)
        XCTAssertFalse(settings.keepSearchTextAfterClosing)
        XCTAssertFalse(settings.confirmDeleteWithKeyboardShortcut)
        XCTAssertEqual(settings.historyWindowOpenBehavior, .keepLastSelection)
        XCTAssertFalse(settings.quickPasteEnabled)
        XCTAssertEqual(settings.quickPasteNumberingStart, .normalEntries)
        XCTAssertEqual(settings.quickPasteEntryCount, SettingsDefaults.quickPasteEntryCountRange.upperBound)
        XCTAssertEqual(settings.textDetailFontStyle, .regular)
        XCTAssertEqual(settings.textDetailFontSize, .large)
        XCTAssertFalse(settings.enableWebsitePreviews)
        XCTAssertTrue(defaults.bool(forKey: SettingsKey.keepSearchTextAfterPaste.rawValue))
        XCTAssertFalse(defaults.bool(forKey: SettingsKey.keepSearchTextAfterClosing.rawValue))
        XCTAssertFalse(defaults.bool(forKey: SettingsKey.confirmDeleteWithKeyboardShortcut.rawValue))
        XCTAssertEqual(
            defaults.string(forKey: SettingsKey.historyWindowOpenBehavior.rawValue),
            HistoryWindowOpenBehavior.keepLastSelection.rawValue
        )
        XCTAssertNil(defaults.object(forKey: SettingsKey.keepHistoryWindowSelectionOnReopen.rawValue))
        XCTAssertFalse(defaults.bool(forKey: SettingsKey.quickPasteEnabled.rawValue))
        XCTAssertEqual(
            defaults.string(forKey: SettingsKey.quickPasteNumberingStart.rawValue),
            QuickPasteNumberingStart.normalEntries.rawValue
        )
        XCTAssertEqual(defaults.integer(forKey: SettingsKey.quickPasteEntryCount.rawValue), SettingsDefaults.quickPasteEntryCountRange.upperBound)
        XCTAssertEqual(defaults.string(forKey: SettingsKey.textDetailFontStyle.rawValue), TextDetailFontStyle.regular.rawValue)
        XCTAssertEqual(defaults.integer(forKey: SettingsKey.textDetailFontSize.rawValue), TextDetailFontSize.large.rawValue)
        XCTAssertFalse(defaults.bool(forKey: SettingsKey.enableWebsitePreviews.rawValue))
    }

    func testKeepSearchTextAfterClosingDefaultsToDisabled() {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )

        XCTAssertFalse(settings.keepSearchTextAfterClosing)
        XCTAssertTrue(settings.confirmDeleteWithKeyboardShortcut)
        XCTAssertEqual(settings.historyWindowOpenBehavior, .selectFirstNonPinnedItem)
    }

    func testLegacyKeepLastSelectionValueMigratesToUnifiedReopenBehavior() {
        let defaults = makeTestDefaults()
        defaults.set(HistoryWindowOpenBehavior.keepLastSelection.rawValue, forKey: SettingsKey.historyWindowOpenBehavior.rawValue)

        let settings = SettingsManager(
            defaults: defaults,
            launchAtLoginController: FakeLaunchAtLoginController()
        )

        XCTAssertEqual(settings.historyWindowOpenBehavior, .keepLastSelection)
    }

    func testLegacyDedicatedToggleMigratesToUnifiedReopenBehavior() {
        let defaults = makeTestDefaults()
        defaults.set(true, forKey: SettingsKey.keepHistoryWindowSelectionOnReopen.rawValue)
        defaults.set(HistoryWindowOpenBehavior.selectAnyFirstItem.rawValue, forKey: SettingsKey.historyWindowOpenBehavior.rawValue)

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

        settings.setPrivacySettings(
            PrivacySettings(
                historyRetentionPeriod: .oneWeek,
                enableWebsitePreviews: settings.enableWebsitePreviews
            )
        )

        XCTAssertEqual(settings.historyRetentionPeriod, .oneWeek)
        XCTAssertEqual(defaults.string(forKey: SettingsKey.historyRetentionPeriod.rawValue), HistoryRetentionPeriod.oneWeek.rawValue)
    }

    func testHistoryLimitIsClampedAndPersistedAsInteger() {
        let defaults = makeTestDefaults()
        let settings = SettingsManager(
            defaults: defaults,
            launchAtLoginController: FakeLaunchAtLoginController()
        )

        settings.setHistoryLimit(0)
        XCTAssertEqual(settings.historyLimit, SettingsDefaults.historyLimitRange.lowerBound)
        XCTAssertEqual(defaults.integer(forKey: SettingsKey.historyLimit.rawValue), SettingsDefaults.historyLimitRange.lowerBound)

        settings.setHistoryLimit(25_000)
        XCTAssertEqual(settings.historyLimit, SettingsDefaults.historyLimitRange.upperBound)
        XCTAssertEqual(defaults.integer(forKey: SettingsKey.historyLimit.rawValue), SettingsDefaults.historyLimitRange.upperBound)
    }

    func testQuickPasteEntryCountIsClamped() {
        let defaults = makeTestDefaults()
        let settings = SettingsManager(
            defaults: defaults,
            launchAtLoginController: FakeLaunchAtLoginController()
        )

        settings.setQuickPasteSettings(
            QuickPasteSettings(
                enabled: settings.quickPasteEnabled,
                numberingStart: settings.quickPasteNumberingStart,
                entryCount: 0
            )
        )
        XCTAssertEqual(settings.quickPasteEntryCount, SettingsDefaults.quickPasteEntryCountRange.lowerBound)
        XCTAssertEqual(defaults.integer(forKey: SettingsKey.quickPasteEntryCount.rawValue), SettingsDefaults.quickPasteEntryCountRange.lowerBound)

        settings.setQuickPasteSettings(
            QuickPasteSettings(
                enabled: settings.quickPasteEnabled,
                numberingStart: settings.quickPasteNumberingStart,
                entryCount: 25
            )
        )
        XCTAssertEqual(settings.quickPasteEntryCount, SettingsDefaults.quickPasteEntryCountRange.upperBound)
        XCTAssertEqual(defaults.integer(forKey: SettingsKey.quickPasteEntryCount.rawValue), SettingsDefaults.quickPasteEntryCountRange.upperBound)
    }

    func testInvalidHistoryWindowBehaviorFallsBackToDefault() {
        let defaults = makeTestDefaults()
        defaults.set("invalid", forKey: SettingsKey.historyWindowOpenBehavior.rawValue)

        let settings = SettingsManager(
            defaults: defaults,
            launchAtLoginController: FakeLaunchAtLoginController()
        )

        XCTAssertEqual(settings.historyWindowOpenBehavior, SettingsDefaults.defaultHistoryWindowOpenBehavior)
    }

    func testInvalidExcludedAppsPayloadFallsBackToEmptyList() {
        let defaults = makeTestDefaults()
        defaults.set(Data("invalid".utf8), forKey: SettingsKey.excludedApps.rawValue)

        let settings = SettingsManager(
            defaults: defaults,
            launchAtLoginController: FakeLaunchAtLoginController()
        )

        XCTAssertEqual(settings.excludedApps, [])
    }
}
