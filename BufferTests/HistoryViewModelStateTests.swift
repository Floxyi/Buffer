import XCTest
@testable import Buffer

@MainActor
final class HistoryViewModelStateTests: XCTestCase {
    func testJumpToHistoryClearsSearchAndEntersPendingState() async {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)
        let item = ClipboardItem.text("needle")
        store.add(item)
        await eventually { store.items.count == 1 }

        let viewModel = HistoryViewModel(
            store: store,
            settingsManager: settings,
            ocrService: FakeOCRService(result: "")
        )
        viewModel.searchText = "needle"

        viewModel.jumpToHistory(for: item)

        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertEqual(viewModel.activeJumpToHistoryRequest?.itemID, item.id)
    }

    func testPendingJumpToHistoryRetriesThenAbandonsAfterLimit() async {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)
        let item = ClipboardItem.text("jump")
        store.add(item)
        await eventually { store.items.count == 1 }

        let viewModel = HistoryViewModel(
            store: store,
            settingsManager: settings,
            ocrService: FakeOCRService(result: "")
        )

        viewModel.jumpToHistory(for: item)
        let first = try! XCTUnwrap(viewModel.activeJumpToHistoryRequest)
        viewModel.completeJumpToHistoryScroll(first, succeeded: false)
        let second = try! XCTUnwrap(viewModel.activeJumpToHistoryRequest)
        XCTAssertNotEqual(first.generation, second.generation)

        viewModel.completeJumpToHistoryScroll(second, succeeded: false)
        let third = try! XCTUnwrap(viewModel.activeJumpToHistoryRequest)
        XCTAssertNotEqual(second.generation, third.generation)

        viewModel.completeJumpToHistoryScroll(third, succeeded: false)
        XCTAssertNil(viewModel.activeJumpToHistoryRequest)
    }

    func testHandleQuickPasteModifierFlagsRequiresResetBeforeShowingNumbers() async {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)
        let viewModel = HistoryViewModel(
            store: store,
            settingsManager: settings,
            ocrService: FakeOCRService(result: "")
        )

        viewModel.prepareQuickPasteForWindowOpen(using: [.command], forceModifierReset: true)
        viewModel.handleQuickPasteModifierFlagsChange([.command])
        XCTAssertFalse(viewModel.showsQuickPasteNumbers)

        viewModel.handleQuickPasteModifierFlagsChange([])
        viewModel.handleQuickPasteModifierFlagsChange([.command])
        XCTAssertTrue(viewModel.showsQuickPasteNumbers)
    }

    func testLoadPreviewIfNeededLoadsInitialChunkForFileBackedText() async throws {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)
        let body = String(repeating: "x", count: ChunkedTextState.initialChars + 250)
        let filename = try XCTUnwrap(store.saveText(body))
        let item = ClipboardItem.largeText(preview: "preview", filename: filename)

        store.add(item)
        await eventually { store.items.count == 1 }

        let viewModel = HistoryViewModel(
            store: store,
            settingsManager: settings,
            ocrService: FakeOCRService(result: "")
        )

        await viewModel.loadPreviewIfNeeded()

        XCTAssertEqual(viewModel.chunkedText.visibleText.count, ChunkedTextState.initialChars)
        XCTAssertTrue(viewModel.chunkedText.hasMore)
    }

    func testExtractImageTextStoresRecognizedText() async throws {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)
        let filename = try XCTUnwrap(store.saveImage(makePNGData()))
        let item = ClipboardItem.image(filename: filename)
        store.add(item)
        await eventually { store.items.count == 1 }

        let viewModel = HistoryViewModel(
            store: store,
            settingsManager: settings,
            ocrService: FakeOCRService(result: "recognized")
        )

        await viewModel.loadPreviewIfNeeded()
        await viewModel.extractSelectedImageText()

        await eventually {
            store.items.first?.ocrText == "recognized"
        }
    }
}
