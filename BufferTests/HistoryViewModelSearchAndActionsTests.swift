import XCTest

@testable import Buffer

@MainActor
final class HistoryViewModelSearchAndActionsTests: XCTestCase {
    func testRapidSearchPublishesOnlyLatestQuery() async {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let alpha = ClipboardItem.text("alpha needle")
        let beta = ClipboardItem.text("beta haystack")
        await populateStore(store, with: [alpha, beta])
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)

        let previousRevision = viewModel.filteredItemsRevision
        for query in ["a", "al", "alhpa", "alpha n", "alpha needle", "beta"] {
            viewModel.searchText = query
        }

        await waitForHistorySearch(viewModel)

        XCTAssertEqual(viewModel.searchText, "beta")
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [beta.id])
        XCTAssertEqual(Set(viewModel.searchResultsByItemID.keys), [beta.id])
        XCTAssertGreaterThan(viewModel.filteredItemsRevision, previousRevision)
    }

    func testRapidSearchAlwaysProjectsRowsFromLatestQuerySnapshot() async {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let alpha = ClipboardItem.text("alpha needle")
        let beta = ClipboardItem.text("beta haystack")
        await populateStore(store, with: [alpha, beta])
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)
        let projector = ClipboardListDisplayStateProjector()

        let expectations: [(query: String, visibleIDs: [UUID])] = [
            ("alpha", [alpha.id]),
            ("beta", [beta.id]),
            ("needle", [alpha.id]),
        ]

        for expectation in expectations {
            viewModel.searchText = expectation.query
            await waitForHistorySearch(viewModel)

            let state = projector.project(
                snapshotID: viewModel.filteredItemsSnapshotID,
                cache: viewModel.preparedDisplayCache,
                viewportHeight: 200
            )

            XCTAssertEqual(state.layoutIndex.entries.map(\.id), expectation.visibleIDs)
        }
    }

    func testOneQueryPublishesOneAtomicResultSnapshot() async {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let matching = ClipboardItem.text("git commit")
        let unrelated = ClipboardItem.text("unrelated content")
        await populateStore(store, with: [matching, unrelated])
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)
        await waitForHistorySearch(viewModel)

        var observedSnapshotIDs: Set<UUID> = [viewModel.filteredItemsSnapshotID]
        viewModel.searchText = "gti"
        while viewModel.isSearching {
            observedSnapshotIDs.insert(viewModel.filteredItemsSnapshotID)
            try? await Task.sleep(for: .milliseconds(2))
        }
        observedSnapshotIDs.insert(viewModel.filteredItemsSnapshotID)

        XCTAssertEqual(viewModel.filteredItems.map(\.id), [matching.id])
        XCTAssertEqual(
            observedSnapshotIDs.count,
            2,
            "A single query must replace the old list once, not once per internal search phase"
        )
    }

    func testActiveSearchRefreshesWhenIndexBecomesReady() async throws {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let matchingItem = ClipboardItem.text("delayed needle")
        let otherItem = ClipboardItem.text("unrelated")
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)

        viewModel.searchText = "needle"
        XCTAssertEqual(viewModel.searchText, "needle")

        try await store.add(matchingItem)
        try await store.add(otherItem)
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
        await waitForHistorySearch(viewModel)
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [fileBackedItem.id])

        viewModel.searchText = "ocr needle"
        await waitForHistorySearch(viewModel)
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [imageItem.id])

        viewModel.searchText = "orc needel"
        await waitForHistorySearch(viewModel)
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [imageItem.id])
        XCTAssertEqual(
            viewModel.searchResultsByItemID[imageItem.id]?.evidence.kind.classification,
            .fuzzy
        )

        viewModel.searchText = "inline needle"
        await waitForHistorySearch(viewModel)
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [inlineItem.id])

        viewModel.searchText = "#ff0000"
        await waitForHistorySearch(viewModel)
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [colorItem.id])

        viewModel.searchText = "openai.com/research"
        await waitForHistorySearch(viewModel)
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [linkItem.id])

        viewModel.searchText = "person@example.com"
        await waitForHistorySearch(viewModel)
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
        await waitForHistorySearch(viewModel)
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

    func testDetailActionsMatchSingleLinkSelection() async throws {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let item = ClipboardItem.link(
            URL(string: "https://openai.com/research")!,
            originalText: "openai.com/research"
        )
        await populateStore(store, with: [item])
        let response = try await store.search(ClipboardQuery(text: "openai"), generation: 1)
        XCTAssertTrue(response.hits.contains { $0.itemID == item.id })

        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)
        viewModel.searchText = "openai"
        await waitForHistorySearch(viewModel)

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

        viewModel.setBookmarkedOnly(true)

        await eventually { viewModel.filteredItems.map(\.id) == [bookmarked.id] }
        XCTAssertFalse(viewModel.isShowingFullHistory)
        XCTAssertTrue(
            viewModel.contextMenuActions(for: bookmarked.id).contains {
                $0.action == .jumpToHistory
            }
        )

        viewModel.jumpToHistory(for: bookmarked)

        await eventually {
            Set(viewModel.filteredItems.map(\.id)) == [ordinary.id, bookmarked.id]
        }

        XCTAssertTrue(viewModel.activeQuery.isEmpty)
        XCTAssertTrue(viewModel.filterState.isEmpty)
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
        await waitForHistorySearch(viewModel)
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
        viewModel.setSelectedKind(.text)
        viewModel.clearSearchAfterCommittedAction()

        XCTAssertEqual(viewModel.searchText, "needle")
        XCTAssertEqual(viewModel.filterState.selectedKind, .text)
    }

    func testClearSearchAfterCommittedActionClearsTextAndFiltersByDefault() {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)
        viewModel.searchText = "needle"
        viewModel.setBookmarkedOnly(true)
        viewModel.setSelectedKind(.text)
        viewModel.setDateFilterSelection(
            HistoryDateFilterSelection(day: HistoryCalendarDay(year: 2026, month: 8, day: 14))
        )

        viewModel.clearSearchAfterCommittedAction()

        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertTrue(viewModel.filterState.isEmpty)
        XCTAssertTrue(viewModel.activeQuery.isEmpty)
    }

    func testClearingTextDirectlyDoesNotClearFilters() {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)
        viewModel.searchText = "needle"
        viewModel.setBookmarkedOnly(true)

        viewModel.searchText = ""

        XCTAssertTrue(viewModel.filterState.isBookmarkedOnly)
        XCTAssertFalse(viewModel.activeQuery.isEmpty)
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
        await waitForHistorySearch(viewModel)
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
        await waitForHistorySearch(viewModel)
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

    func testCopyOnlyDismissesBeforeRestoringPreviousApplicationFocus() async {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let item = ClipboardItem.text("copy me")
        await populateStore(store, with: [item])
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)
        await waitForHistorySearch(viewModel)
        var events: [String] = []
        let actionHandler = makeActionHandler(
            viewModel: viewModel,
            store: store,
            settings: settings,
            onCopy: { _ in
                events.append("copy")
                return true
            },
            onDismiss: { events.append("dismiss") },
            onRestoreFocus: { events.append("restore") }
        )

        actionHandler.performCopyOnlyAction()

        await eventually { events.count == 3 }
        XCTAssertEqual(events, ["copy", "dismiss", "restore"])
    }

    func testEscapeDismissesBeforeRestoringPreviousApplicationFocus() {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)
        var events: [String] = []
        let actionHandler = makeActionHandler(
            viewModel: viewModel,
            store: store,
            settings: settings,
            onDismiss: { events.append("dismiss") },
            onRestoreFocus: { events.append("restore") }
        )

        actionHandler.dismissHistoryWindow()

        XCTAssertEqual(events, ["dismiss", "restore"])
    }

    func testDeleteSelectedItemPrefersNextVisibleItem() async {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)

        let oldest = ClipboardItem.text("oldest")
        let middle = ClipboardItem.text("middle")
        let newest = ClipboardItem.text("newest")
        await populateStore(store, with: [oldest, middle, newest])

        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)
        await waitForHistorySearch(viewModel)
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
        await waitForHistorySearch(viewModel)

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

    func testDeletePublishesViewportIntentBeforeMutatingHistory() async throws {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let oldest = ClipboardItem.text("oldest")
        let middle = ClipboardItem.text("middle")
        let newest = ClipboardItem.text("newest")
        await populateStore(store, with: [oldest, middle, newest])
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)
        await waitForHistorySearch(viewModel)

        var preparedItemIDs: Set<UUID>?
        var preparedSnapshot: ClipboardListContentSnapshot?
        viewModel.setListViewportPreservationHandler(
            ClipboardListViewportPreservationHandler(
                prepareForRemoval: { itemIDs, snapshot in
                    preparedItemIDs = itemIDs
                    preparedSnapshot = snapshot
                },
                cancel: {}
            )
        )
        viewModel.selectSingle(middle.id)
        let request = try XCTUnwrap(viewModel.makeDeleteSelectionRequest())

        viewModel.delete(request)

        XCTAssertEqual(preparedItemIDs, [middle.id])
        XCTAssertEqual(preparedSnapshot?.id, viewModel.filteredItemsSnapshotID)
        XCTAssertEqual(preparedSnapshot?.items.map(\.id), [newest.id, middle.id, oldest.id])
        XCTAssertTrue(
            preparedSnapshot?.displayCache.matches(
                sourceSnapshotID: viewModel.filteredItemsSnapshotID
            ) == true
        )
        await eventually {
            !store.items.contains(where: { $0.id == middle.id })
        }
    }

    func testMutationKeepsOriginalMultiSelectionAfterSelectionChanges() async {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let oldest = ClipboardItem.text("oldest")
        let middle = ClipboardItem.text("middle")
        let newest = ClipboardItem.text("newest")
        await populateStore(store, with: [oldest, middle, newest])
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)
        await waitForHistorySearch(viewModel)

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
        viewModel.setBookmarkedOnly(true)
        viewModel.clearSearchAfterClosingIfNeeded()

        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertTrue(viewModel.filterState.isEmpty)
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
        viewModel.setBookmarkedOnly(true)
        viewModel.clearSearchAfterClosingIfNeeded()

        XCTAssertEqual(viewModel.searchText, "needle")
        XCTAssertTrue(viewModel.filterState.isBookmarkedOnly)
    }

    func testFiltersCombineSynchronouslyWithFuzzyOCRSearch() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 12))
        )
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let matching = ClipboardItem(
            timestamp: now,
            sourceApp: "Notes",
            sourceAppBundleIdentifier: "com.apple.Notes",
            isBookmarked: true,
            content: .image(.init(filename: "matching.png", ocrText: "invoice total"))
        )
        let wrongBookmark = ClipboardItem(
            timestamp: now,
            sourceApp: "Notes",
            sourceAppBundleIdentifier: "com.apple.Notes",
            content: .image(.init(filename: "bookmark.png", ocrText: "invoice total"))
        )
        let wrongApp = ClipboardItem(
            timestamp: now,
            sourceApp: "Preview",
            sourceAppBundleIdentifier: "com.apple.Preview",
            isBookmarked: true,
            content: .image(.init(filename: "app.png", ocrText: "invoice total"))
        )
        let wrongType = ClipboardItem(
            timestamp: now,
            sourceApp: "Notes",
            sourceAppBundleIdentifier: "com.apple.Notes",
            isBookmarked: true,
            content: .text(.init(inlineText: "invoice total"))
        )
        let wrongDate = ClipboardItem(
            timestamp: yesterday,
            sourceApp: "Notes",
            sourceAppBundleIdentifier: "com.apple.Notes",
            isBookmarked: true,
            content: .image(.init(filename: "date.png", ocrText: "invoice total"))
        )
        await populateStore(
            store,
            with: [matching, wrongBookmark, wrongApp, wrongType, wrongDate]
        )
        let viewModel = HistoryViewModel(
            store: store,
            settingsManager: settings,
            ocrService: FakeOCRService(result: ""),
            filterCalendar: calendar
        )

        var revision = viewModel.filteredItemsRevision
        viewModel.setBookmarkedOnly(true)
        await eventually { viewModel.filteredItemsRevision > revision }
        revision = viewModel.filteredItemsRevision
        viewModel.setSelectedApplication(bundleIdentifier: "com.apple.Notes")
        await eventually { viewModel.filteredItemsRevision > revision }
        revision = viewModel.filteredItemsRevision
        viewModel.setSelectedKind(.image)
        await eventually { viewModel.filteredItemsRevision > revision }
        revision = viewModel.filteredItemsRevision
        viewModel.setDateFilterSelection(
            HistoryDateFilterSelection(
                day: HistoryCalendarDay(date: now, calendar: calendar)
            )
        )
        await eventually { viewModel.filteredItemsRevision > revision }
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [matching.id])

        revision = viewModel.filteredItemsRevision
        viewModel.searchText = "inovice"
        await waitForHistorySearch(viewModel)

        XCTAssertGreaterThan(viewModel.filteredItemsRevision, revision)
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [matching.id])
        XCTAssertEqual(viewModel.searchResultsByItemID[matching.id]?.evidence.field, .ocr)
        XCTAssertEqual(
            viewModel.searchResultsByItemID[matching.id]?.evidence.kind.classification,
            .fuzzy
        )
        XCTAssertEqual(viewModel.selectedID, matching.id)
        XCTAssertEqual(viewModel.quickPasteBadgeNumberByItemID[matching.id], 1)
    }

    func testDateAvailabilityUsesEntireHistoryRegardlessOfOtherFilters() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let textDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 12))
        )
        let imageDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 12))
        )
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        await populateStore(
            store,
            with: [
                ClipboardItem(timestamp: textDate, content: .text(.init(inlineText: "text"))),
                ClipboardItem(timestamp: imageDate, content: .image(.init(filename: "image.png"))),
            ]
        )
        let viewModel = HistoryViewModel(
            store: store,
            settingsManager: settings,
            ocrService: FakeOCRService(result: ""),
            filterCalendar: calendar
        )
        await waitForHistorySearch(viewModel)

        viewModel.setSelectedKind(.text)
        await waitForHistorySearch(viewModel)

        XCTAssertEqual(
            viewModel.dateAvailability.copiedDays,
            Set([
                HistoryCalendarDay(date: textDate, calendar: calendar),
                HistoryCalendarDay(date: imageDate, calendar: calendar),
            ])
        )
    }

    func testDeletingRangeEndpointShrinksSelectionToRemainingCopiedDays() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let firstDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 12))
        )
        let lastDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 12))
        )
        let firstItem = ClipboardItem(
            timestamp: firstDate,
            content: .text(.init(inlineText: "first"))
        )
        let lastItem = ClipboardItem(
            timestamp: lastDate,
            content: .text(.init(inlineText: "last"))
        )
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        await populateStore(store, with: [firstItem, lastItem])
        let viewModel = HistoryViewModel(
            store: store,
            settingsManager: settings,
            ocrService: FakeOCRService(result: ""),
            filterCalendar: calendar
        )
        await waitForHistorySearch(viewModel)
        let lastDay = HistoryCalendarDay(date: lastDate, calendar: calendar)
        viewModel.setDateFilterSelection(
            HistoryDateFilterSelection(
                startDay: HistoryCalendarDay(date: firstDate, calendar: calendar),
                endDay: lastDay
            )
        )
        await waitForHistorySearch(viewModel)

        try await store.delete(firstItem)

        await eventually {
            viewModel.filterState.dateSelection == HistoryDateFilterSelection(day: lastDay)
                && viewModel.filteredItems.map(\.id) == [lastItem.id]
        }
    }

    func testApplicationOptionsDeduplicateSortAndRetainActiveSelection() {
        let older = ClipboardItem(
            timestamp: Date(timeIntervalSince1970: 1),
            sourceApp: "Old Name",
            sourceAppBundleIdentifier: "com.example.beta",
            sourceAppBundlePath: "/Applications/Old.app",
            content: .text(.init(inlineText: "older"))
        )
        let newest = ClipboardItem(
            timestamp: Date(timeIntervalSince1970: 2),
            sourceApp: "Beta",
            sourceAppBundleIdentifier: "com.example.beta",
            sourceAppBundlePath: "/Applications/Beta.app",
            content: .text(.init(inlineText: "newest"))
        )
        let alpha = ClipboardItem(
            sourceApp: "Alpha",
            sourceAppBundleIdentifier: "com.example.alpha",
            content: .text(.init(inlineText: "alpha"))
        )
        let unidentified = ClipboardItem(
            sourceApp: "Unknown",
            content: .text(.init(inlineText: "unknown"))
        )
        let invalidIdentifier = ClipboardItem(
            sourceApp: "Invalid",
            sourceAppBundleIdentifier: "  \n",
            content: .text(.init(inlineText: "invalid"))
        )
        let options = HistoryApplicationFilterOptions.make(
            from: [older, unidentified, newest, invalidIdentifier, alpha]
        )

        XCTAssertEqual(options.map(\.displayName), ["Alpha", "Beta"])
        XCTAssertEqual(options.last?.iconItem.id, newest.id)
        XCTAssertEqual(options.last?.iconItem.sourceAppBundlePath, "/Applications/Beta.app")

        let retained = HistoryApplicationFilterOptions.make(
            from: [],
            retaining: options.last
        )
        XCTAssertEqual(retained, [options.last].compactMap { $0 })
    }

    func testFilterBarPresentationProjectsLabelsAccessibilityAndAvailability() {
        let inactive = HistoryFilterBarPresentation(
            filterState: HistoryFilterState(),
            hasApplicationOptions: false
        )

        XCTAssertEqual(
            [
                inactive.bookmarks.title,
                inactive.application.title,
                inactive.kind.title,
                inactive.date.title,
            ],
            ["Bookmarks", "App", "Type", "Date"]
        )
        XCTAssertEqual(
            [
                inactive.bookmarks.accessibilityIdentifier,
                inactive.application.accessibilityIdentifier,
                inactive.kind.accessibilityIdentifier,
                inactive.date.accessibilityIdentifier,
            ],
            [
                "historyFilter.bookmarks",
                "historyFilter.app",
                "historyFilter.type",
                "historyFilter.date",
            ]
        )
        XCTAssertFalse(inactive.bookmarks.isActive)
        XCTAssertFalse(inactive.application.isEnabled)

        let item = ClipboardItem(
            sourceApp: "Very Long Application Name",
            sourceAppBundleIdentifier: "com.example.long-name",
            content: .text(.init(inlineText: "item"))
        )
        let application = HistoryApplicationFilterOption(
            bundleIdentifier: "com.example.long-name",
            displayName: "Very Long Application Name",
            representativeItem: item
        )
        let activeState = HistoryFilterState(
            isBookmarkedOnly: true,
            selectedApplication: application,
            selectedKind: .image,
            dateSelection: HistoryDateFilterSelection(
                startDay: HistoryCalendarDay(year: 2026, month: 7, day: 16),
                endDay: HistoryCalendarDay(year: 2026, month: 8, day: 14)
            )
        )
        let active = HistoryFilterBarPresentation(
            filterState: activeState,
            hasApplicationOptions: true
        )

        XCTAssertEqual(active.application.title, "Very Long Application Name")
        XCTAssertEqual(active.application.accessibilityValue, "Very Long Application Name")
        XCTAssertEqual(active.kind.title, "Image")
        XCTAssertNotEqual(active.date.title, "Date")
        XCTAssertTrue(active.bookmarks.isActive)
        XCTAssertTrue(active.application.isActive)
        XCTAssertTrue(active.kind.isActive)
        XCTAssertTrue(active.date.isActive)
        XCTAssertTrue(active.application.isEnabled)
    }

    func testViewModelRetainsSelectedApplicationAfterItsItemsDisappear() async throws {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let item = ClipboardItem(
            sourceApp: "Notes",
            sourceAppBundleIdentifier: "com.apple.Notes",
            content: .text(.init(inlineText: "note"))
        )
        await populateStore(store, with: [item])
        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)
        await waitForHistorySearch(viewModel)
        viewModel.setSelectedApplication(bundleIdentifier: "com.apple.Notes")
        await waitForHistorySearch(viewModel)

        try await store.delete(item)
        await eventually {
            store.items.isEmpty && viewModel.filteredItems.isEmpty && !viewModel.isSearching
        }

        XCTAssertEqual(viewModel.applicationFilterOptions.map(\.bundleIdentifier), ["com.apple.Notes"])
        XCTAssertEqual(
            viewModel.filterState.selectedApplication?.bundleIdentifier,
            "com.apple.Notes"
        )
        XCTAssertTrue(viewModel.filteredItems.isEmpty)
        XCTAssertFalse(viewModel.activeQuery.isEmpty)

        viewModel.setSelectedApplication(bundleIdentifier: nil)
        await waitForHistorySearch(viewModel)

        XCTAssertTrue(viewModel.applicationFilterOptions.isEmpty)
        XCTAssertTrue(viewModel.filterState.isEmpty)
        XCTAssertTrue(viewModel.activeQuery.isEmpty)
    }
}

@MainActor
private func makeActionHandler(
    viewModel: HistoryViewModel,
    store: ClipboardStore,
    settings: SettingsManager,
    onCopy: @escaping ([ClipboardItem]) async -> Bool = { _ in true },
    onPaste: @escaping (ClipboardItem) -> Void = { _ in },
    onPasteMultiple: @escaping ([ClipboardItem]) -> Void = { _ in },
    onDismiss: @escaping () -> Void = {},
    onRestoreFocus: @escaping () -> Void = {}
) -> HistoryActionHandler {
    HistoryActionHandler(
        viewModel: viewModel,
        contentReader: store,
        assetProvider: ClipboardItemAssetProvider(store: store, settings: settings),
        onCopy: onCopy,
        onPaste: { items in
            if items.count == 1, let item = items.first {
                onPaste(item)
            } else {
                onPasteMultiple(items)
            }
        },
        onDismiss: onDismiss,
        onRestoreFocus: onRestoreFocus,
        presentingWindow: { nil }
    )
}
