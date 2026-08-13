import SwiftUI
import XCTest
@testable import Buffer

@MainActor
final class SettingsFormBindingsTests: XCTestCase {
    func testSearchBehaviorBindingPreservesSiblingValues() {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )

        settings.setSearchBehavior(
            SearchBehaviorSettings(
                keepSearchTextAfterPaste: false,
                keepSearchTextAfterClosing: true,
                confirmDeleteWithKeyboardShortcut: true
            )
        )

        settings.formBindings.searchBehavior.keepSearchTextAfterPaste.wrappedValue = true

        XCTAssertTrue(settings.keepSearchTextAfterPaste)
        XCTAssertTrue(settings.keepSearchTextAfterClosing)
        XCTAssertTrue(settings.confirmDeleteWithKeyboardShortcut)
    }

    func testQuickPasteBindingPreservesSiblingValues() {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )

        settings.setQuickPasteSettings(
            QuickPasteSettings(
                enabled: false,
                numberingStart: .pinnedSection,
                entryCount: 5
            )
        )

        settings.formBindings.quickPaste.entryCount.wrappedValue = 8

        XCTAssertFalse(settings.quickPasteEnabled)
        XCTAssertEqual(settings.quickPasteNumberingStart, .pinnedSection)
        XCTAssertEqual(settings.quickPasteEntryCount, 8)
    }

    func testPrivacyBindingPreservesSiblingValues() {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )

        settings.setPrivacySettings(
            PrivacySettings(
                historyRetentionPeriod: .oneWeek,
                enableWebsitePreviews: false
            )
        )

        settings.formBindings.privacy.enableWebsitePreviews.wrappedValue = true

        XCTAssertEqual(settings.historyRetentionPeriod, .oneWeek)
        XCTAssertTrue(settings.enableWebsitePreviews)
    }

    func testWhitespaceBindingsAlwaysProduceAnExclusiveMode() {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )

        settings.formBindings.whitespace.showSpacesAndTabs.wrappedValue = true
        XCTAssertEqual(settings.clipboardWhitespaceMode, .showSpacesAndTabs)
        XCTAssertTrue(settings.formBindings.whitespace.showSpacesAndTabs.wrappedValue)
        XCTAssertFalse(settings.formBindings.whitespace.trimTrailingSpacesAndTabs.wrappedValue)

        settings.formBindings.whitespace.trimTrailingSpacesAndTabs.wrappedValue = true
        XCTAssertEqual(settings.clipboardWhitespaceMode, .trimTrailingSpacesAndTabs)
        XCTAssertFalse(settings.formBindings.whitespace.showSpacesAndTabs.wrappedValue)
        XCTAssertTrue(settings.formBindings.whitespace.trimTrailingSpacesAndTabs.wrappedValue)

        settings.formBindings.whitespace.trimTrailingSpacesAndTabs.wrappedValue = false
        XCTAssertEqual(settings.clipboardWhitespaceMode, .preserve)
    }
}
