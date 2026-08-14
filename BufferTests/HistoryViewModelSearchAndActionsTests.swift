import XCTest

@testable import Buffer

@MainActor
final class HistoryViewModelSearchAndActionsTests: XCTestCase {
    func testSearchPublishesEachRapidQueryChangeSynchronously() async {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let alpha = ClipboardItem.text("alpha needle")
        let beta = ClipboardItem.text("beta haystack")
        await populateStore(store, with: [alpha, beta])
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)

        let expectations: [(query: String, itemIDs: Set<UUID>)] = [
            ("a", [alpha.id, beta.id]),
            ("al", [alpha.id]),
            ("alhpa", [alpha.id]),
            ("alpha n", [alpha.id]),
            ("alpha needle", [alpha.id]),
            ("beta", [beta.id]),
        ]

        var previousRevision = viewModel.filteredItemsRevision
        for expectation in expectations {
            viewModel.searchText = expectation.query

            XCTAssertEqual(Set(viewModel.filteredItems.map(\.id)), expectation.itemIDs)
            XCTAssertEqual(Set(viewModel.searchResultsByItemID.keys), expectation.itemIDs)
            XCTAssertGreaterThan(viewModel.filteredItemsRevision, previousRevision)
            previousRevision = viewModel.filteredItemsRevision
        }
    }

    func testRapidSearchAlwaysProjectsRowsFromLatestQuerySnapshot() async {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let alpha = ClipboardItem.text("alpha needle")
        let beta = ClipboardItem.text("beta haystack")
        await populateStore(store, with: [alpha, beta])
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)
        let staleCache = ClipboardListStructure.makeDisplayCache(
            from: viewModel.filteredItems,
            sourceSnapshotID: viewModel.filteredItemsSnapshotID
        )
        let projector = ClipboardListDisplayStateProjector()

        let expectations: [(query: String, visibleIDs: [UUID])] = [
            ("alpha", [alpha.id]),
            ("beta", [beta.id]),
            ("needle", [alpha.id]),
        ]

        for expectation in expectations {
            viewModel.searchText = expectation.query

            let state = projector.project(
                items: viewModel.filteredItems,
                itemsSnapshotID: viewModel.filteredItemsSnapshotID,
                cache: staleCache,
                viewportHeight: 200
            )

            XCTAssertEqual(state.layoutIndex.entries.map(\.id), expectation.visibleIDs)
        }
    }

    func testActiveSearchRefreshesWhenDelayedIndexBecomesReady() async throws {
        let indexer = SuspendedClipboardSearchIndexer()
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings, searchIndexer: indexer)
        let matchingItem = ClipboardItem.text("delayed needle")
        let otherItem = ClipboardItem.text("unrelated")
        try await store.add(matchingItem)
        try await store.add(otherItem)
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)

        viewModel.searchText = "needle"
        XCTAssertEqual(viewModel.searchText, "needle")
        XCTAssertFalse(store.isSearchIndexReady)

        await indexer.resume()
        await store.waitForSearchIndex()

        await eventually {
            viewModel.filteredItems.map(\.id) == [matchingItem.id]
        }
        XCTAssertEqual(viewModel.searchText, "needle")
        XCTAssertEqual(Set(viewModel.searchResultsByItemID.keys), [matchingItem.id])
    }

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
        let emailItem = ClipboardItem.email(
            ClipboardEmailValue.parse("person@example.com")!
        )
        let imageItem = ClipboardItem(
            type: .image,
            imageFilename: "image.png",
            ocrText: "ocr needle text"
        )

        await populateStore(
            store,
            with: [inlineItem, fileBackedItem, colorItem, linkItem, emailItem, imageItem]
        )

        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)

        viewModel.searchText = "file-backed"
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [fileBackedItem.id])

        viewModel.searchText = "ocr needle"
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [imageItem.id])

        viewModel.searchText = "orc needel"
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [imageItem.id])
        XCTAssertEqual(
            viewModel.searchResultsByItemID[imageItem.id]?.matches.first {
                $0.field == .ocr
            }?.classification,
            .fuzzy
        )

        viewModel.searchText = "inline needle"
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [inlineItem.id])

        viewModel.searchText = "#ff0000"
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [colorItem.id])

        viewModel.searchText = "openai.com/research"
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [linkItem.id])

        viewModel.searchText = "person@example.com"
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [emailItem.id])
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
        XCTAssertNotNil(
            store.searchIndexSnapshot.results(
                for: [item.id],
                query: ClipboardQuery(text: "openai")
            )[item.id]
        )

        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)
        viewModel.searchText = "openai"

        XCTAssertEqual(viewModel.filteredItems.map(\.id), [item.id])
        XCTAssertEqual(viewModel.selectedID, item.id)
        XCTAssertEqual(viewModel.detailViewState.selectionCount, 1)
        XCTAssertEqual(
            viewModel.detailViewState.actions.map(\.action),
            [.copy, .openLink, .jumpToHistory, .toggleBookmark, .togglePin, .delete]
        )
    }

    func testFilterOnlyQueryOffersJumpAndJumpRestoresFullHistory() async {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let ordinary = ClipboardItem.text("ordinary")
        let bookmarked = ClipboardItem(
            isBookmarked: true,
            bookmarkedAt: Date(),
            content: .text(TextItemContent(inlineText: "bookmarked"))
        )
        await populateStore(store, with: [ordinary, bookmarked])
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)

        viewModel.setFilters(ClipboardFilters(requiresBookmark: true))

        XCTAssertEqual(viewModel.filteredItems.map(\.id), [bookmarked.id])
        XCTAssertFalse(viewModel.isShowingFullHistory)
        XCTAssertTrue(viewModel.detailViewState.canJumpToHistorySelection)
        XCTAssertTrue(
            viewModel.contextMenuActions(for: bookmarked.id).contains {
                $0.action == .jumpToHistory
            }
        )

        viewModel.jumpToHistory(for: bookmarked)

        XCTAssertTrue(viewModel.activeQuery.isEmpty)
        XCTAssertEqual(Set(viewModel.filteredItems.map(\.id)), [ordinary.id, bookmarked.id])
        XCTAssertEqual(viewModel.selectedID, bookmarked.id)
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
            [.copy, .toggleBookmark, .togglePin, .delete]
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

    func testPrimaryPasteCapturesFuzzyFilteredSelectionWithoutClearingSearchBeforeCommit() async {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        await populateStore(
            store,
            with: [
                ClipboardItem.text("matching oldest"),
                ClipboardItem.text("matching middle"),
                ClipboardItem.text("matching newest"),
            ]
        )
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)
        viewModel.searchText = "macthing"
        let selectedItem = viewModel.filteredItems[1]
        viewModel.selectSingle(selectedItem.id)
        var pastedItem: ClipboardItem?
        let actionHandler = makeActionHandler(
            viewModel: viewModel,
            store: store,
            settings: settings,
            onPaste: { pastedItem = $0 }
        )

        actionHandler.performPrimaryPasteAction()

        XCTAssertEqual(pastedItem?.id, selectedItem.id)
        XCTAssertEqual(viewModel.searchText, "macthing")
    }

    func testPrimaryPasteCapturesFilteredMultiSelectionInActionOrderWithoutClearingSearch() async {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        await populateStore(
            store,
            with: [
                ClipboardItem.text("matching oldest"),
                ClipboardItem.text("matching middle"),
                ClipboardItem.text("matching newest"),
            ]
        )
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)
        viewModel.searchText = "matching"
        let firstSelectedItem = viewModel.filteredItems[1]
        let secondSelectedItem = viewModel.filteredItems[2]
        viewModel.selectSingle(firstSelectedItem.id)
        viewModel.toggleSelection(secondSelectedItem.id)
        var pastedItems: [ClipboardItem] = []
        let actionHandler = makeActionHandler(
            viewModel: viewModel,
            store: store,
            settings: settings,
            onPasteMultiple: { pastedItems = $0 }
        )

        actionHandler.performPrimaryPasteAction()

        XCTAssertEqual(pastedItems.map(\.id), [firstSelectedItem.id, secondSelectedItem.id])
        XCTAssertEqual(viewModel.searchText, "matching")
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
        viewModel.deleteSelectedItems()

        await eventually {
            viewModel.selectedItem?.id == oldest.id
        }

        XCTAssertEqual(viewModel.selectedItem?.id, oldest.id)
    }

    func testDeleteRequestKeepsOriginalMultiSelectionAfterSelectionChanges() async throws {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let oldest = ClipboardItem.text("oldest")
        let middle = ClipboardItem.text("middle")
        let newest = ClipboardItem.text("newest")
        await populateStore(store, with: [oldest, middle, newest])
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)

        viewModel.selectSingle(middle.id)
        viewModel.toggleSelection(oldest.id)
        let request = try XCTUnwrap(viewModel.makeDeleteSelectionRequest())
        viewModel.selectSingle(newest.id)

        viewModel.delete(request)

        await eventually {
            Set(store.items.map(\.id)) == [newest.id]
        }
        XCTAssertEqual(Set(request.items.map(\.id)), [middle.id, oldest.id])
        XCTAssertEqual(store.items.map(\.id), [newest.id])
    }

    func testMutationKeepsOriginalMultiSelectionAfterSelectionChanges() async {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let oldest = ClipboardItem.text("oldest")
        let middle = ClipboardItem.text("middle")
        let newest = ClipboardItem.text("newest")
        await populateStore(store, with: [oldest, middle, newest])
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)

        viewModel.selectSingle(middle.id)
        viewModel.toggleSelection(oldest.id)
        let mutationTargets = viewModel.selectedItemsInActionOrder

        viewModel.togglePin(for: mutationTargets)
        viewModel.selectSingle(newest.id)

        await eventually {
            let itemByID = Dictionary(uniqueKeysWithValues: store.items.map { ($0.id, $0) })
            return itemByID[middle.id]?.isPinned == true
                && itemByID[oldest.id]?.isPinned == true
                && itemByID[newest.id]?.isPinned == false
        }
        XCTAssertEqual(Set(mutationTargets.map(\.id)), [middle.id, oldest.id])
        XCTAssertEqual(viewModel.selectedID, newest.id)
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

