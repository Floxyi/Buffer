import XCTest
@testable import Buffer

final class ClipboardListStructureTests: XCTestCase {
    func testRebuildsCacheWhenWeekBoundaryChanges() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let mondayReferenceDate = DateComponents(
            calendar: calendar,
            year: 2026,
            month: 5,
            day: 18,
            hour: 9
        ).date!
        let sundayReferenceDate = DateComponents(
            calendar: calendar,
            year: 2026,
            month: 5,
            day: 17,
            hour: 9
        ).date!
        let lastTuesdayItemDate = DateComponents(
            calendar: calendar,
            year: 2026,
            month: 5,
            day: 12,
            hour: 12
        ).date!

        let items = [
            ClipboardItem(
                type: .text,
                timestamp: lastTuesdayItemDate,
                textContent: "last week item"
            )
        ]

        let staleCache = ClipboardListStructure.makeDisplayCache(
            from: items,
            referenceDate: sundayReferenceDate,
            calendar: calendar
        )

        XCTAssertFalse(staleCache.matches(items: items, referenceDate: mondayReferenceDate, calendar: calendar))

        let refreshedRows = ClipboardListStructure.displayRows(
            from: items,
            referenceDate: mondayReferenceDate,
            calendar: calendar
        )
        let sectionTitle = refreshedRows.compactMap { row -> String? in
            guard case .header(let title, _) = row.kind else { return nil }
            return title
        }.first

        XCTAssertEqual(sectionTitle, "LAST WEEK")
    }
}
