import XCTest
@testable import Buffer

final class AppFormattingTests: XCTestCase {
    func testHistorySectionTitleUsesExpectedBuckets() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        let referenceDate = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 27,
            hour: 12
        ).date!

        let today = referenceDate
        let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate)!
        let thisWeek = calendar.date(byAdding: .day, value: -2, to: referenceDate)!
        let lastWeek = calendar.date(byAdding: .day, value: -8, to: referenceDate)!

        XCTAssertEqual(AppFormatting.historySectionTitle(for: today, calendar: calendar, referenceDate: referenceDate), "TODAY")
        XCTAssertEqual(AppFormatting.historySectionTitle(for: yesterday, calendar: calendar, referenceDate: referenceDate), "YESTERDAY")
        XCTAssertEqual(AppFormatting.historySectionTitle(for: thisWeek, calendar: calendar, referenceDate: referenceDate), "THIS WEEK")
        XCTAssertEqual(AppFormatting.historySectionTitle(for: lastWeek, calendar: calendar, referenceDate: referenceDate), "LAST WEEK")
    }

    func testShortcutDisplayUsesMappedKeyNameAndModifierSymbols() {
        let modifiers = HotkeyModifiers(shift: true, command: true, control: true)

        XCTAssertEqual(AppFormatting.keyDisplayName(for: 9), "V")
        XCTAssertEqual(AppFormatting.keyDisplayName(for: 999), "?")
        XCTAssertEqual(AppFormatting.shortcutDisplay(modifiers: modifiers, keyCode: 9), "⌃⇧⌘V")
    }
}
