import XCTest
@testable import Buffer

@MainActor
final class HistoryViewModelTests: XCTestCase {
    func testSearchMatchesInlineFileBackedAndOCRContent() async {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)

        let inlineItem = ClipboardItem.text("inline needle")
        let largeTextFilename = store.saveText("file-backed needle body")!
        let fileBackedItem = ClipboardItem.largeText(preview: "preview", filename: largeTextFilename)
        let imageItem = ClipboardItem(
            type: .image,
            imageFilename: "image.png",
            ocrText: "ocr needle text"
        )

        store.add(inlineItem)
        store.add(fileBackedItem)
        store.add(imageItem)

        await eventually {
            store.items.count == 3
        }

        let viewModel = HistoryViewModel(
            store: store,
            settingsManager: settings,
            ocrService: FakeOCRService(result: "")
        )

        viewModel.searchText = "file-backed"
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [fileBackedItem.id])

        viewModel.searchText = "ocr needle"
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [imageItem.id])

        viewModel.searchText = "inline needle"
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [inlineItem.id])
    }

    func testHandleWindowOpenSelectsFirstNonPinnedItemWhenPreferenceEnabled() async {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        settings.setPreferInitialSelectionFromFirstNonPinnedItem(true)

        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)

        let olderUnpinned = ClipboardItem.text("older unpinned")
        let newerUnpinned = ClipboardItem.text("newer unpinned")
        let pinned = ClipboardItem.text("pinned")

        store.add(olderUnpinned)
        store.add(newerUnpinned)
        store.add(pinned)

        await eventually {
            store.items.count == 3
        }

        store.togglePin(for: pinned)

        await eventually {
            store.items.first(where: { $0.id == pinned.id })?.isPinned == true
        }

        let viewModel = HistoryViewModel(
            store: store,
            settingsManager: settings,
            ocrService: FakeOCRService(result: "")
        )

        viewModel.handleWindowOpen(
            focusSearch: true,
            suppressQuickPasteUntilModifiersReleased: false
        )

        XCTAssertEqual(viewModel.selectedItem?.id, newerUnpinned.id)
    }

    func testClearSearchAfterCommittedActionKeepsSearchWhenPreferenceEnabled() {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        settings.setKeepSearchTextAfterPaste(true)

        let store = ClipboardStore(
            settingsManager: settings,
            storagePaths: TestStorageFactory.makePaths()
        )
        let viewModel = HistoryViewModel(
            store: store,
            settingsManager: settings,
            ocrService: FakeOCRService(result: "")
        )

        viewModel.searchText = "needle"
        viewModel.clearSearchAfterCommittedAction()

        XCTAssertEqual(viewModel.searchText, "needle")
    }
}
