import XCTest

@testable import Buffer

@MainActor
final class HistoryPreviewStateControllerTests: XCTestCase {
    func testLoadPreviewForInlineTextUsesPastedText() {
        let item = ClipboardItem.text("hello")

        let state = HistoryPreviewStateController().immediatePreview(
            for: item,
            cachedPreviewImage: nil
        )

        XCTAssertEqual(state.chunkedText.visibleText, "hello")
        XCTAssertTrue(state.chunkedText.reachedEOF)
        XCTAssertNil(state.previewImage)
    }

    func testBeginAndFinishExtractingToggleFlag() {
        let controller = HistoryPreviewStateController()
        let extracting = controller.beginExtracting(state: HistoryPreviewState())
        let finished = controller.finishExtracting(state: extracting)

        XCTAssertTrue(extracting.isExtractingText)
        XCTAssertFalse(finished.isExtractingText)
    }
}
