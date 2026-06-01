import XCTest
@testable import Buffer

@MainActor
final class HistoryPreviewStateControllerTests: XCTestCase {
    func testLoadPreviewForInlineTextUsesPastedText() {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)
        let item = ClipboardItem.text("hello")
        let loader = HistoryPreviewLoader(store: store, ocrService: FakeOCRService(result: nil))

        let state = HistoryPreviewStateController().loadPreview(
            for: item,
            store: store,
            previewLoader: loader
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
