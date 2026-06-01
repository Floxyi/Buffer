import AppKit
import XCTest
@testable import Buffer

@MainActor
final class HistoryQuickPasteControllerTests: XCTestCase {
    func testPrepareForWindowOpenRequiresModifierResetWhenCommandIsHeld() {
        let controller = HistoryQuickPasteController()

        let state = controller.prepareForWindowOpen(
            using: [.command],
            forceModifierReset: false,
            state: HistoryQuickPasteState(showsQuickPasteNumbers: true, quickPasteNeedsModifierReset: false)
        )

        XCTAssertTrue(state.quickPasteNeedsModifierReset)
        XCTAssertFalse(state.showsQuickPasteNumbers)
    }

    func testModifierResetClearsOnlyAfterRelevantFlagsAreReleased() {
        let controller = HistoryQuickPasteController()
        let initial = HistoryQuickPasteState(showsQuickPasteNumbers: false, quickPasteNeedsModifierReset: true)

        let stillHeld = controller.handleModifierFlagsChange(
            [.command],
            state: initial,
            isQuickPasteEnabled: true
        )
        let released = controller.handleModifierFlagsChange(
            [],
            state: stillHeld,
            isQuickPasteEnabled: true
        )

        XCTAssertTrue(stillHeld.quickPasteNeedsModifierReset)
        XCTAssertFalse(stillHeld.showsQuickPasteNumbers)
        XCTAssertFalse(released.quickPasteNeedsModifierReset)
        XCTAssertFalse(released.showsQuickPasteNumbers)
    }

    func testCommandOnlyShowsQuickPasteNumbersWhenEnabled() {
        let controller = HistoryQuickPasteController()

        let shown = controller.handleModifierFlagsChange(
            [.command],
            state: HistoryQuickPasteState(),
            isQuickPasteEnabled: true
        )
        let hidden = controller.handleModifierFlagsChange(
            [.command, .shift],
            state: HistoryQuickPasteState(),
            isQuickPasteEnabled: true
        )

        XCTAssertTrue(shown.showsQuickPasteNumbers)
        XCTAssertFalse(hidden.showsQuickPasteNumbers)
    }

    func testBadgeNumberByItemIDSkipsPinnedWhenNormalEntriesPreferred() {
        let defaults = makeTestDefaults()
        let settings = SettingsManager(
            defaults: defaults,
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        settings.setQuickPasteSettings(
            QuickPasteSettings(enabled: true, numberingStart: .normalEntries, entryCount: 3)
        )

        var pinned = ClipboardItem.text("pinned")
        pinned.isPinned = true
        pinned.pinnedAt = Date()
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")
        let third = ClipboardItem.text("third")
        let badges = HistoryQuickPasteController().badgeNumberByItemID(
            for: [pinned, first, second, third],
            settings: settings
        )

        XCTAssertNil(badges[pinned.id])
        XCTAssertEqual(badges[first.id], 1)
        XCTAssertEqual(badges[second.id], 2)
        XCTAssertEqual(badges[third.id], 3)
    }

    func testItemToPasteReturnsAddressableUnpinnedItem() {
        let defaults = makeTestDefaults()
        let settings = SettingsManager(
            defaults: defaults,
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        settings.setQuickPasteSettings(
            QuickPasteSettings(enabled: true, numberingStart: .normalEntries, entryCount: 2)
        )

        var pinned = ClipboardItem.text("pinned")
        pinned.isPinned = true
        pinned.pinnedAt = Date()
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")
        let resolved = HistoryQuickPasteController().itemToPaste(
            at: 1,
            in: [pinned, first, second],
            settings: settings
        )

        XCTAssertEqual(resolved?.id, second.id)
    }
}
