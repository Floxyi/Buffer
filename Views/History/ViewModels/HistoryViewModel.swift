import AppKit
import Combine
import SwiftUI

@MainActor
final class HistoryViewModel: ObservableObject {
    typealias OpenListScrollRequest = HistoryOpenListScrollRequest
    typealias JumpToHistoryRequest = HistoryJumpToHistoryRequest
    typealias KeyboardScrollRequest = HistoryKeyboardScrollRequest
    typealias JumpToHistoryState = HistoryJumpToHistoryState

    private struct PublishedSearchContext {
        let session: ClipboardSearchSession
    }

    var searchText: String {
        get { searchTextValue }
        set {
            guard newValue != searchTextValue else { return }
            searchTextValue = newValue
            guard !isApplyingQueryConfiguration else { return }
            scheduleQuery(preferredID: filteredItems.first?.id)
        }
    }

    @Published private var querySnapshot = HistoryQuerySnapshot()
    @Published private var selectionViewState = HistorySelectionViewState()
    @Published private var presentationState = HistoryViewPresentationState()
    @Published private(set) var detailViewState = HistoryDetailViewState()
    private(set) var filterState = HistoryFilterState()
    @Published private(set) var applicationFilterOptions: [HistoryApplicationFilterOption] = []
    @Published private(set) var isSearching = false
    @Published private(set) var searchStatus = ClipboardSearchStatus.initial
    @Published var mutationFailure: HistoryMutationFailure?

    private let store: ClipboardStore
    private let settingsManager: SettingsManager
    private let projectionCoordinator = HistorySearchProjectionCoordinator()
    private let selectionController = HistorySelectionController()
    private let quickPasteController = HistoryQuickPasteController()
    private let jumpNavigationController = HistoryJumpNavigationController()
    private let actionResolver = HistoryActionResolver()
    private let contextMenuController = HistoryContextMenuController()
    private let itemMutationController = HistoryItemMutationController()
    private let sessionController = HistorySessionController()
    private let selectionViewStateProjector = HistorySelectionViewStateProjector()
    private let keyboardScrollRouter: HistoryKeyboardScrollRouter
    private let detailModel: HistoryDetailModel
    private let filterCalendar: Calendar
    private let nowProvider: @MainActor () -> Date
    private var selectionState = HistorySelectionState()
    private var quickPasteState = HistoryQuickPasteState()
    private var navigationState = HistoryNavigationState()
    private var cancellables: Set<AnyCancellable> = []
    private var queryFilters = ClipboardFilters()
    private var includesOCRTextInSearch = true
    private var isApplyingQueryConfiguration = false
    @Published private var searchTextValue = ""
    private var filteredItemByID: [UUID: ClipboardItem] = [:]
    private var filteredItemIndexByID: [UUID: Int] = [:]
    private var keyboardDetailTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var snippetTask: Task<Void, Never>?
    private var searchGeneration: UInt = 0
    private var publishedSearchContext: PublishedSearchContext?
    private var pendingMutationPreferredSelectionID: UUID?

    init(
        store: ClipboardStore,
        settingsManager: SettingsManager,
        ocrService: OCRServicing,
        assetProvider: (any ClipboardItemAssetProviding)? = nil,
        keyboardScrollRouter: HistoryKeyboardScrollRouter = HistoryKeyboardScrollRouter(),
        filterCalendar: Calendar = .autoupdatingCurrent,
        nowProvider: @escaping @MainActor () -> Date = Date.init
    ) {
        self.store = store
        self.settingsManager = settingsManager
        self.filterCalendar = filterCalendar
        self.nowProvider = nowProvider
        let resolvedAssetProvider =
            assetProvider ?? ClipboardItemAssetProvider(store: store, settings: settingsManager)
        self.detailModel = HistoryDetailModel(
            store: store,
            assetProvider: resolvedAssetProvider,
            ocrService: ocrService
        )
        self.keyboardScrollRouter = keyboardScrollRouter
        store.$items
            .sink { [weak self] items in
                guard let self else { return }
                self.scheduleQuery(
                    preferredID: self.pendingMutationPreferredSelectionID ?? self.selectedID,
                    itemsSnapshot: items
                )
            }
            .store(in: &cancellables)

        Publishers.Merge(
            NotificationCenter.default.publisher(for: .NSCalendarDayChanged),
            NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)
        )
        .sink { [weak self] _ in
            self?.refreshActiveDateFilter()
        }
        .store(in: &cancellables)