private actor SuspendedClipboardSearchIndexer: ClipboardSearchIndexing {
    private let indexer = ClipboardSearchIndexer()
    private var isSuspended = true
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func makeIndex(
        for items: [ClipboardItem],
        assetAccess: any ClipboardAssetAccessing
    ) async -> ClipboardSearchIndex {
        if isSuspended {
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }
        return await indexer.makeIndex(for: items, assetAccess: assetAccess)
    }

    func resume() {
        isSuspended = false
        let pendingContinuations = continuations
        continuations.removeAll()
        for continuation in pendingContinuations {
            continuation.resume()
        }
    }
}

@MainActor
private func makeActionHandler(
    viewModel: HistoryViewModel,
    store: ClipboardStore,
    settings: SettingsManager,
    onPaste: @escaping (ClipboardItem) -> Void = { _ in },
    onPasteMultiple: @escaping ([ClipboardItem]) -> Void = { _ in }
) -> HistoryActionHandler {
    HistoryActionHandler(
        viewModel: viewModel,
        contentReader: store,
        assetProvider: ClipboardItemAssetProvider(store: store, settings: settings),
        onCopy: { _ in true },
        onPaste: { items in
            if items.count == 1, let item = items.first {
                onPaste(item)
            } else {
                onPasteMultiple(items)
            }
        },
        onDismiss: {},
        presentingWindow: { nil }
    )
}
