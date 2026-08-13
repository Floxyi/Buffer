import AppKit
import Combine
import SwiftUI

@MainActor
final class HistoryViewModel: ObservableObject {
    typealias OpenListScrollRequest = HistoryOpenListScrollRequest
    typealias JumpToHistoryRequest = HistoryJumpToHistoryRequest
    typealias KeyboardScrollRequest = HistoryKeyboardScrollRequest
    typealias JumpToHistoryState = HistoryJumpToHistoryState

    @Published var searchText = "" {
        didSet {
            let searchChange = sessionController.handleSearchTextChange(state: sessionState)
            sessionState = searchChange.state

            guard searchChange.shouldRebuildFilteredItems else {
                refreshDetailViewState()
                return
            }

            rebuildFilteredItems(preferredID: filteredItems.first?.id)
        }
    }

    @Published private(set) var filteredItems: [ClipboardItem] = []
    @Published private var selectionViewState = HistorySelectionViewState()
    @Published private var previewState = HistoryPreviewState()
    @Published private var presentationState = HistoryViewPresentationState()
    @Published private(set) var detailViewState = HistoryDetailViewState()
    @Published private(set) var selectionNavigationToken = 0

    private let store: ClipboardStore
    private let settingsManager: SettingsManager
    private let ocrService: OCRServicing
    private let visibleItemsController = HistoryVisibleItemsController()
    private let selectionController = HistorySelectionController()
    private let quickPasteController = HistoryQuickPasteController()
    private let jumpNavigationController = HistoryJumpNavigationController()
    private let actionResolver = HistoryActionResolver()
    private let contextMenuController = HistoryContextMenuController()
    private let itemMutationController = HistoryItemMutationController()
    private let previewStateController = HistoryPreviewStateController()
    private let sessionController = HistorySessionController()
    private let selectionViewStateProjector = HistorySelectionViewStateProjector()
    private let detailViewStateProjector = HistoryDetailViewStateProjector()
    private let copiedAtFormatter = HistoryCopiedAtFormatter()

    private lazy var previewLoader = HistoryPreviewLoader(store: store, ocrService: ocrService)
    private var selectionState = HistorySelectionState()
    private var sessionState = HistorySessionState()
    private var quickPasteState = HistoryQuickPasteState()
    private var navigationState = HistoryNavigationState()
    private var cancellables: Set<AnyCancellable> = []
    private var detailLoadTask: Task<Void, Never>?
    private var detailLoadGeneration: UInt = 0
    private var detailTotalSizeBytes: Int?
    private var activeOCRItemID: UUID?
    private var activeOCRGeneration: UInt = 0
    private var activeOCRTask: Task<String?, Never>?

    init(store: ClipboardStore, settingsManager: SettingsManager, ocrService: OCRServicing) {
        self.store = store
        self.settingsManager = settingsManager
        self.ocrService = ocrService

        filteredItems = visibleItemsController.initialFilteredItems(from: store.items, store: store)
        syncSelection()

        store.$items
            .sink { [weak self] items in
                guard let self else { return }
                let update = self.visibleItemsController.handleStoreItemsChange(
                    items: items,
                    searchText: self.searchText,
                    store: store,
                    sessionState: self.sessionState
                )
                self.filteredItems = update.filteredItems
                self.sessionState = update.sessionState
                self.syncSelection(preferredID: update.preferredSelectionID)
            }
            .store(in: &cancellables)
    }

    private var selectionQuery: HistorySelectionQuery {
        HistorySelectionQuery(
            filteredItems: filteredItems,
            selectedIDs: selectionViewState.selectedIDs,
            selectedActionOrderIDs: selectionViewState.selectedActionOrderIDs,
            selectedID: selectionViewState.selectedID,
            searchText: searchText,
            totalItemCount: store.items.count
        )
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
        presentationState.keyboardScrollRequest
    }

