import XCTest
@testable import Buffer

@MainActor
final class HistoryViewModelSearchAndActionsTests: XCTestCase {
    func testSearchMatchesInlineFileBackedAndOCRContent() async {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)

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

        await populateStore(store, with: [inlineItem, fileBackedItem, colorItem, linkItem, imageItem])

        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)

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

    func testTypeDrivenImageActionsExcludeColorItems() async {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let colorItem = ClipboardItem.color(
            ClipboardColorValue(red: 0, green: 1, blue: 0, alpha: 1),
            originalText: "#00ff00"
        )
        await populateStore(store, with: [colorItem])

        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)
        viewModel.selectSingle(colorItem.id)

        XCTAssertFalse(viewModel.detailViewState.canSaveSelectedImage)
        XCTAssertFalse(viewModel.detailViewState.canExtractSelectedImageText)
        XCTAssertEqual(viewModel.detailViewState.colorSelectionCount, 1)
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
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let item = ClipboardItem.link(
            URL(string: "https://openai.com/research")!,
            originalText: "openai.com/research"
        )
        await populateStore(store, with: [item])

        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)
        viewModel.searchText = "openai"

        XCTAssertEqual(
            viewModel.detailViewState.actions.map(\.action),
            [.copy, .openLink, .jumpToHistory, .togglePin, .delete]
        )
    }

    func testContextMenuActionsMatchMultiSelection() async {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")
        await populateStore(store, with: [first, second])

        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)
        viewModel.selectSingle(first.id)
        viewModel.toggleSelection(second.id)

        XCTAssertEqual(
            viewModel.contextMenuActions(for: first.id).map(\.action),
            [.copy, .togglePin, .delete]
        )
    }

    func testClearSearchAfterCommittedActionKeepsSearchWhenPreferenceEnabled() {
        let settings = makeHistoryTestSettings()
        settings.setSearchBehavior(
            SearchBehaviorSettings(
                keepSearchTextAfterPaste: true,
                keepSearchTextAfterClosing: settings.keepSearchTextAfterClosing,
                confirmDeleteWithKeyboardShortcut: settings.confirmDeleteWithKeyboardShortcut
            )
        )
        let store = makeHistoryTestStore(settings: settings)
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)

        viewModel.searchText = "needle"
        viewModel.clearSearchAfterCommittedAction()

        XCTAssertEqual(viewModel.searchText, "needle")
    }

    func testDeleteSelectedItemPrefersNextVisibleItem() async {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)

        let oldest = ClipboardItem.text("oldest")
        let middle = ClipboardItem.text("middle")
        let newest = ClipboardItem.text("newest")
        await populateStore(store, with: [oldest, middle, newest])

        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)
        viewModel.selectSingle(middle.id)
        viewModel.deleteSelectedItem()

        await eventually {
            viewModel.selectedItem?.id == oldest.id
        }

        XCTAssertEqual(viewModel.selectedItem?.id, oldest.id)
    }

    func testClearSearchAfterClosingClearsTextByDefault() {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)

        viewModel.searchText = "needle"
        viewModel.clearSearchAfterClosingIfNeeded()

        XCTAssertEqual(viewModel.searchText, "")
    }

    func testClearSearchAfterClosingKeepsTextWhenEnabled() {
        let settings = makeHistoryTestSettings()
        settings.setSearchBehavior(
            SearchBehaviorSettings(
                keepSearchTextAfterPaste: settings.keepSearchTextAfterPaste,
                keepSearchTextAfterClosing: true,
                confirmDeleteWithKeyboardShortcut: settings.confirmDeleteWithKeyboardShortcut
            )
        )
        let store = makeHistoryTestStore(settings: settings)
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)

        viewModel.searchText = "needle"
        viewModel.clearSearchAfterClosingIfNeeded()

        XCTAssertEqual(viewModel.searchText, "needle")
    }
}
