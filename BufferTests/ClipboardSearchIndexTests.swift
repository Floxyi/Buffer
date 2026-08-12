import XCTest

@testable import Buffer

final class ClipboardSearchIndexTests: XCTestCase {
    func testRebuildRetainsCachedValueForUnchangedContentHash() {
        var index = ClipboardSearchIndex()
        let item = ClipboardItem.text("hello")
        var loadCount = 0

        index.rebuild(using: [item]) { currentItem in
            loadCount += 1
            return currentItem.textContent ?? ""
        }
        index.rebuild(using: [item]) { currentItem in
            loadCount += 1
            return (currentItem.textContent ?? "") + " changed"
        }

        XCTAssertEqual(index.searchableText(for: item.id), "hello")
        XCTAssertEqual(loadCount, 1)
    }

    func testRebuildRefreshesEntryWhenContentHashChanges() {
        var index = ClipboardSearchIndex()
        let item = ClipboardItem(type: .image, imageFilename: "sample.png", ocrText: nil)
        let updatedItem = item.updatingOCRText("detected text")

        index.rebuild(using: [item]) { _ in "" }
        index.rebuild(using: [updatedItem]) { currentItem in
            currentItem.ocrText ?? ""
        }

        XCTAssertEqual(index.searchableText(for: item.id), "detected text")
    }

    func testMatchesUsesNormalizedCaseInsensitiveText() {
        var index = ClipboardSearchIndex()
        let item = ClipboardItem.text("CafE")
        index.rebuild(using: [item]) { $0.textContent ?? "" }

        XCTAssertTrue(index.matches(ClipboardSearchIndex.normalize("cafe"), for: item.id))
    }

    func testFilteringCachedEntriesStaysWithinInteractiveBudget() {
        assertCachedFilterDuration(itemCount: 1_000, isLessThan: 0.05)
        assertCachedFilterDuration(itemCount: 5_000, isLessThan: 0.05)
    }

    func testPerformanceDiagnosticsRetainOnlyRecentSamples() {
        BufferPerformanceDiagnostics.reset()

        for _ in 0..<(BufferPerformanceDiagnostics.sampleLimit + 50) {
            let token = BufferPerformanceDiagnostics.begin(.historyFilter)
            BufferPerformanceDiagnostics.end(token)
        }

        XCTAssertEqual(
            BufferPerformanceDiagnostics.samples(for: .historyFilter).count,
            BufferPerformanceDiagnostics.sampleLimit
        )
    }

    private func assertCachedFilterDuration(itemCount: Int, isLessThan limit: TimeInterval) {
        var index = ClipboardSearchIndex()
        let items = (0..<itemCount).map { number in
            ClipboardItem.text("entry \(number) common searchable content")
        }
        index.rebuild(using: items) { $0.textContent ?? "" }
        let query = ClipboardSearchIndex.normalize("entry 499")

        let start = CFAbsoluteTimeGetCurrent()
        let matches = items.filter { index.matches(query, for: $0.id) }
        let duration = CFAbsoluteTimeGetCurrent() - start

        XCTAssertFalse(matches.isEmpty)
        XCTAssertLessThan(
            duration,
            limit,
            "Filtering \(itemCount) cached entries took \(duration)s"
        )
    }
}
