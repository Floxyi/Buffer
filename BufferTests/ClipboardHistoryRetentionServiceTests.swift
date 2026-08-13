import XCTest

@testable import Buffer

final class ClipboardHistoryRetentionServiceTests: XCTestCase {
    func testCutoffIsNilForNeverRetention() {
        let service = ClipboardHistoryRetentionService()

        XCTAssertNil(service.cutoff(for: .never, now: Date(timeIntervalSince1970: 1_000)))
    }

    func testPrunedInitialItemsDropsExpiredEntriesAndPersistsRetainedSet() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let fresh = ClipboardItem(
            timestamp: now.addingTimeInterval(-300), content: .text(TextItemContent(inlineText: "fresh")))
        let stale = ClipboardItem(
            timestamp: now.addingTimeInterval(-13 * 60 * 60), content: .text(TextItemContent(inlineText: "stale")))
        let persistence = RecordingClipboardHistoryPersistence()
        let service = ClipboardHistoryRetentionService()

        let retained = try service.prunedInitialItems(
            from: [fresh, stale],
            retentionPeriod: .twelveHours,
            persistence: persistence,
            now: now
        )

        XCTAssertEqual(retained.map(\.id), [fresh.id])
        XCTAssertEqual(persistence.savedHistorySnapshots.last?.map(\.id), [fresh.id])
    }

    func testPrunedInitialItemsPreservesPinnedAndBookmarkedEntries() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let timestamp = now.addingTimeInterval(-13 * 60 * 60)
        let pinned = ClipboardItem(
            timestamp: timestamp,
            isPinned: true,
            content: .text(TextItemContent(inlineText: "pinned"))
        )
        let bookmarked = ClipboardItem(
            timestamp: timestamp,
            isBookmarked: true,
            content: .text(TextItemContent(inlineText: "bookmarked"))
        )
        let persistence = RecordingClipboardHistoryPersistence()

        let retained = try ClipboardHistoryRetentionService().prunedInitialItems(
            from: [pinned, bookmarked],
            retentionPeriod: .twelveHours,
            persistence: persistence,
            now: now
        )

        XCTAssertEqual(Set(retained.map(\.id)), [pinned.id, bookmarked.id])
        XCTAssertTrue(persistence.savedHistorySnapshots.isEmpty)
    }
}

private final class RecordingClipboardHistoryPersistence: ClipboardHistoryPersisting, @unchecked Sendable {
    private(set) var savedHistorySnapshots: [[ClipboardItem]] = []

    func loadHistory() throws -> [ClipboardItem] { [] }

    func saveHistory(_ items: [ClipboardItem]) throws {
        savedHistorySnapshots.append(items)
    }
}