    var scrollTrigger: Bool {
        get { presentationState.scrollTrigger }
        set { updatePresentationState { $0.scrollTrigger = newValue } }
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
        updatePresentationState { $0.keyboardScrollRequest = nil }
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
        updatePresentationState { $0.keyboardScrollRequest = nil }
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
        itemMutationController.togglePinForSelectedItems(
            selectedItemsInActionOrder,
            selectedID: selectedID,
            store: store,
            syncSelection: syncSelection(preferredID:)
        )
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
        itemMutationController.delete(
            request,
            store: store,
            setPendingPreferredSelectionID: { [weak self] in
                guard let self else { return }
                self.sessionState = self.sessionController.setPendingPreferredSelectionID($0, state: self.sessionState)
            }
        )
    }

    func togglePin(for item: ClipboardItem) {
        itemMutationController.togglePin(
            for: item,
            selectSingle: selectSingle(_:),
            store: store,
            syncSelection: syncSelection(preferredID:)
        )
    }

    func delete(_ item: ClipboardItem) {
        itemMutationController.delete(
            item,
            filteredItems: filteredItems,
            selectionController: selectionController,
            selectSingle: selectSingle(_:),
            store: store,
            setPendingPreferredSelectionID: { [weak self] in
                guard let self else { return }
                self.sessionState = self.sessionController.setPendingPreferredSelectionID($0, state: self.sessionState)
            }
        )
    }

    func contextMenuTargetItems(for clickedItemID: UUID) -> [ClipboardItem] {
        contextMenuController.targetItems(
            for: clickedItemID,
            filteredItems: filteredItems,
            selectedIDs: selectedIDs,
            selectedItemsInActionOrder: selectedItemsInActionOrder
        )
    }

    func visualContextMenuTargetItems(for clickedItemID: UUID) -> [ClipboardItem] {
        contextMenuController.visualTargetItems(
            for: clickedItemID,
            filteredItems: filteredItems,
            selectedIDs: selectedIDs,
            selectedItemsInActionOrder: selectedItemsInActionOrder
        )
    }

    func contextMenuActions(for clickedItemID: UUID) -> [HistoryItemActionDescriptor] {
        contextMenuController.actions(
            for: clickedItemID,
            filteredItems: filteredItems,
            selectedIDs: selectedIDs,
            selectedItemsInActionOrder: selectedItemsInActionOrder,
            searchText: searchText,
            isExtractingText: detailViewState.isExtractingText,
            actionResolver: actionResolver
        )
    }

    func shouldShowUnpinForContextMenuTarget(_ clickedItemID: UUID) -> Bool {
        contextMenuController.shouldShowUnpin(
            for: clickedItemID,
            filteredItems: filteredItems,
            selectedIDs: selectedIDs,
            selectedItemsInActionOrder: selectedItemsInActionOrder
        )
    }

    func deleteContextMenuTarget(_ clickedItemID: UUID) {
        itemMutationController.deleteContextMenuTarget(
            contextMenuTargetItems(for: clickedItemID),
            filteredItems: filteredItems,
            selectionController: selectionController,
            store: store,
            setPendingPreferredSelectionID: { [weak self] in
                guard let self else { return }
                self.sessionState = self.sessionController.setPendingPreferredSelectionID($0, state: self.sessionState)
            }
        )
    }

    func togglePinForContextMenuTarget(_ clickedItemID: UUID) {
        itemMutationController.togglePinForContextMenuTarget(
            contextMenuTargetItems(for: clickedItemID),
            clickedItemID: clickedItemID,
            selectedIDs: selectedIDs,
            selectedID: selectedID,
            store: store,
            syncSelection: syncSelection(preferredID:)
        )
    }

