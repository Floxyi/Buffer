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
        settings.setHistoryWindowOpenBehavior(.keepLastSelection)

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

    func testJumpToFirstItemSelectsNewestVisibleItem() async {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(
            settingsManager: settings,
            storagePaths: TestStorageFactory.makePaths()
        )

        let oldest = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 1), textContent: "oldest")
        let middle = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 2), textContent: "middle")
        let newest = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 3), textContent: "newest")

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

        viewModel.selectSingle(oldest.id)
        viewModel.jumpToFirstItem()

        XCTAssertEqual(viewModel.selectedItem?.id, viewModel.filteredItems.first?.id)
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertTrue(viewModel.scrollTrigger)
    }

    func testJumpToLastItemSelectsOldestVisibleItem() async {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(
            settingsManager: settings,
            storagePaths: TestStorageFactory.makePaths()
        )

        let oldest = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 1), textContent: "oldest")
        let middle = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 2), textContent: "middle")
        let newest = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 3), textContent: "newest")

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

        viewModel.selectSingle(newest.id)
        viewModel.jumpToLastItem()

        XCTAssertEqual(viewModel.selectedItem?.id, viewModel.filteredItems.last?.id)
        XCTAssertEqual(viewModel.selectedIndex, viewModel.filteredItems.count - 1)
        XCTAssertTrue(viewModel.scrollTrigger)
    }

    func testQuickPasteUsesPinnedSectionByDefault() async {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        settings.setQuickPasteEntryCount(3)

        let store = ClipboardStore(
            settingsManager: settings,
            storagePaths: TestStorageFactory.makePaths()
        )

        let pinned = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 1), textContent: "pinned")
        let first = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 2), textContent: "first")
        let second = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 3), textContent: "second")

        store.add(pinned)
        store.add(first)
        store.add(second)

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

        XCTAssertEqual(viewModel.quickPasteBadgeNumberByItemID[pinned.id], 1)
        XCTAssertEqual(viewModel.quickPasteBadgeNumberByItemID[second.id], 2)
        XCTAssertEqual(viewModel.quickPasteBadgeNumberByItemID[first.id], 3)
        XCTAssertEqual(viewModel.performQuickPaste(at: 0)?.id, pinned.id)
    }

    func testQuickPasteCanStartAtNormalEntries() async {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        settings.setQuickPasteNumberingStart(.normalEntries)
        settings.setQuickPasteEntryCount(2)

        let store = ClipboardStore(
            settingsManager: settings,
            storagePaths: TestStorageFactory.makePaths()
        )

        let pinned = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 1), textContent: "pinned")
        let first = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 2), textContent: "first")
        let second = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 3), textContent: "second")

        store.add(pinned)
        store.add(first)
        store.add(second)

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

        XCTAssertNil(viewModel.quickPasteBadgeNumberByItemID[pinned.id])
        XCTAssertEqual(viewModel.quickPasteBadgeNumberByItemID[second.id], 1)
        XCTAssertEqual(viewModel.quickPasteBadgeNumberByItemID[first.id], 2)
        XCTAssertEqual(viewModel.performQuickPaste(at: 0)?.id, second.id)
        XCTAssertEqual(viewModel.performQuickPaste(at: 1)?.id, first.id)
        XCTAssertNil(viewModel.performQuickPaste(at: 2))
    }

    func testQuickPasteCanBeDisabled() async {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        settings.setQuickPasteEnabled(false)

        let store = ClipboardStore(
            settingsManager: settings,
            storagePaths: TestStorageFactory.makePaths()
        )

        let item = ClipboardItem.text("only")
        store.add(item)

        await eventually {
            store.items.count == 1
        }

        let viewModel = HistoryViewModel(
            store: store,
            settingsManager: settings,
            ocrService: FakeOCRService(result: "")
        )

        viewModel.handleQuickPasteModifierFlagsChange(.command)

        XCTAssertTrue(viewModel.quickPasteBadgeNumberByItemID.isEmpty)
        XCTAssertNil(viewModel.performQuickPaste(at: 0))
        XCTAssertFalse(viewModel.showsQuickPasteNumbers)
    }

    func testExtendSelectionToFirstItemSelectsRangeToNewestVisibleItem() async {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(
            settingsManager: settings,
            storagePaths: TestStorageFactory.makePaths()
        )

        let oldest = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 1), textContent: "oldest")
        let middle = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 2), textContent: "middle")
        let newest = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 3), textContent: "newest")

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
        viewModel.extendSelectionToFirstItem()

        XCTAssertEqual(viewModel.selectedID, viewModel.filteredItems.first?.id)
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertEqual(viewModel.selectedIDs, Set(viewModel.filteredItems.prefix(2).map(\.id)))
        XCTAssertTrue(viewModel.scrollTrigger)
    }

    func testExtendSelectionToLastItemSelectsRangeToOldestVisibleItem() async {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(
            settingsManager: settings,
            storagePaths: TestStorageFactory.makePaths()
        )

        let oldest = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 1), textContent: "oldest")
        let middle = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 2), textContent: "middle")
        let newest = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 3), textContent: "newest")

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
        viewModel.extendSelectionToLastItem()

        XCTAssertEqual(viewModel.selectedID, viewModel.filteredItems.last?.id)
        XCTAssertEqual(viewModel.selectedIndex, viewModel.filteredItems.count - 1)
        XCTAssertEqual(viewModel.selectedIDs, Set(viewModel.filteredItems.suffix(2).map(\.id)))
        XCTAssertTrue(viewModel.scrollTrigger)
    }
}
