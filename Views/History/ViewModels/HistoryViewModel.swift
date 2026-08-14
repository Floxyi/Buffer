import AppKit
import Combine
import SwiftUI

@MainActor
final class HistoryViewModel: ObservableObject {
    typealias OpenListScrollRequest = HistoryOpenListScrollRequest
    typealias JumpToHistoryRequest = HistoryJumpToHistoryRequest
    typealias KeyboardScrollRequest = HistoryKeyboardScrollRequest
    typealias JumpToHistoryState = HistoryJumpToHistoryState

    var searchText: String {
        get { searchTextValue }
        set {
            guard newValue != searchTextValue else { return }
            searchTextValue = newValue
            guard !isApplyingQueryConfiguration else { return }
            rebuildFilteredItems(preferredID: filteredItems.first?.id)
        }
    }

    @Published private var querySnapshot = HistoryQuerySnapshot()
    @Published private var selectionViewState = HistorySelectionViewState()
    @Published private var presentationState = HistoryViewPresentationState()
    @Published private(set) var detailViewState = HistoryDetailViewState()
    @Published var mutationFailure: HistoryMutationFailure?

    private let store: ClipboardStore
    private let settingsManager: SettingsManager
    private let queryModel = HistoryQueryModel()
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
    private var selectionState = HistorySelectionState()
    private var quickPasteState = HistoryQuickPasteState()
    private var navigationState = HistoryNavigationState()
    private var cancellables: Set<AnyCancellable> = []
    private var queryFilters = ClipboardFilters()
    private var includesOCRTextInSearch = true
    private var isApplyingQueryConfiguration = false
    private var searchTextValue = ""
    private var filteredItemByID: [UUID: ClipboardItem] = [:]
    private var filteredItemIndexByID: [UUID: Int] = [:]
    private var keyboardDetailTask: Task<Void, Never>?

    init(
        store: ClipboardStore,
        settingsManager: SettingsManager,
        ocrService: OCRServicing,
        assetProvider: (any ClipboardItemAssetProviding)? = nil,
        keyboardScrollRouter: HistoryKeyboardScrollRouter = HistoryKeyboardScrollRouter()
    ) {
        self.store = store
        self.settingsManager = settingsManager
        let resolvedAssetProvider =
            assetProvider ?? ClipboardItemAssetProvider(store: store, settings: settingsManager)
        self.detailModel = HistoryDetailModel(
            store: store,
            assetProvider: resolvedAssetProvider,
            ocrService: ocrService
        )
        self.keyboardScrollRouter = keyboardScrollRouter

        let initialQuerySnapshot = queryModel.evaluate(
            items: store.items,
            query: ClipboardQuery(),
            searchIndex: store.searchIndexSnapshot
        )
        publishQuerySnapshot(initialQuerySnapshot)
        syncSelection()

        store.$items
            .sink { [weak self] items in
                guard let self else { return }
                if self.activeQuery.isEmpty || self.store.isSearchIndexReady {
                    self.applyQuery(to: items)
                } else {
                    self.reconcilePendingIndexedItems(items)
                }
                self.syncSelection()
            }
            .store(in: &cancellables)

        store.$searchIndexState
            .sink { [weak self] searchIndexState in
                guard let self else { return }
                guard searchIndexState.isReady else { return }
                let preferredID = self.selectedID
                self.applyQuery(to: self.store.items, searchIndex: searchIndexState.index)
                self.syncSelection(preferredID: preferredID)
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
        querySnapshot.revision
    }

    var filteredItemsSnapshotID: UUID {
        querySnapshot.id
    }

    var searchResultsByItemID: [UUID: ClipboardSearchResult] {
        querySnapshot.resultsByItemID
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

    func setFilters(_ filters: ClipboardFilters) {
        guard queryFilters != filters else { return }
        updateQueryConfiguration(preferredID: filteredItems.first?.id) {
            queryFilters = filters
        }
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
        if let clearedSearchText = sessionController.clearedSearchText(
            currentSearchText: searchText,
            shouldKeepSearchText: settingsManager.keepSearchTextAfterPaste
        ) {
            searchText = clearedSearchText
        }
    }

    func clearSearchAfterClosingIfNeeded() {
        if let clearedSearchText = sessionController.clearedSearchText(
            currentSearchText: searchText,
            shouldKeepSearchText: settingsManager.keepSearchTextAfterClosing
        ) {
            searchText = clearedSearchText
        }
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
        performMutation { [self] in
            let preferredID = try await itemMutationController.delete(request, store: store)
            syncSelection(preferredID: preferredID)
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
            isExtractingText: detailViewState.isExtractingText,
            actionResolver: actionResolver
        )
    }

    func dismissMutationFailure() {
        mutationFailure = nil
    }

    func jumpToHistory(for item: ClipboardItem) {
        let targetID = item.id
        let hadActiveFilters = !queryFilters.isEmpty
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
            preferredTopSelectionID: preferredTopSelectionID()
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
        applyQuery(to: store.items)
        syncSelection(preferredID: preferredID)
    }

    /// Applies related query mutations as one transaction. User-entered search
    /// text never passes through this path, so every editor change immediately
    /// publishes a matching list snapshot.
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

    private func applyQuery(
        to items: [ClipboardItem],
        searchIndex: ClipboardSearchIndex? = nil
    ) {
        let snapshot = queryModel.evaluate(
            items: items,
            query: activeQuery,
            searchIndex: searchIndex ?? store.searchIndexSnapshot
        )
        publishQuerySnapshot(snapshot)
    }

    private func publishQuerySnapshot(_ snapshot: HistoryQuerySnapshot) {
        var nextSnapshot = snapshot
        nextSnapshot.revision = querySnapshot.revision &+ 1
        filteredItemByID = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) })
        filteredItemIndexByID = Dictionary(
            uniqueKeysWithValues: snapshot.items.enumerated().map { ($1.id, $0) }
        )
        querySnapshot = nextSnapshot
    }

    /// Keeps the currently proven search result set stable while a replacement
    /// index is being built. Removed items disappear immediately and updated
    /// values are refreshed, while newly matching items arrive with the index.
    private func reconcilePendingIndexedItems(_ items: [ClipboardItem]) {
        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let reconciledItems = filteredItems.compactMap { itemByID[$0.id] }
        let reconciledIDs = Set(reconciledItems.map(\.id))

        publishQuerySnapshot(
            HistoryQuerySnapshot(
                query: activeQuery,
                items: reconciledItems,
                resultsByItemID: searchResultsByItemID.filter { reconciledIDs.contains($0.key) }
            )
        )
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