    func jumpToHistory(for item: ClipboardItem) {
        let targetID = item.id
        navigationState = jumpNavigationController.beginJump(to: targetID, state: navigationState)
        updatePresentationState { $0.jumpToHistoryState = navigationState.jumpToHistoryState }

        logJumpToHistory(
            "Jump to history requested item=\(targetID.uuidString) generation=\(navigationState.jumpToHistoryState.request?.generation ?? 0)"
        )

        let jumpPlan = sessionController.makeJumpToHistoryPlan(
            for: targetID,
            currentSearchText: searchText,
            state: sessionState
        )
        sessionState = jumpPlan.state

        if let nextSearchText = jumpPlan.searchText {
            searchText = nextSearchText
        }

        if jumpPlan.shouldRebuildFilteredItems {
            rebuildFilteredItems(preferredID: jumpPlan.preferredSelectionID)
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
        await detailLoadTask?.value
    }

    func extractSelectedImageText() async {
        guard let item = selectedItem else { return }
        await extractImageText(for: item)
    }

    func extractImageText(for item: ClipboardItem) async {
        guard activeOCRItemID != item.id else { return }

        cancelActiveOCRExtraction()
        activeOCRItemID = item.id
        activeOCRGeneration &+= 1
        let generation = activeOCRGeneration
        updatePreviewState(previewStateController.beginExtracting(state: previewState))

        let task = Task { [previewLoader] in
            await previewLoader.extractImageText(
                for: item,
                previewImage: selectedItem?.id == item.id ? detailViewState.previewImage : nil
            )
        }
        activeOCRTask = task
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }

        guard activeOCRGeneration == generation, activeOCRItemID == item.id else {
            return
        }

        if !task.isCancelled, let result {
            store.setOCRText(result.isEmpty ? "No text found in this image." : result, for: item)
        }

        updatePreviewState(previewStateController.finishExtracting(state: previewState))
        activeOCRItemID = nil
        activeOCRTask = nil
    }

    func loadNextChunk() async {
        guard let item = selectedItem else { return }
        let generation = detailLoadGeneration
        let nextState = await previewStateController.loadNextChunk(
            for: item,
            currentState: previewState,
            previewLoader: previewLoader
        )
        guard generation == detailLoadGeneration, selectedID == item.id else { return }
        updatePreviewState(nextState)
    }

    private func syncSelection(preferredID: UUID? = nil) {
        navigationState = jumpNavigationController.clearKeyboardScrollRequest(state: navigationState)
        updatePresentationState { $0.keyboardScrollRequest = nil }
        selectionState = selectionController.syncSelection(
            state: selectionState,
            in: filteredItems,
            preferredID: preferredID,
            preferredTopSelectionID: preferredTopSelectionID()
        )
        applySelectionState()

        if let activeOCRItemID, activeOCRItemID != selectedID {
            cancelActiveOCRExtraction()
        }
    }

    private func cancelActiveOCRExtraction() {
        guard activeOCRItemID != nil || activeOCRTask != nil else {
            return
        }

        activeOCRGeneration &+= 1
        activeOCRTask?.cancel()
        activeOCRTask = nil
        activeOCRItemID = nil
        updatePreviewState(previewStateController.finishExtracting(state: previewState))
    }

    private func preferredTopSelectionID() -> UUID? {
        sessionController.preferredTopSelectionID(
            in: filteredItems,
            historyWindowOpenBehavior: settingsManager.historyWindowOpenBehavior
        )
    }

    private func rebuildFilteredItems(preferredID: UUID? = nil) {
        filteredItems = visibleItemsController.rebuildFilteredItems(
            from: store.items,
            searchText: searchText,
            store: store
        )
        syncSelection(preferredID: preferredID)
    }

    private func navigate(by delta: Int) {
        moveKeyboardSelection(to: selectedIndex + delta, extending: false)
    }

