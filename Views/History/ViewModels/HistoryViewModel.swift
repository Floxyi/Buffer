import AppKit
import Combine
import SwiftUI

@MainActor
final class HistoryViewModel: ObservableObject {
    typealias OpenListScrollRequest = HistoryOpenListScrollRequest
    typealias JumpToHistoryRequest = HistoryJumpToHistoryRequest
    typealias KeyboardNavigationRequest = HistoryKeyboardNavigationRequest
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
    private var previewImageTask: Task<Void, Never>?
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

    var keyboardNavigationRequest: KeyboardNavigationRequest? {
        presentationState.keyboardNavigationRequest
    }

    var scrollTrigger: Bool {
        get { presentationState.scrollTrigger }
        set { updatePresentationState { $0.scrollTrigger = newValue } }
    }

    var hoveredItemID: UUID? {
        get { presentationState.hoveredItemID }
        set { updatePresentationState { $0.hoveredItemID = newValue } }
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
        navigationState = jumpNavigationController.clearKeyboardNavigation(state: navigationState)
        updatePresentationState { $0.keyboardNavigationRequest = nil }
        selectionState = selectionController.applySingleSelection(id, in: filteredItems, state: selectionState)
        applySelectionState()
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
        navigationState = jumpNavigationController.clearKeyboardNavigation(state: navigationState)
        updatePresentationState { $0.keyboardNavigationRequest = nil }
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
        requestKeyboardNavigation(by: -1)
    }

    func navigateDown() {
        requestKeyboardNavigation(by: 1)
    }

    func jumpToFirstItem() {
        guard let firstItemID = filteredItems.first?.id else { return }

        scrollTrigger = true
        selectionState.selectedIndex = 0
        syncSelection(preferredID: firstItemID)
    }

    func jumpToLastItem() {
        guard let lastItemID = filteredItems.last?.id else { return }

        scrollTrigger = true
        selectionState.selectedIndex = filteredItems.count - 1
        syncSelection(preferredID: lastItemID)
    }

    func extendSelectionToFirstItem() {
        guard let firstItemID = filteredItems.first?.id else { return }

        scrollTrigger = true
        selectionState.selectionAnchor = selectionState.selectionAnchor ?? selectedID ?? firstItemID
        extendSelectionTo(firstItemID)
    }

    func extendSelectionToLastItem() {
        guard let lastItemID = filteredItems.last?.id else { return }

        scrollTrigger = true
        selectionState.selectionAnchor = selectionState.selectionAnchor ?? selectedID ?? lastItemID
        extendSelectionTo(lastItemID)
    }

    func extendSelectionUp() {
        guard selectedIndex > 0 else { return }

        scrollTrigger = true
        selectionState = selectionController.extendSelectionUp(in: filteredItems, state: selectionState)
        applySelectionState()
    }

    func extendSelectionDown() {
        guard selectedIndex < filteredItems.count - 1 else { return }

        scrollTrigger = true
        selectionState = selectionController.extendSelectionDown(in: filteredItems, state: selectionState)
        applySelectionState()
    }

    func togglePinForSelectedItem() {
        itemMutationController.togglePinForSelectedItems(
            selectedItemsInActionOrder,
            selectedID: selectedID,
            store: store,
            syncSelection: syncSelection(preferredID:)
        )
    }

    func deleteSelectedItem() {
        itemMutationController.deleteSelectedItems(
            selectedItemsInActionOrder,
            filteredItems: filteredItems,
            selectionController: selectionController,
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

    func completeKeyboardNavigation(_ request: KeyboardNavigationRequest) {
        guard presentationState.keyboardNavigationRequest == request else {
            return
        }

        navigationState = jumpNavigationController.clearKeyboardNavigation(state: navigationState)
        updatePresentationState { $0.keyboardNavigationRequest = nil }

        guard filteredItems[safe: request.targetIndex]?.id == request.itemID else {
            syncSelection(preferredID: request.itemID)
            return
        }

        withAnimation(.easeInOut(duration: 0.14)) {
            selectionState = selectionController.applySingleSelection(
                request.itemID,
                index: request.targetIndex,
                in: filteredItems,
                state: selectionState
            )
            applySelectionState()
        }
    }

    func setHoveredItemID(_ itemID: UUID?, isHovered: Bool) {
        updatePresentationState { $0.hoveredItemID = isHovered ? itemID : nil }
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
        previewImageTask?.cancel()
        updatePreviewState(previewStateController.reset())

        guard let item = selectedItem else { return }

        let initialState = previewStateController.loadPreview(
            for: item,
            store: store,
            previewLoader: previewLoader
        )
        updatePreviewState(initialState)

        guard item.kind == .image else { return }

        previewImageTask = Task { [weak self] in
            guard let self else { return }
            let image = await previewLoader.loadPreviewImage(for: item)
            guard !Task.isCancelled, self.selectedItem?.id == item.id else { return }
            var nextState = self.previewState
            nextState.previewImage = image
            self.updatePreviewState(nextState)
        }
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
        updatePreviewState(
            previewStateController.loadNextChunk(
                for: item,
                currentState: previewState,
                previewLoader: previewLoader
            ))
    }

    private func syncSelection(preferredID: UUID? = nil) {
        navigationState = jumpNavigationController.clearKeyboardNavigation(state: navigationState)
        updatePresentationState { $0.keyboardNavigationRequest = nil }
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

    private func requestKeyboardNavigation(by delta: Int) {
        if let pendingRequest = navigationState.keyboardNavigationRequest {
            completeKeyboardNavigation(pendingRequest)
        }

        navigationState = jumpNavigationController.requestKeyboardNavigation(
            by: delta,
            selectedIndex: selectedIndex,
            filteredItems: filteredItems,
            state: navigationState
        )
        updatePresentationState { $0.keyboardNavigationRequest = navigationState.keyboardNavigationRequest }
    }

    private func logJumpToHistory(_ message: @autoclosure () -> String) {
        #if DEBUG
            let resolvedMessage = message()
            BufferLogger.ui.debug("\(resolvedMessage, privacy: .public)")
        #endif
    }

    private func applySelectionState() {
        selectionViewState = selectionViewStateProjector.project(selectionState)
        refreshDetailViewState()
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
        detailViewState = detailViewStateProjector.project(
            selectedItem: selectedItem,
            selectedItemsInVisualOrder: selectedItemsInVisualOrder,
            selectedItemsInActionOrder: selectedItemsInActionOrder,
            searchText: searchText,
            previewState: previewState,
            store: store,
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
