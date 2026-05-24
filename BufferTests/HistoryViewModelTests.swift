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
        let colorItem = ClipboardItem.color(
            ClipboardColorValue(red: 1, green: 0, blue: 0, alpha: 1),
            originalText: "#ff0000"
        )
        let linkItem = ClipboardItem.link(
            URL(string: "https://openai.com/research")!,
            originalText: "openai.com/research"
        )
        let imageItem = ClipboardItem(
            type: .image,
            imageFilename: "image.png",
            ocrText: "ocr needle text"
        )

        store.add(inlineItem)
        store.add(fileBackedItem)
        store.add(colorItem)
        store.add(linkItem)
        store.add(imageItem)

        await eventually {
            store.items.count == 5
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

        viewModel.searchText = "#ff0000"
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [colorItem.id])

        viewModel.searchText = "openai.com/research"
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [linkItem.id])
    }

    func testColorClassificationCreatesStructuredColorItem() async {
        let item = await ClipboardCaptureSupport.classifyTextItem(
            "#ff0000",
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            XCTFail("Expected inline color item")
            return nil
        }

        XCTAssertEqual(item.kind, .color)
        XCTAssertEqual(item.colorPayload?.originalText, "#ff0000")
        XCTAssertEqual(item.textContent, nil)
    }

    func testColorClassificationRecognizesRGBAndHSL() async {
        let rgbItem = await ClipboardCaptureSupport.classifyTextItem(
            "rgba(255, 0, 128, 0.5)",
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            XCTFail("Expected inline color item")
            return nil
        }
        let hslItem = await ClipboardCaptureSupport.classifyTextItem(
            "hsl(330, 100%, 50%)",
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            XCTFail("Expected inline color item")
            return nil
        }

        XCTAssertEqual(rgbItem.kind, .color)
        XCTAssertEqual(rgbItem.colorPayload?.value, ClipboardColorValue(red: 1, green: 0, blue: 128.0 / 255.0, alpha: 0.5))
        XCTAssertEqual(hslItem.kind, .color)
        XCTAssertEqual(hslItem.colorPayload?.originalText, "hsl(330, 100%, 50%)")
    }

    func testColorClassificationRejectsNonColorHashText() async {
        let headingItem = await ClipboardCaptureSupport.classifyTextItem(
            "## Phase 1: Polish",
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            XCTFail("Expected inline plain text item")
            return nil
        }
        let malformedHexItem = await ClipboardCaptureSupport.classifyTextItem(
            "#12 nope",
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            XCTFail("Expected inline plain text item")
            return nil
        }
        let malformedRGBItem = await ClipboardCaptureSupport.classifyTextItem(
            "rgb(255, blue, 0)",
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            XCTFail("Expected inline plain text item")
            return nil
        }

        XCTAssertEqual(headingItem.kind, .text)
        XCTAssertEqual(headingItem.textContent, "## Phase 1: Polish")
        XCTAssertNil(headingItem.colorPayload)

        XCTAssertEqual(malformedHexItem.kind, .text)
        XCTAssertNil(malformedHexItem.colorPayload)

        XCTAssertEqual(malformedRGBItem.kind, .text)
        XCTAssertNil(malformedRGBItem.colorPayload)
    }

    func testLinkClassificationCreatesStructuredLinkItem() async {
        let httpsItem = await ClipboardCaptureSupport.classifyTextItem(
            "https://www.youtube.com/watch?v=123",
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            XCTFail("Expected inline link item")
            return nil
        }
        let schemeLessItem = await ClipboardCaptureSupport.classifyTextItem(
            "openai.com/research",
            sourceApp: nil,
            enableWebsitePreviews: true,
            websiteReachability: { _ in true }
        ) { _ in
            XCTFail("Expected inline link item")
            return nil
        }

        XCTAssertEqual(httpsItem.kind, .link)
        XCTAssertEqual(httpsItem.linkPayload?.websiteName, "Youtube")
        XCTAssertEqual(httpsItem.linkPayload?.originalText, "https://www.youtube.com/watch?v=123")

        XCTAssertEqual(schemeLessItem.kind, .link)
        XCTAssertEqual(schemeLessItem.linkPayload?.url.absoluteString, "https://openai.com/research")
    }

    func testLinkClassificationRejectsNonURLText() async {
        let plainTextItem = await ClipboardCaptureSupport.classifyTextItem(
            "openai research",
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            XCTFail("Expected inline plain text item")
            return nil
        }
        let markdownHeadingItem = await ClipboardCaptureSupport.classifyTextItem(
            "# Release Notes",
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            XCTFail("Expected inline plain text item")
            return nil
        }
        let nonWebSchemeItem = await ClipboardCaptureSupport.classifyTextItem(
            "file:///tmp/test.txt",
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            XCTFail("Expected inline plain text item")
            return nil
        }

        XCTAssertEqual(plainTextItem.kind, .text)
        XCTAssertNil(plainTextItem.linkPayload)

        XCTAssertEqual(markdownHeadingItem.kind, .text)
        XCTAssertNil(markdownHeadingItem.linkPayload)

        XCTAssertEqual(nonWebSchemeItem.kind, .text)
        XCTAssertNil(nonWebSchemeItem.linkPayload)
    }

    func testImplicitLinkClassificationRequiresReachableWebsite() async {
        let reachableItem = await ClipboardCaptureSupport.classifyTextItem(
            "youtube.com",
            sourceApp: nil,
            enableWebsitePreviews: true,
            websiteReachability: { _ in true }
        ) { _ in
            XCTFail("Expected inline link item")
            return nil
        }

        let unreachableItem = await ClipboardCaptureSupport.classifyTextItem(
            "bla.bla",
            sourceApp: nil,
            enableWebsitePreviews: true,
            websiteReachability: { _ in false }
        ) { _ in
            XCTFail("Expected inline plain text item")
            return nil
        }

        XCTAssertEqual(reachableItem.kind, .link)
        XCTAssertEqual(reachableItem.linkPayload?.url.absoluteString, "https://youtube.com")
        XCTAssertEqual(unreachableItem.kind, .text)
        XCTAssertNil(unreachableItem.linkPayload)
    }

    func testLocalOnlyModeRequiresExplicitHTTPSLinks() async {
        let httpsItem = await ClipboardCaptureSupport.classifyTextItem(
            "https://youtube.com/watch?v=123",
            sourceApp: nil,
            enableWebsitePreviews: false
        ) { _ in
            XCTFail("Expected inline link item")
            return nil
        }

        let httpItem = await ClipboardCaptureSupport.classifyTextItem(
            "http://youtube.com/watch?v=123",
            sourceApp: nil,
            enableWebsitePreviews: false
        ) { _ in
            XCTFail("Expected inline plain text item")
            return nil
        }

        let schemeLessItem = await ClipboardCaptureSupport.classifyTextItem(
            "youtube.com/watch?v=123",
            sourceApp: nil,
            enableWebsitePreviews: false
        ) { _ in
            XCTFail("Expected inline plain text item")
            return nil
        }

        XCTAssertEqual(httpsItem.kind, .link)
        XCTAssertEqual(httpItem.kind, .text)
        XCTAssertEqual(schemeLessItem.kind, .text)
    }

    func testTypeDrivenImageActionsExcludeColorItems() async {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(
            settingsManager: settings,
            storagePaths: TestStorageFactory.makePaths()
        )

        let colorItem = ClipboardItem.color(
            ClipboardColorValue(red: 0, green: 1, blue: 0, alpha: 1),
            originalText: "#00ff00"
        )
        store.add(colorItem)

        await eventually {
            store.items.count == 1
        }

        let viewModel = HistoryViewModel(
            store: store,
            settingsManager: settings,
            ocrService: FakeOCRService(result: "")
        )

        viewModel.selectSingle(colorItem.id)

        XCTAssertFalse(viewModel.canSaveSelectedImage)
        XCTAssertFalse(viewModel.canExtractSelectedImageText)
        XCTAssertEqual(viewModel.colorSelectionCount, 1)
    }

    func testTypeDrivenLinkActionsExposeOpenLink() {
        let linkItem = ClipboardItem.link(
            URL(string: "https://openai.com")!,
            originalText: "openai.com"
        )

        XCTAssertTrue(ClipboardItemTypeRegistry.canOpenLink(for: linkItem))
        XCTAssertFalse(ClipboardItemTypeRegistry.canSaveImage(for: linkItem))
        XCTAssertFalse(ClipboardItemTypeRegistry.canExtractImageText(for: linkItem))
    }

    func testDetailActionsMatchSingleLinkSelection() async {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(
            settingsManager: settings,
            storagePaths: TestStorageFactory.makePaths()
        )

        let item = ClipboardItem.link(
            URL(string: "https://openai.com/research")!,
            originalText: "openai.com/research"
        )
        store.add(item)

        await eventually {
            store.items.count == 1
        }

        let viewModel = HistoryViewModel(
            store: store,
            settingsManager: settings,
            ocrService: FakeOCRService(result: "")
        )
        viewModel.searchText = "openai"

        XCTAssertEqual(
            viewModel.detailActions.map(\.action),
            [.copy, .openLink, .jumpToHistory, .togglePin, .delete]
        )
    }

    func testContextMenuActionsMatchMultiSelection() async {
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
        viewModel.toggleSelection(second.id)

        XCTAssertEqual(
            viewModel.contextMenuActions(for: first.id).map(\.action),
            [.copy, .togglePin, .delete]
        )
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

    func testHandleWindowOpenKeepsPreviousSelectionWhenConfigured() async {
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
        viewModel.handleWindowOpen(focusSearch: true, suppressQuickPasteUntilModifiersReleased: false)
        viewModel.handleWindowOpen(focusSearch: true, suppressQuickPasteUntilModifiersReleased: false)

        XCTAssertEqual(viewModel.selectedItem?.id, first.id)
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

    func testClipboardListStructureRebuildsCacheWhenWeekBoundaryChanges() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let mondayReferenceDate = DateComponents(
            calendar: calendar,
            year: 2026,
            month: 5,
            day: 18,
            hour: 9
        ).date!
        let sundayReferenceDate = DateComponents(
            calendar: calendar,
            year: 2026,
            month: 5,
            day: 17,
            hour: 9
        ).date!
        let lastTuesdayItemDate = DateComponents(
            calendar: calendar,
            year: 2026,
            month: 5,
            day: 12,
            hour: 12
        ).date!

        let items = [
            ClipboardItem(
                type: .text,
                timestamp: lastTuesdayItemDate,
                textContent: "last week item"
            )
        ]

        let staleCache = ClipboardListStructure.makeDisplayCache(
            from: items,
            referenceDate: sundayReferenceDate,
            calendar: calendar
        )

        XCTAssertFalse(staleCache.matches(items: items, referenceDate: mondayReferenceDate, calendar: calendar))

        let refreshedRows = ClipboardListStructure.displayRows(
            from: items,
            referenceDate: mondayReferenceDate,
            calendar: calendar
        )
        let sectionTitle = refreshedRows.compactMap { row -> String? in
            guard case .header(let title, _) = row.kind else { return nil }
            return title
        }.first

        XCTAssertEqual(sectionTitle, "LAST WEEK")
    }

    func testCopiedAtTextUsesWeekdayAndFixedDetailFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        let timestamp = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 12,
            hour: 12,
            minute: 36
        ).date!

        XCTAssertEqual(
            HistoryViewModel.copiedAtText(for: timestamp),
            "Tue, 12. May 2026, at 12:36"
        )
    }

    func testClearSearchAfterClosingClearsTextByDefault() {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
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
        viewModel.clearSearchAfterClosingIfNeeded()

        XCTAssertEqual(viewModel.searchText, "")
    }

    func testClearSearchAfterClosingKeepsTextWhenEnabled() {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        settings.setKeepSearchTextAfterClosing(true)

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
        viewModel.clearSearchAfterClosingIfNeeded()

        XCTAssertEqual(viewModel.searchText, "needle")
    }

    func testCommandToggleSelectionTracksActionOrderAndRemovesDeselectedItems() async {
        let viewModel = await makeSelectionViewModel()
        let newest = viewModel.filteredItems[0]
        let middle = viewModel.filteredItems[1]
        let oldest = viewModel.filteredItems[2]

        viewModel.selectSingle(middle.id)
        viewModel.toggleSelection(oldest.id)
        viewModel.toggleSelection(newest.id)

        XCTAssertEqual(viewModel.selectedItemsInActionOrder.map(\.id), [middle.id, oldest.id, newest.id])
        XCTAssertEqual(viewModel.selectedItemsInVisualOrder.map(\.id), [newest.id, middle.id, oldest.id])

        viewModel.toggleSelection(oldest.id)

        XCTAssertEqual(viewModel.selectedItemsInActionOrder.map(\.id), [middle.id, newest.id])
        XCTAssertEqual(viewModel.selectedIDs, Set([middle.id, newest.id]))
    }

    func testShiftRangeSelectionAppendsNewItemsInGestureDirection() async {
        let viewModel = await makeSelectionViewModel()
        let newest = viewModel.filteredItems[0]
        let middle = viewModel.filteredItems[1]
        let oldest = viewModel.filteredItems[2]

        viewModel.selectSingle(middle.id)
        viewModel.extendSelectionTo(oldest.id)
        XCTAssertEqual(viewModel.selectedItemsInActionOrder.map(\.id), [middle.id, oldest.id])

        viewModel.selectSingle(middle.id)
        viewModel.extendSelectionTo(newest.id)
        XCTAssertEqual(viewModel.selectedItemsInActionOrder.map(\.id), [middle.id, newest.id])
    }

    func testKeyboardExtendAppendsNewEdgeItemInExtensionDirection() async {
        let viewModel = await makeSelectionViewModel()
        let newest = viewModel.filteredItems[0]
        let middle = viewModel.filteredItems[1]
        let oldest = viewModel.filteredItems[2]

        viewModel.selectSingle(middle.id)
        viewModel.extendSelectionUp()
        XCTAssertEqual(viewModel.selectedItemsInActionOrder.map(\.id), [middle.id, newest.id])

        viewModel.selectSingle(middle.id)
        viewModel.extendSelectionDown()
        XCTAssertEqual(viewModel.selectedItemsInActionOrder.map(\.id), [middle.id, oldest.id])
    }

    func testContextMenuTargetingUsesSelectionScopeForSelectedRowsAndSingleScopeOtherwise() async {
        let viewModel = await makeSelectionViewModel()
        let newest = viewModel.filteredItems[0]
        let middle = viewModel.filteredItems[1]
        let oldest = viewModel.filteredItems[2]

        viewModel.selectSingle(middle.id)
        viewModel.toggleSelection(newest.id)

        XCTAssertEqual(
            viewModel.contextMenuTargetItems(for: newest.id).map(\.id),
            [middle.id, newest.id]
        )
        XCTAssertEqual(
            viewModel.contextMenuTargetItems(for: oldest.id).map(\.id),
            [oldest.id]
        )
    }

    private func makeSelectionViewModel() async -> HistoryViewModel {
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

        return HistoryViewModel(
            store: store,
            settingsManager: settings,
            ocrService: FakeOCRService(result: "")
        )
    }
}
