import AppKit
import XCTest

@testable import Buffer

@MainActor
final class HistoryDetailViewStateProjectorTests: XCTestCase {
    func testProjectsSingleLinkSelectionIntoActionsAndMetadata() {
        let projector = HistoryDetailViewStateProjector()
        let item = ClipboardItem.link(
            URL(string: "https://openai.com/research")!,
            originalText: "openai.com/research"
        )
        let previewState = HistoryPreviewState()
        let store = FakeClipboardStoreReading(itemSizes: [item.id: 512])

        let state = projector.project(
            selectedItem: item,
            selectedItemsInVisualOrder: [item],
            selectedItemsInActionOrder: [item],
            searchText: "openai",
            previewState: previewState,
            store: store,
            actionResolver: HistoryActionResolver(),
            copiedAtFormatter: HistoryCopiedAtFormatter()
        )

        XCTAssertEqual(state.selectionCount, 1)
        XCTAssertEqual(state.selectedItemSourceName, nil)
        XCTAssertEqual(state.linkSelectionCount, 1)
        XCTAssertEqual(state.selectedItemsTotalSizeText, "512 bytes")
        XCTAssertTrue(state.canJumpToHistorySelection)
        XCTAssertEqual(state.actions.map(\.action), [.copy, .openLink, .jumpToHistory, .togglePin, .delete])
    }

    func testProjectsImageSelectionIntoImageCapabilities() {
        let projector = HistoryDetailViewStateProjector()
        let item = ClipboardItem.image(filename: "preview.png")
        let store = FakeClipboardStoreReading(itemSizes: [item.id: 2_048])

        let state = projector.project(
            selectedItem: item,
            selectedItemsInVisualOrder: [item],
            selectedItemsInActionOrder: [item],
            searchText: "",
            previewState: HistoryPreviewState(),
            store: store,
            actionResolver: HistoryActionResolver(),
            copiedAtFormatter: HistoryCopiedAtFormatter()
        )

        XCTAssertEqual(state.imageSelectionCount, 1)
        XCTAssertTrue(state.canSaveSelectedImage)
        XCTAssertTrue(state.canExtractSelectedImageText)
        XCTAssertFalse(state.canJumpToHistorySelection)
    }
}

@MainActor
private final class FakeClipboardStoreReading: ClipboardStoreReading {
    let items: [ClipboardItem] = []
    private let itemSizes: [UUID: Int]

    init(itemSizes: [UUID: Int]) {
        self.itemSizes = itemSizes
    }

    func image(for item: ClipboardItem) -> NSImage? { nil }
    func thumbnail(for item: ClipboardItem, maxPixelSize: CGFloat) -> NSImage? { nil }
    func imageDimensions(for item: ClipboardItem) -> String? { nil }
    func fullText(for item: ClipboardItem) -> String? { nil }
    func textChunk(for item: ClipboardItem, charCount: Int) -> (text: String, totalBytes: Int, reachedEOF: Bool)? {
        nil
    }
    func itemSize(for item: ClipboardItem) -> Int? { itemSizes[item.id] }
    func searchableText(for item: ClipboardItem) -> String { "" }
    func matchesSearchQuery(_ normalizedQuery: String, for item: ClipboardItem) -> Bool { false }
}
