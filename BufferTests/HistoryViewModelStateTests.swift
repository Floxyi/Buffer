import XCTest

@testable import Buffer

@MainActor
final class HistoryViewModelStateTests: XCTestCase {
    func testJumpToHistoryClearsSearchAndEntersPendingState() async throws {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)
        let item = ClipboardItem.text("needle")
        try await store.add(item)
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

    func testPendingJumpToHistoryRetriesThenAbandonsAfterLimit() async throws {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)
        let item = ClipboardItem.text("jump")
        try await store.add(item)
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

        try await store.add(item)
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

    func testSupersededFileBackedDetailCannotPublishForOldSelection() async throws {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)
        let firstFilename = try XCTUnwrap(store.saveText(String(repeating: "first-", count: 2_000)))
        let secondFilename = try XCTUnwrap(store.saveText(String(repeating: "second-", count: 2_000)))
        let firstItem = ClipboardItem.largeText(preview: "first", filename: firstFilename)
        let secondItem = ClipboardItem.largeText(preview: "second", filename: secondFilename)
        try await store.add(firstItem)
        try await store.add(secondItem)
        await eventually { store.items.count == 2 }

        let viewModel = HistoryViewModel(
            store: store,
            settingsManager: settings,
            ocrService: FakeOCRService(result: "")
        )

        viewModel.selectSingle(firstItem.id)
        viewModel.selectSingle(secondItem.id)
        await viewModel.loadPreviewIfNeeded()

        XCTAssertEqual(viewModel.selectedID, secondItem.id)
        XCTAssertTrue(viewModel.chunkedText.visibleText.hasPrefix("second-"))
        XCTAssertFalse(viewModel.chunkedText.visibleText.hasPrefix("first-"))
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
        try await store.add(item)
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

    func testSupersededOCRRequestCannotOverwriteNewerResult() async throws {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)
        let firstItem = ClipboardItem.image(filename: try XCTUnwrap(store.saveImage(makePNGData())))
        let secondItem = ClipboardItem.image(filename: try XCTUnwrap(store.saveImage(makePNGData())))
        try await store.add(firstItem)
        try await store.add(secondItem)
        await eventually { store.items.count == 2 }

        let ocrService = ControlledOCRService()
        let viewModel = HistoryViewModel(
            store: store,
            settingsManager: settings,
            ocrService: ocrService
        )
        viewModel.selectSingle(firstItem.id)
        let firstTask = Task {
            await viewModel.extractImageText(for: firstItem)
        }
        await eventually { ocrService.pendingRequestCount == 1 }

        viewModel.selectSingle(secondItem.id)
        let secondTask = Task {
            await viewModel.extractImageText(for: secondItem)
        }
        await eventually { ocrService.pendingRequestCount == 2 }
        ocrService.resumeRequest(at: 1, returning: "newer")
        await secondTask.value
        ocrService.resumeRequest(at: 0, returning: "stale")
        await firstTask.value

        await eventually {
            store.items.first(where: { $0.id == secondItem.id })?.ocrText == "newer"
        }
        XCTAssertNil(store.items.first(where: { $0.id == firstItem.id })?.ocrText)
    }
}

@MainActor
private final class ControlledOCRService: OCRServicing {
    private var continuations: [CheckedContinuation<String?, Never>?] = []

    var pendingRequestCount: Int {
        continuations.count
    }

    func recognizeText(from image: NSImage) async -> String? {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeRequest(at index: Int, returning result: String?) {
        continuations[index]?.resume(returning: result)
        continuations[index] = nil
    }
}
