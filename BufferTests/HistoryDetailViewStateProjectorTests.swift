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
        let state = projector.project(
            selectedItem: item,
            selectedItemsInVisualOrder: [item],
            selectedItemsInActionOrder: [item],
            searchText: "openai",
            previewState: previewState,
            selectedItemsTotalSizeBytes: 512,
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
        let state = projector.project(
            selectedItem: item,
            selectedItemsInVisualOrder: [item],
            selectedItemsInActionOrder: [item],
            searchText: "",
            previewState: HistoryPreviewState(),
            selectedItemsTotalSizeBytes: 2_048,
            actionResolver: HistoryActionResolver(),
            copiedAtFormatter: HistoryCopiedAtFormatter()
        )

        XCTAssertEqual(state.imageSelectionCount, 1)
        XCTAssertTrue(state.canSaveSelectedImage)
        XCTAssertTrue(state.canExtractSelectedImageText)
        XCTAssertFalse(state.canJumpToHistorySelection)
    }
}
