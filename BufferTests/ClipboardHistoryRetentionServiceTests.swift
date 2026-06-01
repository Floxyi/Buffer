import XCTest
@testable import Buffer

final class ClipboardHistoryRetentionServiceTests: XCTestCase {
    func testCutoffIsNilForNeverRetention() {
        let service = ClipboardHistoryRetentionService()

        XCTAssertNil(service.cutoff(for: .never, now: Date(timeIntervalSince1970: 1_000)))
    }

    func testPrunedInitialItemsDropsExpiredEntriesAndPersistsRetainedSet() {
        let now = Date(timeIntervalSince1970: 10_000)
        let fresh = ClipboardItem(timestamp: now.addingTimeInterval(-300), content: .text(TextItemContent(inlineText: "fresh")))
        let stale = ClipboardItem(timestamp: now.addingTimeInterval(-13 * 60 * 60), content: .text(TextItemContent(inlineText: "stale")))
        let persistence = RecordingClipboardHistoryPersistence()
        let service = ClipboardHistoryRetentionService()

        let retained = service.prunedInitialItems(
            from: [fresh, stale],
            retentionPeriod: .twelveHours,
            persistence: persistence,
            now: now
        )

        XCTAssertEqual(retained.map(\.id), [fresh.id])
        XCTAssertEqual(persistence.savedHistorySnapshots.last?.map(\.id), [fresh.id])
    }
}

private final class RecordingClipboardHistoryPersistence: ClipboardHistoryPersisting, @unchecked Sendable {
    private(set) var savedHistorySnapshots: [[ClipboardItem]] = []

    func saveHistory(_ items: [ClipboardItem]) {
        savedHistorySnapshots.append(items)
    }
}