    private func moveKeyboardSelection(to targetIndex: Int, extending: Bool) {
        guard filteredItems.indices.contains(targetIndex) else { return }

        let item = filteredItems[targetIndex]
        let nextState = extending
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
              nextState.selectedID == filteredItems[focusedIndex].id else {
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
        updatePresentationState { $0.keyboardScrollRequest = navigationState.keyboardScrollRequest }
        beginDetailLoad(
            selectedItem: focusedItem,
            selectedItemsInVisualOrder: selectedItemsInVisualOrder,
            selectedItemsInActionOrder: selectedItemsInActionOrder
        )
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

    private func updatePreviewState(_ nextState: HistoryPreviewState) {
        previewState = nextState
        refreshDetailViewState()
    }

    private func refreshDetailViewState() {
        publishDetailViewState(
            selectedItem: selectedItem,
            selectedItemsInVisualOrder: selectedItemsInVisualOrder,
            selectedItemsInActionOrder: selectedItemsInActionOrder
        )
    }

    private func beginDetailLoad(
        selectedItem: ClipboardItem?,
        selectedItemsInVisualOrder: [ClipboardItem],
        selectedItemsInActionOrder: [ClipboardItem]
    ) {
        detailLoadGeneration &+= 1
        let generation = detailLoadGeneration
        detailLoadTask?.cancel()
        detailLoadTask = nil

        guard let selectedItem else {
            detailTotalSizeBytes = nil
            previewState = previewStateController.reset()
            publishDetailViewState(
                selectedItem: nil,
                selectedItemsInVisualOrder: selectedItemsInVisualOrder,
                selectedItemsInActionOrder: selectedItemsInActionOrder
            )
            return
        }

        detailTotalSizeBytes = immediateTotalSizeBytes(for: selectedItemsInVisualOrder)
        let cachedPreviewImage =
            ClipboardItemTypeRegistry.supportsImageAssets(for: selectedItem)
            ? ClipboardImageAssetLoader.cachedPreviewImage(for: selectedItem)
            : nil
        previewState = previewStateController.immediatePreview(
            for: selectedItem,
            cachedPreviewImage: cachedPreviewImage
        )
        publishDetailViewState(
            selectedItem: selectedItem,
            selectedItemsInVisualOrder: selectedItemsInVisualOrder,
            selectedItemsInActionOrder: selectedItemsInActionOrder
        )

        let previewLoader = previewLoader
        detailLoadTask = Task { [weak self, store] in
            guard let self,
                !Task.isCancelled,
                self.detailLoadGeneration == generation
            else {
                return
            }

            var loadedPreviewState = self.previewState

            var totalSize = 0

            for item in selectedItemsInVisualOrder {
                guard !Task.isCancelled else { return }
                totalSize += await store.itemSizeAsync(for: item) ?? 0
            }

            if selectedItem.isFileBacked {
                loadedPreviewState.chunkedText = await previewLoader.loadInitialChunk(for: selectedItem)
            } else if selectedItem.kind == .image, loadedPreviewState.previewImage == nil {
                loadedPreviewState.previewImage = await previewLoader.loadPreviewImage(for: selectedItem)
            }

            guard !Task.isCancelled,
                self.detailLoadGeneration == generation,
                self.selectedID == selectedItem.id
            else {
                return
            }

            self.previewState = loadedPreviewState
            self.detailTotalSizeBytes = totalSize
            self.publishDetailViewState(
                selectedItem: selectedItem,
                selectedItemsInVisualOrder: selectedItemsInVisualOrder,
                selectedItemsInActionOrder: selectedItemsInActionOrder
            )
            self.detailLoadTask = nil
        }
    }

    private func immediateTotalSizeBytes(for items: [ClipboardItem]) -> Int? {
        var totalSize = 0
        for item in items {
            let itemSize: Int?
            if let originalSizeBytes = item.originalSizeBytes {
                itemSize = originalSizeBytes
            } else {
                switch item.content {
                case .text(let payload) where payload.fileName == nil:
                    itemSize = payload.inlineText?.utf8.count
                case .color(let payload):
                    itemSize = payload.originalText.utf8.count
                case .link(let payload):
                    itemSize = payload.originalText.utf8.count
                case .email(let payload):
                    itemSize = payload.originalText.utf8.count
                case .text, .image:
                    itemSize = nil
                }
            }

            guard let itemSize else { return nil }
            totalSize += itemSize
        }
        return totalSize
    }

    private func publishDetailViewState(
        selectedItem: ClipboardItem?,
        selectedItemsInVisualOrder: [ClipboardItem],
        selectedItemsInActionOrder: [ClipboardItem]
    ) {
        detailViewState = detailViewStateProjector.project(
            selectedItem: selectedItem,
            selectedItemsInVisualOrder: selectedItemsInVisualOrder,
            selectedItemsInActionOrder: selectedItemsInActionOrder,
            searchText: searchText,
            previewState: previewState,
            selectedItemsTotalSizeBytes: detailTotalSizeBytes,
            actionResolver: actionResolver,
            copiedAtFormatter: copiedAtFormatter
        )
    }

    private func updatePresentationState(_ update: (inout HistoryViewPresentationState) -> Void) {
        var nextState = presentationState
        update(&nextState)
        presentationState = nextState
    }
}
