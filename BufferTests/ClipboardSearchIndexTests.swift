import XCTest
@testable import Buffer

final class ClipboardSearchIndexTests: XCTestCase {
    func testValueCachesLoadedTextUntilPruned() {
        var index = ClipboardSearchIndex()
        let itemID = UUID()
        var loadCount = 0

        let first = index.value(for: itemID) {
            loadCount += 1
            return "hello"
        }
        let second = index.value(for: itemID) {
            loadCount += 1
            return "changed"
        }

        XCTAssertEqual(first, "hello")
        XCTAssertEqual(second, "hello")
        XCTAssertEqual(loadCount, 1)
    }

    func testPruneRemovesValuesForMissingIDs() {
        var index = ClipboardSearchIndex()
        let retainedID = UUID()
        let removedID = UUID()

        _ = index.value(for: retainedID) { "keep" }
        _ = index.value(for: removedID) { "drop" }

        index.prune(validIDs: [retainedID])

        XCTAssertEqual(index.value(for: retainedID) { "new keep" }, "keep")
        XCTAssertEqual(index.value(for: removedID) { "reloaded" }, "reloaded")
    }
}