        store.$searchStatus
            .sink { [weak self] searchStatus in
                guard let self else { return }
                self.searchStatus = searchStatus
                guard !self.activeQuery.normalizedText.isEmpty,
                    searchStatus.indexGeneration
                        > (self.publishedSearchContext?.session.committedState.indexGeneration ?? 0)
                else { return }
                self.scheduleQuery(
                    preferredID: self.selectedID
                )
            }
            .store(in: &cancellables)

        store.$ocrProcessingItemIDs
            .sink { [weak self] _ in
                self?.detailModel.refreshOCRProcessingState()
            }
            .store(in: &cancellables)

        detailModel.$viewState
            .sink { [weak self] state in
                self?.detailViewState = state
            }
            .store(in: &cancellables)
    }

    private var selectionQuery: HistorySelectionQuery {
        HistorySelectionQuery(
            filteredItems: filteredItems,
            selectedIDs: selectionViewState.selectedIDs,
            selectedActionOrderIDs: selectionViewState.selectedActionOrderIDs,
            selectedID: selectionViewState.selectedID,
            isQueryEmpty: activeQuery.isEmpty,
            totalItemCount: store.items.count,
            itemByID: filteredItemByID,
            itemIndexByID: filteredItemIndexByID
        )
    }

    var filteredItems: [ClipboardItem] {
        querySnapshot.items
    }

    var filteredItemsRevision: UInt {
        UInt(querySnapshot.renderRevision)
    }

    var filteredItemsSnapshotID: UUID {
        querySnapshot.id
    }

    var searchResultsByItemID: [UUID: ClipboardSearchHit] {
        querySnapshot.hitByItemID
    }

    var committedSearchText: String {
        querySnapshot.query.text
    }

    var preparedDisplayCache: ClipboardListStructure.DisplayCache {
        querySnapshot.displayCache
    }

    var selectedItem: ClipboardItem? {
        selectionQuery.selectedItem
    }

    var previewImage: NSImage? {
        detailViewState.previewImage
    }

    var chunkedText: ChunkedTextState {
        detailViewState.chunkedText
    }

    var isExtractingText: Bool {
        detailViewState.isExtractingText
    }

    var showsQuickPasteNumbers: Bool {
        presentationState.showsQuickPasteNumbers
    }

    var windowOpenToken: Int {
        presentationState.windowOpenToken
    }

    var shouldFocusSearchOnOpen: Bool {
        presentationState.shouldFocusSearchOnOpen
    }

    var searchSelectionToken: Int {
        presentationState.searchSelectionToken
    }

    var openListScrollRequest: OpenListScrollRequest {
        presentationState.openListScrollRequest
    }

    var openListScrollRequestToken: Int {
        presentationState.openListScrollRequestToken
    }

    var jumpToHistoryState: JumpToHistoryState {
        presentationState.jumpToHistoryState
    }

    var keyboardScrollRequest: KeyboardScrollRequest? {
        navigationState.keyboardScrollRequest
    }

    var selectedIDs: Set<UUID> {
        selectionViewState.selectedIDs
    }

    var selectedActionOrderIDs: [UUID] {
        selectionViewState.selectedActionOrderIDs
    }

    var selectedIndex: Int {
        selectionViewState.selectedIndex
    }

    var selectedID: UUID? {
        selectionViewState.selectedID
    }

    var selectedItems: [ClipboardItem] {
        selectionQuery.selectedItems
    }

    var selectedItemsInVisualOrder: [ClipboardItem] {
        selectedItems
    }

    var selectedItemsInActionOrder: [ClipboardItem] {
        selectionQuery.selectedItemsInActionOrder
    }

    var selectionCount: Int {
        selectionQuery.selectionCount
    }

    var activeJumpToHistoryRequest: JumpToHistoryRequest? {
        navigationState.jumpToHistoryState.request
    }

    var isShowingFullHistory: Bool {
        selectionQuery.isShowingFullHistory
    }

    var quickPasteBadgeNumberByItemID: [UUID: Int] {
        quickPasteController.badgeNumberByItemID(for: filteredItems, settings: settingsManager)
    }

    var activeQuery: ClipboardQuery {
        ClipboardQuery(
            text: searchText,
            filters: queryFilters,
            includesOCRText: includesOCRTextInSearch
        )
    }

    func setBookmarkedOnly(_ isEnabled: Bool) {
        mutateFilterState { $0.isBookmarkedOnly = isEnabled }
    }

    func setSelectedApplication(bundleIdentifier: String?) {
        let selectedApplication = bundleIdentifier.flatMap { bundleIdentifier in
            applicationFilterOptions.first { $0.bundleIdentifier == bundleIdentifier }
        }
        guard bundleIdentifier == nil || selectedApplication != nil else { return }
        mutateFilterState { $0.selectedApplication = selectedApplication }
    }

    func setSelectedKind(_ kind: ClipboardItemKind?) {
        mutateFilterState { $0.selectedKind = kind }
    }

    func setDateFilterPreset(_ preset: HistoryDateFilterPreset) {
        mutateFilterState { $0.datePreset = preset }
    }

    func setIncludesOCRTextInSearch(_ isEnabled: Bool) {
        guard includesOCRTextInSearch != isEnabled else { return }
        updateQueryConfiguration(preferredID: filteredItems.first?.id) {
            includesOCRTextInSearch = isEnabled
        }
    }

    func handleWindowOpen(
        focusSearch: Bool,
        suppressQuickPasteUntilModifiersReleased: Bool
    ) {
        refreshActiveDateFilter()
        let plan = sessionController.makeWindowOpenPlan(
            searchText: searchText,
            focusSearch: focusSearch,
            currentSelectionIsEmpty: selectedIDs.isEmpty,
            selectedID: selectedID,
            filteredItems: filteredItems,
            historyWindowOpenBehavior: settingsManager.historyWindowOpenBehavior
        )

        if plan.shouldIncrementSearchSelectionToken {
            updatePresentationState { $0.searchSelectionToken &+= 1 }
        }

        updatePresentationState { $0.shouldFocusSearchOnOpen = plan.shouldFocusSearchOnOpen }
        prepareQuickPasteForWindowOpen(
            using: NSEvent.modifierFlags, forceModifierReset: suppressQuickPasteUntilModifiersReleased)

        switch plan.selectionPreference {
        case .keepCurrentOrSelectTop:
            syncSelection()
        case .selectPreferred(let preferredID):
            syncSelection(preferredID: preferredID)
        }

        if let openListScrollRequest = plan.openListScrollRequest {
            updatePresentationState {
                $0.openListScrollRequest = openListScrollRequest
                $0.openListScrollRequestToken &+= 1
            }
        }

        updatePresentationState { $0.windowOpenToken += 1 }
    }

    func prepareQuickPasteForWindowOpen(
        using flags: NSEvent.ModifierFlags,
        forceModifierReset: Bool = false
    ) {
        quickPasteState = quickPasteController.prepareForWindowOpen(
            using: flags,
            forceModifierReset: forceModifierReset,
            state: quickPasteState
        )
        applyQuickPasteState()
    }

    func handleQuickPasteModifierFlagsChange(_ flags: NSEvent.ModifierFlags) {
        let nextState = quickPasteController.handleModifierFlagsChange(
            flags,
            state: quickPasteState,
            isQuickPasteEnabled: settingsManager.quickPasteEnabled
        )

        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
            quickPasteState = nextState
            applyQuickPasteState()
        }
    }

    func handleAppResignActive() {
        quickPasteState = quickPasteController.resetForAppResignActive(state: quickPasteState)
        applyQuickPasteState()
    }

    func clearSearchAfterCommittedAction() {
        clearQueryIfNeeded(shouldKeepQuery: settingsManager.keepSearchTextAfterPaste)
    }

    func clearSearchAfterClosingIfNeeded() {
        clearQueryIfNeeded(shouldKeepQuery: settingsManager.keepSearchTextAfterClosing)
    }

    func selectSingle(_ id: UUID) {
        guard let index = filteredItems.firstIndex(where: { $0.id == id }) else { return }
        selectSingle(id, at: index)
    }

    func selectSingle(_ id: UUID, at index: Int) {
        let resolvedIndex: Int
        if filteredItems.indices.contains(index), filteredItems[index].id == id {
            resolvedIndex = index
        } else if let currentIndex = filteredItems.firstIndex(where: { $0.id == id }) {
            resolvedIndex = currentIndex
        } else {
            return
        }

        let selectionToken = BufferPerformanceDiagnostics.begin(.pointerSelection)
        navigationState = jumpNavigationController.clearKeyboardScrollRequest(state: navigationState)
        selectionState = selectionController.applySingleSelection(
            id,
            index: resolvedIndex,
            in: filteredItems,
            state: selectionState
        )

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectionViewState = selectionViewStateProjector.project(selectionState)
        }
        BufferPerformanceDiagnostics.end(selectionToken)

        let item = filteredItems[resolvedIndex]
        beginDetailLoad(
            selectedItem: item,
            selectedItemsInVisualOrder: [item],
            selectedItemsInActionOrder: [item]
        )
    }

    @discardableResult
    func selectPreferredTopItem() -> UUID? {
        guard let preferredTopSelectionID = preferredTopSelectionID() else {
            clearSelection()
            return nil
        }

        syncSelection(preferredID: preferredTopSelectionID)
        return preferredTopSelectionID
    }

    func toggleSelection(_ id: UUID) {
        navigationState = jumpNavigationController.clearKeyboardScrollRequest(state: navigationState)
        selectionState = selectionController.toggleSelection(id, in: filteredItems, state: selectionState)
        applySelectionState()
    }

    func extendSelectionTo(_ targetID: UUID) {
        guard selectionState.selectionAnchor != nil else {
            selectSingle(targetID)
            return
        }
        selectionState = selectionController.extendSelection(to: targetID, in: filteredItems, state: selectionState)
        applySelectionState()
    }

    func navigateUp() {
        navigate(by: -1)
    }

    func navigateDown() {
        navigate(by: 1)
    }

    func jumpToFirstItem() {
        moveKeyboardSelection(to: 0, extending: false)
    }

    func jumpToLastItem() {
        moveKeyboardSelection(to: filteredItems.count - 1, extending: false)
    }

    func extendSelectionToFirstItem() {
        moveKeyboardSelection(to: 0, extending: true)
    }

    func extendSelectionToLastItem() {
        moveKeyboardSelection(to: filteredItems.count - 1, extending: true)
    }

    func extendSelectionUp() {
        moveKeyboardSelection(to: selectedIndex - 1, extending: true)
    }

    func extendSelectionDown() {
        moveKeyboardSelection(to: selectedIndex + 1, extending: true)
    }

    func selectAllItems() {
        guard !filteredItems.isEmpty else { return }

        let nextState = selectionController.selectAll(in: filteredItems, state: selectionState)
        publishKeyboardSelection(nextState, focusedIndex: nextState.selectedIndex)
    }

    func togglePinForSelectedItem() {
        togglePin(for: selectedItemsInActionOrder)
    }

    func toggleBookmarkForSelectedItem() {
        toggleBookmark(for: selectedItemsInActionOrder)
    }

    func deleteSelectedItems() {
        guard let request = makeDeleteSelectionRequest() else { return }
        delete(request)
    }

    func makeDeleteSelectionRequest() -> HistoryDeleteRequest? {
        itemMutationController.makeDeleteRequest(
            for: selectedItemsInActionOrder,
            in: filteredItems,
            selectionController: selectionController
        )
    }

    func delete(_ request: HistoryDeleteRequest) {
        pendingMutationPreferredSelectionID = request.preferredSelectionID
        performMutation { [self] in
            do {
                let preferredID = try await itemMutationController.delete(request, store: store)
                syncSelection(preferredID: preferredID)
            } catch {
                pendingMutationPreferredSelectionID = nil
                throw error
            }
        }
    }

    func togglePin(for items: [ClipboardItem]) {
        guard !items.isEmpty else { return }
        focusSingleMutationTargetIfNeeded(items)
        performMutation { [self] in
            try await itemMutationController.togglePinForSelectedItems(items, store: store)
        }
    }

    func toggleBookmark(for items: [ClipboardItem]) {
        guard !items.isEmpty else { return }
        focusSingleMutationTargetIfNeeded(items)
        performMutation { [self] in
            try await itemMutationController.toggleBookmarkForSelectedItems(items, store: store)
        }
    }

    func delete(_ items: [ClipboardItem]) {
        guard !items.isEmpty else { return }
        focusSingleMutationTargetIfNeeded(items)
        guard
            let request = itemMutationController.makeDeleteRequest(
                for: items,
                in: filteredItems,
                selectionController: selectionController
            )
        else { return }
        delete(request)
    }

    func contextMenuTargetItems(for clickedItemID: UUID) -> [ClipboardItem] {
        contextMenuController.targetItems(
            for: clickedItemID,
            itemByID: filteredItemByID,
            selectedIDs: selectedIDs,
            selectedItemsInActionOrder: selectedItemsInActionOrder
        )
    }

    func contextMenuActions(for clickedItemID: UUID) -> [HistoryItemActionDescriptor] {
        contextMenuController.actions(
            for: clickedItemID,
            itemByID: filteredItemByID,
            selectedIDs: selectedIDs,
            selectedItemsInActionOrder: selectedItemsInActionOrder,
            allowsJumpToHistory: !activeQuery.isEmpty,
            ocrProcessingItemIDs: store.ocrProcessingItemIDs,
            actionResolver: actionResolver
        )
    }

    func dismissMutationFailure() {
        mutationFailure = nil
    }

    func jumpToHistory(for item: ClipboardItem) {
        let targetID = item.id
        let hadActiveFilters = !filterState.isEmpty || !queryFilters.isEmpty
        navigationState = jumpNavigationController.beginJump(to: targetID, state: navigationState)
        updatePresentationState { $0.jumpToHistoryState = navigationState.jumpToHistoryState }

        logJumpToHistory(
            "Jump to history requested item=\(targetID.uuidString) generation=\(navigationState.jumpToHistoryState.request?.generation ?? 0)"
        )

        let jumpPlan = sessionController.makeJumpToHistoryPlan(
            for: targetID,
            currentSearchText: searchText
        )
        if jumpPlan.searchText != nil || hadActiveFilters {
            updateQueryConfiguration(preferredID: jumpPlan.preferredSelectionID) {
                filterState = HistoryFilterState()
                queryFilters = ClipboardFilters()
                if let nextSearchText = jumpPlan.searchText {
                    searchText = nextSearchText
                }
            }
        } else {
            syncSelection(preferredID: jumpPlan.preferredSelectionID)
        }
    }

    func markJumpToHistoryScrollStarted(_ request: JumpToHistoryRequest) {
        navigationState = jumpNavigationController.markJumpScrollStarted(request, state: navigationState)
        updatePresentationState { $0.jumpToHistoryState = navigationState.jumpToHistoryState }

        logJumpToHistory(
            "Jump to history scroll started item=\(request.itemID.uuidString) generation=\(request.generation)"
        )
    }

    func completeJumpToHistoryScroll(_ request: JumpToHistoryRequest, succeeded: Bool) {
        guard navigationState.jumpToHistoryState.request == request else {
            return
        }

        if succeeded {
            logJumpToHistory(
                "Jump to history completed item=\(request.itemID.uuidString) generation=\(request.generation)"
            )

            navigationState = jumpNavigationController.completeJumpScroll(
                request, succeeded: true, state: navigationState)
            updatePresentationState { $0.jumpToHistoryState = navigationState.jumpToHistoryState }
            return
        }
        let previousState = navigationState.jumpToHistoryState
        navigationState = jumpNavigationController.completeJumpScroll(request, succeeded: false, state: navigationState)
        updatePresentationState { $0.jumpToHistoryState = navigationState.jumpToHistoryState }

        switch previousState {
        case .idle:
            return
        case .scrolling:
            logJumpToHistory(
                "Jump to history finished without verification item=\(request.itemID.uuidString) generation=\(request.generation)"
            )
        case .pending:
            if let retryRequest = navigationState.jumpToHistoryState.request {
                logJumpToHistory(
                    "Jump to history pending retry item=\(request.itemID.uuidString) attempt=\(navigationState.jumpToHistoryFailureCount)"
                )
                logJumpToHistory(
                    "Jump to history requested item=\(retryRequest.itemID.uuidString) generation=\(retryRequest.generation)"
                )
            } else {
                logJumpToHistory(
                    "Jump to history abandoned item=\(request.itemID.uuidString)"
                )
            }
        }
    }

    func performQuickPaste(at index: Int) -> ClipboardItem? {
        guard
            let item = quickPasteController.itemToPaste(
                at: index,
                in: filteredItems,
                settings: settingsManager
            )
        else { return nil }

        selectSingle(item.id)
        return item
    }

    func loadPreviewIfNeeded() async {
        // Search-index publication can legitimately resynchronize selection and
        // replace an in-flight detail task during startup.
        await store.waitForSearchIndex()
        while let task = searchTask {
            let generation = searchGeneration
            await task.value
            guard generation != searchGeneration else { break }
        }
        await keyboardDetailTask?.value
        await detailModel.waitUntilLoaded()
    }

    func extractSelectedImageText() async {
        await keyboardDetailTask?.value
        guard let item = selectedItem else { return }
        await extractImageText(for: item)
    }

    func extractImageText(for item: ClipboardItem) async {
        await keyboardDetailTask?.value
        do {
            try await detailModel.extractImageText(for: item)
        } catch {
            mutationFailure = HistoryMutationFailure(message: error.localizedDescription)
        }
    }

    func loadNextChunk() async {
        await keyboardDetailTask?.value
        await detailModel.loadNextChunk()
    }

    private func syncSelection(preferredID: UUID? = nil) {
        navigationState = jumpNavigationController.clearKeyboardScrollRequest(state: navigationState)
        selectionState = selectionController.syncSelection(
            state: selectionState,
            in: filteredItems,
            preferredID: preferredID,
            preferredTopSelectionID: preferredTopSelectionID(),
            validItemIDs: querySnapshot.validItemIDs,
            itemIndexByID: querySnapshot.itemIndexByID
        )
        applySelectionState()
    }

    private func performMutation(
        _ operation: @escaping @MainActor () async throws -> Void
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await operation()
            } catch {
                mutationFailure = HistoryMutationFailure(message: error.localizedDescription)
            }
        }
    }

    private func focusSingleMutationTargetIfNeeded(_ items: [ClipboardItem]) {
        guard items.count == 1, let item = items.first else { return }
        selectSingle(item.id)
    }

    private func preferredTopSelectionID() -> UUID? {
        sessionController.preferredTopSelectionID(
            in: filteredItems,
            historyWindowOpenBehavior: settingsManager.historyWindowOpenBehavior
        )
    }

    private func rebuildFilteredItems(preferredID: UUID? = nil) {
        scheduleQuery(preferredID: preferredID)
    }

    private func mutateFilterState(_ mutation: (inout HistoryFilterState) -> Void) {
        var nextState = filterState
        mutation(&nextState)
        guard nextState != filterState else { return }
        updateQueryConfiguration(preferredID: filteredItems.first?.id) {
            filterState = nextState
            queryFilters = nextState.clipboardFilters(
                now: nowProvider(),
                calendar: filterCalendar
            )
        }

    }

    private func clearQueryIfNeeded(shouldKeepQuery: Bool) {
        guard !shouldKeepQuery,
            !searchText.isEmpty || !filterState.isEmpty || !queryFilters.isEmpty
        else { return }
        updateQueryConfiguration(preferredID: filteredItems.first?.id) {
            filterState = HistoryFilterState()
            queryFilters = ClipboardFilters()
            searchText = ""
        }
    }

    private func refreshActiveDateFilter() {
        guard filterState.datePreset != .allDates else {
            scheduleQuery(preferredID: selectedID)
            return
        }
        let nextFilters = filterState.clipboardFilters(
            now: nowProvider(),
            calendar: filterCalendar
        )
        guard nextFilters != queryFilters else { return }
        updateQueryConfiguration(preferredID: filteredItems.first?.id) {
            queryFilters = nextFilters
        }
    }

    /// Applies related query mutations as one transaction.
    private func updateQueryConfiguration(
        preferredID: UUID?,
        _ update: () -> Void
    ) {
        precondition(!isApplyingQueryConfiguration)
        isApplyingQueryConfiguration = true
        update()
        isApplyingQueryConfiguration = false
        rebuildFilteredItems(preferredID: preferredID)
    }

    private func scheduleQuery(
        preferredID: UUID?,
        itemsSnapshot: [ClipboardItem]? = nil
    ) {
        searchGeneration &+= 1
        let generation = searchGeneration
        searchTask?.cancel()
        snippetTask?.cancel()
        snippetTask = nil
        store.interruptSearch()

        let query = activeQuery
        guard !query.normalizedText.isEmpty else {
            publishedSearchContext = nil
            // Empty/filter-only projections are asynchronous so the main actor
            // never builds a 10k-item cache.
            isSearching = true
            // @Published emits from willSet, so an items observer must use the
            // delivered value rather than reading the store's previous value.
            let currentItems = itemsSnapshot ?? store.items
            let historyRevision = store.currentHistoryRevision
            let selectedApplication = filterState.selectedApplication
            searchTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let prepared: PreparedHistoryQuerySnapshot
                do {
                    prepared = try await projectionCoordinator.projectLatest(
                        response: nil,
                        items: currentItems,
                        query: query,
                        queryGeneration: UInt64(generation),
                        historyRevision: historyRevision,
                        retaining: selectedApplication
                    )
                } catch {
                    return
                }
                guard !Task.isCancelled, generation == searchGeneration, query == activeQuery else {
                    return
                }
                applyPreparedProjection(prepared)
                syncSelection(preferredID: preferredID)
                if pendingMutationPreferredSelectionID == preferredID {
                    pendingMutationPreferredSelectionID = nil
                }
                isSearching = false
                searchTask = nil
            }
            return
        }

        isSearching = true
        searchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard !Task.isCancelled, generation == searchGeneration else { return }
            let response: ClipboardSearchResponse
            do {
                response = try await store.search(query, generation: generation)
            } catch is CancellationError {
                return
            } catch {
                guard generation == searchGeneration, query == activeQuery else { return }
                BufferLogger.persistence.error(
                    "Search execution failed: \(String(describing: error), privacy: .public)"
                )
                isSearching = false
                searchTask = nil
                return
            }
            guard !Task.isCancelled,
                response.session.queryGeneration == UInt64(searchGeneration),
                response.session.committedState.historyRevision == store.currentHistoryRevision,
                query == activeQuery
            else { return }

            do {
                let prepared = try await projectionCoordinator.projectLatest(
                    response: response,
                    items: store.items,
                    query: query,
                    queryGeneration: UInt64(generation),
                    historyRevision: response.session.committedState.historyRevision,
                    retaining: filterState.selectedApplication
                )
                guard !Task.isCancelled,
                    response.session.queryGeneration == UInt64(searchGeneration),
                    response.session.committedState.historyRevision == store.currentHistoryRevision,
                    query == activeQuery
                else { return }
                publishedSearchContext = PublishedSearchContext(session: response.session)
                applyPreparedProjection(prepared)
                syncSelection(preferredID: preferredID)
                if pendingMutationPreferredSelectionID == preferredID {
                    pendingMutationPreferredSelectionID = nil
                }
                isSearching = false
                searchTask = nil
                visibleSearchItemIDsChanged(
                    Array(prepared.querySnapshot.items.prefix(12).map(\.id))
                )
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func applyPreparedProjection(_ prepared: PreparedHistoryQuerySnapshot) {
        guard prepared.queryGeneration == UInt64(searchGeneration),
            prepared.historyRevision == store.currentHistoryRevision
        else { return }
        if let selectedApplication = filterState.selectedApplication,
            let refreshed = prepared.applicationFilterOptions.first(where: {
                $0.bundleIdentifier == selectedApplication.bundleIdentifier
            })
        {
            filterState.selectedApplication = refreshed
        }
        applicationFilterOptions = prepared.applicationFilterOptions
        publishQuerySnapshot(prepared.querySnapshot)
    }

    private func publishQuerySnapshot(_ snapshot: HistoryQuerySnapshot) {
        filteredItemByID = snapshot.itemByID
        filteredItemIndexByID = snapshot.itemIndexByID
        querySnapshot = HistoryQuerySnapshot(
            id: snapshot.id,
            renderRevision: querySnapshot.renderRevision &+ 1,
            query: snapshot.query,
            items: snapshot.items,
            hitByItemID: snapshot.hitByItemID,
            itemByID: snapshot.itemByID,
            itemIndexByID: snapshot.itemIndexByID,
            validItemIDs: snapshot.validItemIDs,
            displayCache: snapshot.displayCache
        )
    }

    func visibleSearchItemIDsChanged(_ itemIDs: [UUID]) {
        guard !activeQuery.normalizedText.isEmpty else { return }
        let missingItemIDs = itemIDs.prefix(50).compactMap { itemID -> UUID? in
            guard querySnapshot.hitByItemID[itemID]?.snippet == nil,
                querySnapshot.hitByItemID[itemID] != nil
            else { return nil }
            return itemID
        }
        guard !missingItemIDs.isEmpty, let context = publishedSearchContext else { return }
        snippetTask?.cancel()
        snippetTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let batch = try await store.snippets(
                    ClipboardSearchSnippetRequest(
                        session: context.session,
                        itemIDs: missingItemIDs
                    )
                )
                guard !Task.isCancelled,
                    batch.session == publishedSearchContext?.session,
                    batch.session.queryGeneration == UInt64(searchGeneration),
                    batch.session.committedState.historyRevision == store.currentHistoryRevision
                else { return }
                let snapshotID = querySnapshot.id
                let updatedSnapshot = await projectionCoordinator.applyingSnippets(
                    batch.snippetsByItemID,
                    to: querySnapshot
                )
                guard !Task.isCancelled,
                    snapshotID == querySnapshot.id,
                    batch.session == publishedSearchContext?.session,
                    batch.session.queryGeneration == UInt64(searchGeneration),
                    batch.session.committedState.historyRevision == store.currentHistoryRevision
                else { return }
                querySnapshot = updatedSnapshot
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func navigate(by delta: Int) {
        moveKeyboardSelection(to: selectedIndex + delta, extending: false)
    }

    private func moveKeyboardSelection(to targetIndex: Int, extending: Bool) {
        guard filteredItems.indices.contains(targetIndex) else { return }

        let item = filteredItems[targetIndex]
        let nextState =
            extending
            ? selectionController.extendSelection(
                to: item.id,
                targetIndex: targetIndex,
                in: filteredItems,
                state: selectionState
            )
            : selectionController.applySingleSelection(
                item.id,
                index: targetIndex,
                in: filteredItems,
                state: selectionState
            )

        publishKeyboardSelection(nextState, focusedIndex: targetIndex)
    }

    private func publishKeyboardSelection(
        _ nextState: HistorySelectionState,
        focusedIndex: Int
    ) {
        guard nextState != selectionState,
            filteredItems.indices.contains(focusedIndex),
            nextState.selectedID == filteredItems[focusedIndex].id
        else {
            return
        }

        let selectionToken = BufferPerformanceDiagnostics.begin(.keyboardSelection)
        selectionState = nextState

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectionViewState = selectionViewStateProjector.project(selectionState)
        }
        BufferPerformanceDiagnostics.end(selectionToken)

        let focusedItem = filteredItems[focusedIndex]
        navigationState = jumpNavigationController.makeKeyboardScrollRequest(
            itemID: focusedItem.id,
            targetIndex: focusedIndex,
            state: navigationState
        )
        if let request = navigationState.keyboardScrollRequest {
            keyboardScrollRouter.submit(request)
        }
        scheduleKeyboardDetailLoad(for: focusedItem.id)
    }

    private func logJumpToHistory(_ message: @autoclosure () -> String) {
        #if DEBUG
            let resolvedMessage = message()
            BufferLogger.ui.debug("\(resolvedMessage, privacy: .public)")
        #endif
    }

    private func applySelectionState() {
        selectionViewState = selectionViewStateProjector.project(selectionState)
        beginDetailLoad(
            selectedItem: selectedItem,
            selectedItemsInVisualOrder: selectedItemsInVisualOrder,
            selectedItemsInActionOrder: selectedItemsInActionOrder
        )
    }

    private func applyQuickPasteState() {
        updatePresentationState { $0.showsQuickPasteNumbers = quickPasteState.showsQuickPasteNumbers }
    }

    private func clearSelection() {
        selectionState = selectionController.clearSelection()
        applySelectionState()
    }

    private func refreshDetailViewState() {
        detailModel.update(
            HistoryDetailContext(
                selectedItem: selectedItem,
                selectedItemsInVisualOrder: selectedItemsInVisualOrder,
                selectedItemsInActionOrder: selectedItemsInActionOrder,
                isQueryActive: !activeQuery.isEmpty
            )
        )
    }

    private func beginDetailLoad(
        selectedItem: ClipboardItem?,
        selectedItemsInVisualOrder: [ClipboardItem],
        selectedItemsInActionOrder: [ClipboardItem]
    ) {
        detailModel.update(
            HistoryDetailContext(
                selectedItem: selectedItem,
                selectedItemsInVisualOrder: selectedItemsInVisualOrder,
                selectedItemsInActionOrder: selectedItemsInActionOrder,
                isQueryActive: !activeQuery.isEmpty
            )
        )
    }

    /// Detail projection can invalidate a large portion of the detail hierarchy.
    /// Coalescing it separately keeps repeated key events limited to selection and
    /// the imperative viewport update; only the latest selection starts detail work.
    private func scheduleKeyboardDetailLoad(for selectedItemID: UUID) {
        keyboardDetailTask?.cancel()
        keyboardDetailTask = Task { @MainActor [weak self] in
            // Key-repeat events arrive in separate run-loop turns. A short debounce
            // prevents each intermediate row from rebuilding the detail hierarchy.
            try? await Task.sleep(nanoseconds: 40_000_000)

            guard let self,
                !Task.isCancelled,
                selectionState.selectedID == selectedItemID,
                let selectedItem = filteredItemByID[selectedItemID]
            else { return }

            beginDetailLoad(
                selectedItem: selectedItem,
                selectedItemsInVisualOrder: selectionQuery.selectedItems,
                selectedItemsInActionOrder: selectionQuery.selectedItemsInActionOrder
            )
            keyboardDetailTask = nil
        }
    }

    private func updatePresentationState(_ update: (inout HistoryViewPresentationState) -> Void) {
        var nextState = presentationState
        update(&nextState)
        presentationState = nextState
    }
}
