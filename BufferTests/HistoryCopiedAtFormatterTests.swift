import XCTest

@testable import Buffer

final class HistoryCopiedAtFormatterTests: XCTestCase {
    func testUsesRelativeMinuteFormatForToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        let now = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 24,
            hour: 12,
            minute: 36
        ).date!
        let timestamp = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 24,
            hour: 12,
            minute: 35
        ).date!

        XCTAssertEqual(
            HistoryCopiedAtFormatter().string(for: timestamp, now: now, calendar: calendar),
            "1 minute ago"
        )
    }

    func testUsesYesterdayForPreviousDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        let now = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 24,
            hour: 12,
            minute: 36
        ).date!
        let timestamp = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 23,
            hour: 21,
            minute: 15
        ).date!

        XCTAssertEqual(
            HistoryCopiedAtFormatter().string(for: timestamp, now: now, calendar: calendar),
            "Yesterday"
        )
    }
}
