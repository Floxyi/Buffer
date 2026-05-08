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

    func testHandleWindowOpenSelectsFirstNonPinnedItemWhenConfigured() async {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        settings.setHistoryWindowOpenBehavior(.selectFirstNonPinnedItem)

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

    func testHandleWindowOpenRestoresLastListStateWhenConfigured() async {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(
            settingsManager: settings,
            storagePaths: TestStorageFactory.makePaths()
        )

        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")
        store.add(first)
        store.add(second)

        await eventually {
            store.items.count == 2
        }

        let viewModel = HistoryViewModel(
            store: store,
            settingsManager: settings,
            ocrService: FakeOCRService(result: "")
        )

        viewModel.selectSingle(first.id)
        viewModel.updateLastListScrollOffset(172)
        viewModel.handleWindowOpen(focusSearch: true, suppressQuickPasteUntilModifiersReleased: false)

        XCTAssertEqual(viewModel.selectedItem?.id, first.id)
        XCTAssertEqual(viewModel.openListScrollRequest, .init(mode: .restoreOffset(172)))
    }

    func testHandleWindowOpenCanSelectAnyFirstItemWhenConfigured() async {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        settings.setHistoryWindowOpenBehavior(.selectAnyFirstItem)

        let store = ClipboardStore(
            settingsManager: settings,
            storagePaths: TestStorageFactory.makePaths()
        )

        let older = ClipboardItem.text("older")
        let newer = ClipboardItem.text("newer")
        store.add(older)
        store.add(newer)

        await eventually {
            store.items.count == 2
        }

        let viewModel = HistoryViewModel(
            store: store,
            settingsManager: settings,
            ocrService: FakeOCRService(result: "")
        )

        viewModel.selectSingle(older.id)
        viewModel.updateLastListScrollOffset(240)
        viewModel.handleWindowOpen(focusSearch: true, suppressQuickPasteUntilModifiersReleased: false)

        XCTAssertEqual(viewModel.selectedItem?.id, newer.id)
        XCTAssertEqual(viewModel.openListScrollRequest, .init(mode: .scrollToTop))
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

    func testDeleteSelectedItemPrefersNextVisibleItem() async {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(
            settingsManager: settings,
            storagePaths: TestStorageFactory.makePaths()
        )

        let oldest = ClipboardItem.text("oldest")
        let middle = ClipboardItem.text("middle")
        let newest = ClipboardItem.text("newest")

        store.add(oldest)
        store.add(middle)
        store.add(newest)

        await eventually {
            store.items.count == 3
        }

        let viewModel = HistoryViewModel(
            store: store,
            settingsManager: settings,
            ocrService: FakeOCRService(result: "")
        )

        viewModel.selectSingle(middle.id)
        viewModel.deleteSelectedItem()

        await eventually {
            viewModel.selectedItem?.id == oldest.id
        }

        XCTAssertEqual(viewModel.selectedItem?.id, oldest.id)
    }
}
