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

    func testProjectsEmailSelectionIntoDedicatedCountAndPreview() throws {
        let projector = HistoryDetailViewStateProjector()
        let item = ClipboardItem.email(
            try XCTUnwrap(ClipboardEmailValue.parse("person@example.com"))
        )
        let state = projector.project(
            selectedItem: item,
            selectedItemsInVisualOrder: [item],
            selectedItemsInActionOrder: [item],
            searchText: "person",
            previewState: HistoryPreviewState(),
            selectedItemsTotalSizeBytes: 18,
            actionResolver: HistoryActionResolver(),
            copiedAtFormatter: HistoryCopiedAtFormatter()
        )

        XCTAssertEqual(state.emailSelectionCount, 1)
        XCTAssertEqual(state.linkSelectionCount, 0)
        XCTAssertEqual(state.firstTextPreview, "person@example.com")
        XCTAssertEqual(state.actions.map(\.action), [.copy, .composeEmail, .jumpToHistory, .togglePin, .delete])
    }

    func testDetailScrollResetIDChangesOnlyWithSelectionIdentity() {
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")
        let initialState = HistoryDetailViewState(
            selectionCount: 1,
            selectedItem: first,
            selectedItems: [first]
        )
        let initialResetID = HistoryDetailScrollResetID(detailState: initialState)

        var previewUpdatedState = initialState
        previewUpdatedState.previewImage = NSImage(size: NSSize(width: 10, height: 10))

        XCTAssertEqual(
            HistoryDetailScrollResetID(detailState: previewUpdatedState),
            initialResetID
        )

        let nextItemState = HistoryDetailViewState(
            selectionCount: 1,
            selectedItem: second,
            selectedItems: [second]
        )
        XCTAssertNotEqual(
            HistoryDetailScrollResetID(detailState: nextItemState),
            initialResetID
        )

        let multiSelectionState = HistoryDetailViewState(
            selectionCount: 2,
            selectedItem: second,
            selectedItems: [first, second]
        )
        XCTAssertNotEqual(
            HistoryDetailScrollResetID(detailState: multiSelectionState),
            HistoryDetailScrollResetID(detailState: nextItemState)
        )
    }
}
