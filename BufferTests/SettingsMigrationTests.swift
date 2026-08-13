import Foundation
import XCTest
@testable import Buffer

final class SettingsMigrationTests: XCTestCase {
    func testLoadHotkeyValuesUseStoredKeysWhenPresent() {
        let defaults = makeTestDefaults()
        let store = UserDefaultsSettingsStore(defaults: defaults)
        defaults.set(["shift", "option"], forKey: SettingsKey.hotkeyModifiers.rawValue)
        defaults.set(33, forKey: SettingsKey.hotkeyKeyCode.rawValue)

        let modifiers = SettingsMigration.loadHotkeyModifiers(from: store)
        let keyCode = SettingsMigration.loadHotkeyKeyCode(from: store)

        XCTAssertEqual(modifiers, HotkeyModifiers(shift: true, command: false, option: true, control: false))
        XCTAssertEqual(keyCode, 33)
    }

    func testLoadHistoryWindowOpenBehaviorPrefersLegacyToggle() {
        let defaults = makeTestDefaults()
        let store = UserDefaultsSettingsStore(defaults: defaults)
        defaults.set(false, forKey: SettingsKey.keepHistoryWindowSelectionOnReopen.rawValue)
        defaults.set(HistoryWindowOpenBehavior.keepLastSelection.rawValue, forKey: SettingsKey.historyWindowOpenBehavior.rawValue)

        let behavior = SettingsMigration.loadHistoryWindowOpenBehavior(from: store)

        XCTAssertEqual(behavior, SettingsDefaults.defaultHistoryWindowOpenBehavior)
    }

    func testLoadQuickPasteSettingsFallsBackToDefaultsForInvalidStoredValues() {
        let defaults = makeTestDefaults()
        let store = UserDefaultsSettingsStore(defaults: defaults)
        defaults.set(true, forKey: SettingsKey.quickPasteEnabled.rawValue)
        defaults.set("invalid", forKey: SettingsKey.quickPasteNumberingStart.rawValue)
        defaults.set(0, forKey: SettingsKey.quickPasteEntryCount.rawValue)

        let settings = SettingsMigration.loadQuickPasteSettings(from: store)

        XCTAssertTrue(settings.enabled)
        XCTAssertEqual(settings.numberingStart, SettingsDefaults.defaultQuickPasteSettings.numberingStart)
        XCTAssertEqual(settings.entryCount, SettingsDefaults.quickPasteEntryCountRange.lowerBound)
    }

    func testLoadExcludedAppsDecodesStoredPayload() throws {
        let defaults = makeTestDefaults()
        let store = UserDefaultsSettingsStore(defaults: defaults)
        let apps = [
            ExcludedApp(name: "Notes", bundleIdentifier: "com.apple.Notes", bundlePath: "/Applications/Notes.app")
        ]
        defaults.set(try JSONEncoder().encode(apps), forKey: SettingsKey.excludedApps.rawValue)

        let decoded = SettingsMigration.loadExcludedApps(from: store)

        XCTAssertEqual(decoded, apps)
    }

    func testLoadClipboardWhitespaceModeFallsBackForMissingOrInvalidValue() {
        let defaults = makeTestDefaults()
        let store = UserDefaultsSettingsStore(defaults: defaults)

        XCTAssertEqual(
            SettingsMigration.loadClipboardWhitespaceMode(from: store),
            .preserve
        )

        defaults.set("invalid", forKey: SettingsKey.clipboardWhitespaceMode.rawValue)
        XCTAssertEqual(
            SettingsMigration.loadClipboardWhitespaceMode(from: store),
            .preserve
        )

        defaults.set(
            ClipboardWhitespaceMode.showSpacesAndTabs.rawValue,
            forKey: SettingsKey.clipboardWhitespaceMode.rawValue
        )
        XCTAssertEqual(
            SettingsMigration.loadClipboardWhitespaceMode(from: store),
            .showSpacesAndTabs
        )
    }
}
