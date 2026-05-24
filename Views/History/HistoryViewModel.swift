import AppKit
import Combine
import SwiftUI

@MainActor
final class HistoryViewModel: ObservableObject {
    struct OpenListScrollRequest: Equatable {
        enum Mode: Equatable {
            case scrollToTop
            case scrollToItem(UUID)
        }

        let mode: Mode
    }

    struct JumpToHistoryRequest: Equatable {
        let itemID: UUID
        let generation: UInt
    }

    struct KeyboardNavigationRequest: Equatable {
        let itemID: UUID
        let targetIndex: Int
        let generation: UInt
    }

    enum JumpToHistoryState: Equatable {
        case idle
        case pending(JumpToHistoryRequest)
        case scrolling(JumpToHistoryRequest)

        var request: JumpToHistoryRequest? {
            switch self {
            case .idle:
                return nil
            case .pending(let request), .scrolling(let request):
                return request
            }
        }

        var itemID: UUID? {
            request?.itemID
        }
    }

    @Published var searchText = "" {
        didSet {
            guard !isApplyingProgrammaticSearchChange else {
                isApplyingProgrammaticSearchChange = false
                return
            }

            rebuildFilteredItems(preferredID: filteredItems.first?.id)
        }
    }

    @Published private(set) var filteredItems: [ClipboardItem] = []
    @Published private(set) var selectedIDs: Set<UUID> = []
    @Published private(set) var selectedActionOrderIDs: [UUID] = []
    @Published private(set) var selectedIndex = 0
    @Published private(set) var selectedID: UUID?
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var chunkedText = ChunkedTextState()
    @Published private(set) var isExtractingText = false
    @Published private(set) var showsQuickPasteNumbers = false
    @Published private(set) var windowOpenToken = 0
    @Published private(set) var shouldFocusSearchOnOpen = true
    @Published private(set) var searchSelectionToken = 0
    @Published private(set) var selectionNavigationToken = 0
    @Published private(set) var openListScrollRequest = OpenListScrollRequest(mode: .scrollToTop)
    @Published private(set) var openListScrollRequestToken = 0
    @Published private(set) var jumpToHistoryState = JumpToHistoryState.idle
    @Published private(set) var keyboardNavigationRequest: KeyboardNavigationRequest?

    @Published var scrollTrigger = false
    @Published var hoveredItemID: UUID?

    private let store: ClipboardStore
    private let settingsManager: SettingsManager
    private let ocrService: OCRServicing

    private var selectionAnchor: UUID?
    private var quickPasteNeedsModifierReset = false
    private var isApplyingProgrammaticSearchChange = false
    private var pendingPreferredSelectionID: UUID?
    private var cancellables: Set<AnyCancellable> = []

    private var jumpToHistoryGenerationCounter: UInt = 0
    private var jumpToHistoryFailureCount = 0
    private let maxJumpToHistoryRetryCount = 2
    private var keyboardNavigationGenerationCounter: UInt = 0

    private static let copiedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, d. MMMM yyyy, 'at' HH:mm"
        return formatter
    }()

    init(store: ClipboardStore, settingsManager: SettingsManager, ocrService: OCRServicing) {
        self.store = store
        self.settingsManager = settingsManager
        self.ocrService = ocrService

        filteredItems = Self.makeFilteredItems(from: store.items, query: "", store: store)
        syncSelection()

        store.$items
            .sink { [weak self] items in
                guard let self else { return }
                self.filteredItems = Self.makeFilteredItems(from: items, query: self.searchText, store: store)
                self.syncSelection(preferredID: self.consumePendingPreferredSelectionID())
            }
            .store(in: &cancellables)
    }

    var selectedItem: ClipboardItem? {
        guard let selectedID else { return nil }
        return filteredItems.first(where: { $0.id == selectedID })
    }

    var selectedItems: [ClipboardItem] {
        filteredItems.filter { selectedIDs.contains($0.id) }
    }

    var selectedItemsInVisualOrder: [ClipboardItem] {
        selectedItems
    }

    var selectedItemsInActionOrder: [ClipboardItem] {
        let itemsByID = Dictionary(uniqueKeysWithValues: filteredItems.map { ($0.id, $0) })
        return selectedActionOrderIDs.compactMap { id in
            guard selectedIDs.contains(id) else { return nil }
            return itemsByID[id]
        }
    }

    var selectionCount: Int {
        selectedIDs.count
    }

    var selectedItemsTotalSizeText: String {
        AppFormatting.formattedByteCount(selectedItems.reduce(0) { $0 + (store.itemSize(for: $1) ?? 0) })
    }

    var isSingleImageSelection: Bool {
        selectionCount <= 1 && ClipboardItemTypeRegistry.canSaveImage(for: selectedItem)
    }

    var canSaveSelectedImage: Bool {
        isSingleImageSelection
    }

    var canExtractSelectedImageText: Bool {
        selectionCount <= 1
            && ClipboardItemTypeRegistry.canExtractImageText(for: selectedItem)
            && selectedItem?.ocrText == nil
            && !isExtractingText
    }

    var selectedItemIsPinned: Bool {
        let targets = selectionCount > 1 ? selectedItemsInActionOrder : selectedItem.map { [$0] } ?? []
        guard !targets.isEmpty else { return false }
        return targets.allSatisfy(\.isPinned)
    }

    var canJumpToHistorySelection: Bool {
        selectionCount == 1 && selectedItem != nil && !searchText.isEmpty
    }

    var detailActions: [HistoryItemActionDescriptor] {
        resolvedActions(
            for: selectedItemsInActionOrder.isEmpty ? selectedItem.map { [$0] } ?? [] : selectedItemsInActionOrder,
            allowsJumpToHistory: canJumpToHistorySelection,
            isExtractingText: isExtractingText
        )
    }

    var textSelectionCount: Int {
        selectedItems.filter { $0.kind == .text }.count
    }

    var imageSelectionCount: Int {
        selectedItems.filter { $0.kind == .image }.count
    }

    var colorSelectionCount: Int {
        selectedItems.filter { $0.kind == .color }.count
    }

    var linkSelectionCount: Int {
        selectedItems.filter { $0.kind == .link }.count
    }

    var firstTextPreview: String? {
        selectedItems.first(where: { $0.kind == .text || $0.kind == .color || $0.kind == .link }).map {
            String(ClipboardItemTypeRegistry.previewText(for: $0).prefix(200))
        }
    }

    var selectedItemSourceName: String? {
        selectedItem?.sourceAppDisplayName
    }

    var selectedItemCopiedAtText: String? {
        guard let timestamp = selectedItem?.timestamp else { return nil }
        return Self.copiedAtText(for: timestamp)
    }

    var activeJumpToHistoryRequest: JumpToHistoryRequest? {
        jumpToHistoryState.request
    }

    var isShowingFullHistory: Bool {
        searchText.isEmpty && filteredItems.count == store.items.count
    }

    static func copiedAtText(for timestamp: Date) -> String {
        copiedAtFormatter.string(from: timestamp)
    }

    var quickPasteBadgeNumberByItemID: [UUID: Int] {
        guard settingsManager.quickPasteEnabled else { return [:] }

        var result: [UUID: Int] = [:]
        for (index, item) in quickPasteAddressableItems.enumerated() {
            result[item.id] = quickPasteBadgeNumber(for: index)
        }
        return result
    }

    func handleWindowOpen(
        focusSearch: Bool,
        suppressQuickPasteUntilModifiersReleased: Bool
    ) {
        if !searchText.isEmpty {
            searchSelectionToken &+= 1
        }

        shouldFocusSearchOnOpen = focusSearch
        prepareQuickPasteForWindowOpen(
            using: NSEvent.modifierFlags,
            forceModifierReset: suppressQuickPasteUntilModifiersReleased
        )

        if settingsManager.historyWindowOpenBehavior == .keepLastSelection {
            if selectedIDs.isEmpty {
                syncSelection(preferredID: selectedID ?? preferredTopSelectionID())
            } else {
                syncSelection()
            }
        } else {
            syncSelection(preferredID: preferredTopSelectionID())
            openListScrollRequest = OpenListScrollRequest(mode: .scrollToTop)
            openListScrollRequestToken &+= 1
        }

        windowOpenToken += 1
    }

    func prepareQuickPasteForWindowOpen(
        using flags: NSEvent.ModifierFlags,
        forceModifierReset: Bool = false
    ) {
        quickPasteNeedsModifierReset = forceModifierReset || !quickPasteRelevantFlags(from: flags).isEmpty
        showsQuickPasteNumbers = false
    }

    func handleQuickPasteModifierFlagsChange(_ flags: NSEvent.ModifierFlags) {
        let relevantFlags = quickPasteRelevantFlags(from: flags)

        if quickPasteNeedsModifierReset {
            if relevantFlags.isEmpty {
                quickPasteNeedsModifierReset = false
            }

            showsQuickPasteNumbers = false
            return
        }

        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
            showsQuickPasteNumbers = settingsManager.quickPasteEnabled && relevantFlags == .command
        }
    }

    func handleAppResignActive() {
        showsQuickPasteNumbers = false
        quickPasteNeedsModifierReset = false
    }

    func clearSearchAfterCommittedAction() {
        guard !settingsManager.keepSearchTextAfterPaste else { return }
        guard !searchText.isEmpty else { return }

        searchText = ""
    }

    func clearSearchAfterClosingIfNeeded() {
        guard !settingsManager.keepSearchTextAfterClosing else { return }
        guard !searchText.isEmpty else { return }

        searchText = ""
    }

    func selectSingle(_ id: UUID) {
        keyboardNavigationRequest = nil
        applySingleSelection(id)
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
        keyboardNavigationRequest = nil
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
            selectedActionOrderIDs.removeAll { $0 == id }
        } else {
            selectedIDs.insert(id)
            selectedActionOrderIDs.append(id)
        }

        selectionAnchor = id

        if let index = filteredItems.firstIndex(where: { $0.id == id }) {
            selectedIndex = index
            if selectedIDs.contains(id) {
                selectedID = id
            } else {
                selectedID = nearestSelectedID(around: index)
            }
        }

        if selectedIDs.isEmpty {
            selectionAnchor = nil
        }
    }

    func extendSelectionTo(_ targetID: UUID) {
        guard let anchorID = selectionAnchor else {
            selectSingle(targetID)
            return
        }

        guard let anchorIndex = filteredItems.firstIndex(where: { $0.id == anchorID }),
              let targetIndex = filteredItems.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        let direction = targetIndex >= anchorIndex ? 1 : -1
        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        let rangeIDs = Set(filteredItems[range].map(\.id))
        let previousSelection = selectedIDs

        selectedIDs = rangeIDs
        selectedActionOrderIDs.removeAll { !rangeIDs.contains($0) }

        let steppedIndices = stride(from: anchorIndex, through: targetIndex, by: direction)
        for index in steppedIndices {
            let id = filteredItems[index].id
            if !previousSelection.contains(id) && !selectedActionOrderIDs.contains(id) {
                selectedActionOrderIDs.append(id)
            }
        }

        selectedIndex = targetIndex
        selectedID = targetID
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
        selectedIndex = 0
        syncSelection(preferredID: firstItemID)
    }

    func jumpToLastItem() {
        guard let lastItemID = filteredItems.last?.id else { return }

        scrollTrigger = true
        selectedIndex = filteredItems.count - 1
        syncSelection(preferredID: lastItemID)
    }

    func extendSelectionToFirstItem() {
        guard let firstItemID = filteredItems.first?.id else { return }

        scrollTrigger = true
        selectionAnchor = selectionAnchor ?? selectedID ?? firstItemID
        extendSelectionTo(firstItemID)
    }

    func extendSelectionToLastItem() {
        guard let lastItemID = filteredItems.last?.id else { return }

        scrollTrigger = true
        selectionAnchor = selectionAnchor ?? selectedID ?? lastItemID
        extendSelectionTo(lastItemID)
    }

    func extendSelectionUp() {
        guard selectedIndex > 0 else { return }

        scrollTrigger = true

        let currentItem = filteredItems[selectedIndex]
        let previousIndex = selectedIndex - 1
        let previousItem = filteredItems[previousIndex]

        if selectedIDs.isEmpty {
            selectSingle(currentItem.id)
            return
        }

        selectedIDs.insert(previousItem.id)
        if !selectedActionOrderIDs.contains(previousItem.id) {
            selectedActionOrderIDs.append(previousItem.id)
        }
        selectionAnchor = selectionAnchor ?? currentItem.id
        selectedIndex = previousIndex
        selectedID = previousItem.id
    }

    func extendSelectionDown() {
        guard selectedIndex < filteredItems.count - 1 else { return }

        scrollTrigger = true

        let currentItem = filteredItems[selectedIndex]
        let nextIndex = selectedIndex + 1
        let nextItem = filteredItems[nextIndex]

        if selectedIDs.isEmpty {
            selectSingle(currentItem.id)
            return
        }

        selectedIDs.insert(nextItem.id)
        if !selectedActionOrderIDs.contains(nextItem.id) {
            selectedActionOrderIDs.append(nextItem.id)
        }
        selectionAnchor = selectionAnchor ?? currentItem.id
        selectedIndex = nextIndex
        selectedID = nextItem.id
    }

    func togglePinForSelectedItem() {
        let items = selectedItemsInActionOrder
        guard !items.isEmpty else { return }

        let shouldPin = !items.allSatisfy(\.isPinned)
        let preferredID = selectedID ?? items.first?.id
        store.setPinned(shouldPin, for: items)
        syncSelection(preferredID: preferredID)
    }

    func deleteSelectedItem() {
        let items = selectedItemsInActionOrder
        guard !items.isEmpty else { return }

        pendingPreferredSelectionID = preferredSelectionID(afterDeleting: items)
        store.delete(items)
    }

    func togglePin(for item: ClipboardItem) {
        selectSingle(item.id)
        store.togglePin(for: item)
        syncSelection(preferredID: item.id)
    }

    func delete(_ item: ClipboardItem) {
        selectSingle(item.id)
        pendingPreferredSelectionID = preferredSelectionID(afterDeleting: [item])
        store.delete(item)
    }

    func contextMenuTargetItems(for clickedItemID: UUID) -> [ClipboardItem] {
        let itemsByID = Dictionary(uniqueKeysWithValues: filteredItems.map { ($0.id, $0) })

        if selectedIDs.contains(clickedItemID) {
            return selectedItemsInActionOrder
        }

        guard let item = itemsByID[clickedItemID] else { return [] }
        return [item]
    }

    func visualContextMenuTargetItems(for clickedItemID: UUID) -> [ClipboardItem] {
        let targets = contextMenuTargetItems(for: clickedItemID)
        let targetIDs = Set(targets.map(\.id))
        return filteredItems.filter { targetIDs.contains($0.id) }
    }

    func contextMenuActions(for clickedItemID: UUID) -> [HistoryItemActionDescriptor] {
        resolvedActions(
            for: contextMenuTargetItems(for: clickedItemID),
            allowsJumpToHistory: !searchText.isEmpty,
            isExtractingText: isExtractingText
        )
    }

    func shouldShowUnpinForContextMenuTarget(_ clickedItemID: UUID) -> Bool {
        let targets = contextMenuTargetItems(for: clickedItemID)
        return !targets.isEmpty && targets.allSatisfy(\.isPinned)
    }

    private func resolvedActions(
        for items: [ClipboardItem],
        allowsJumpToHistory: Bool,
        isExtractingText: Bool
    ) -> [HistoryItemActionDescriptor] {
        guard !items.isEmpty else { return [] }

        let allPinned = items.allSatisfy(\.isPinned)
        let pinDescriptor = HistoryItemActionDescriptor(
            action: .togglePin,
            title: allPinned ? "Unpin" : "Pin",
            systemImage: allPinned ? "pin.slash" : "pin",
            isPinnedVariant: allPinned
        )

        if items.count > 1 {
            return [
                .init(action: .copy),
                pinDescriptor,
                .init(action: .delete, isDestructive: true)
            ]
        }

        let item = items[0]
        var actions: [HistoryItemActionDescriptor] = [.init(action: .copy)]

        if ClipboardItemTypeRegistry.canOpenLink(for: item) {
            actions.append(.init(action: .openLink))
        }

        if allowsJumpToHistory {
            actions.append(.init(action: .jumpToHistory))
        }

        if ClipboardItemTypeRegistry.canSaveImage(for: item) {
            actions.append(.init(action: .saveImage))
        }

        if ClipboardItemTypeRegistry.canExtractImageText(for: item) {
            actions.append(
                .init(
                    action: .extractImageText,
                    systemImage: isExtractingText ? "ellipsis.circle" : HistoryItemAction.extractImageText.systemImage,
                    isEnabled: item.ocrText == nil && !isExtractingText
                )
            )
        }

        actions.append(pinDescriptor)
        actions.append(.init(action: .delete, isDestructive: true))
        return actions
    }

    func deleteContextMenuTarget(_ clickedItemID: UUID) {
        let targets = contextMenuTargetItems(for: clickedItemID)
        guard !targets.isEmpty else { return }

        pendingPreferredSelectionID = preferredSelectionID(afterDeleting: targets)
        store.delete(targets)
    }

    func togglePinForContextMenuTarget(_ clickedItemID: UUID) {
        let targets = contextMenuTargetItems(for: clickedItemID)
        guard !targets.isEmpty else { return }

        let shouldPin = !targets.allSatisfy(\.isPinned)
        let preferredID = selectedIDs.contains(clickedItemID) ? (selectedID ?? clickedItemID) : clickedItemID
        store.setPinned(shouldPin, for: targets)
        syncSelection(preferredID: preferredID)
    }

    func jumpToHistory(for item: ClipboardItem) {
        let targetID = item.id

        jumpToHistoryGenerationCounter &+= 1
        jumpToHistoryFailureCount = 0

        let request = JumpToHistoryRequest(
            itemID: targetID,
            generation: jumpToHistoryGenerationCounter
        )

        jumpToHistoryState = .pending(request)

        logJumpToHistory(
            "Jump to history requested item=\(targetID.uuidString) generation=\(request.generation)"
        )

        if !searchText.isEmpty {
            isApplyingProgrammaticSearchChange = true
            searchText = ""
            rebuildFilteredItems(preferredID: targetID)
        } else {
            syncSelection(preferredID: targetID)
        }
    }

    func markJumpToHistoryScrollStarted(_ request: JumpToHistoryRequest) {
        guard jumpToHistoryState.request == request else {
            return
        }

        jumpToHistoryState = .scrolling(request)

        logJumpToHistory(
            "Jump to history scroll started item=\(request.itemID.uuidString) generation=\(request.generation)"
        )
    }

    func completeJumpToHistoryScroll(_ request: JumpToHistoryRequest, succeeded: Bool) {
        guard jumpToHistoryState.request == request else {
            return
        }

        if succeeded {
            logJumpToHistory(
                "Jump to history completed item=\(request.itemID.uuidString) generation=\(request.generation)"
            )

            jumpToHistoryState = .idle
            jumpToHistoryFailureCount = 0
            return
        }

        switch jumpToHistoryState {
        case .idle:
            return

        case .scrolling:
            /*
             The list already attempted the jump. Even if measured verification failed,
             do not re-pend the jump here. Retrying after a visible scroll causes the
             list to snap back to the selected item and blocks normal user scrolling.
             */
            logJumpToHistory(
                "Jump to history finished without verification item=\(request.itemID.uuidString) generation=\(request.generation)"
            )

            jumpToHistoryState = .idle
            jumpToHistoryFailureCount = 0

        case .pending:
            /*
             Retry only when the list never actually started the jump, for example if
             the full-history list was not ready yet.
             */
            jumpToHistoryFailureCount += 1

            logJumpToHistory(
                "Jump to history pending retry item=\(request.itemID.uuidString) attempt=\(jumpToHistoryFailureCount)"
            )

            guard jumpToHistoryFailureCount <= maxJumpToHistoryRetryCount else {
                logJumpToHistory(
                    "Jump to history abandoned item=\(request.itemID.uuidString)"
                )

                jumpToHistoryState = .idle
                jumpToHistoryFailureCount = 0
                return
            }

            jumpToHistoryGenerationCounter &+= 1

            let retryRequest = JumpToHistoryRequest(
                itemID: request.itemID,
                generation: jumpToHistoryGenerationCounter
            )

            jumpToHistoryState = .pending(retryRequest)
        }
    }

    func completeKeyboardNavigation(_ request: KeyboardNavigationRequest) {
        guard keyboardNavigationRequest == request else {
            return
        }

        keyboardNavigationRequest = nil

        guard filteredItems[safe: request.targetIndex]?.id == request.itemID else {
            syncSelection(preferredID: request.itemID)
            return
        }

        withAnimation(.easeInOut(duration: 0.14)) {
            applySingleSelection(request.itemID, index: request.targetIndex)
        }
    }

    func setHoveredItemID(_ itemID: UUID?, isHovered: Bool) {
        hoveredItemID = isHovered ? itemID : nil
    }

    func performQuickPaste(at index: Int) -> ClipboardItem? {
        guard settingsManager.quickPasteEnabled,
              let item = quickPasteAddressableItems[safe: index] else { return nil }

        selectSingle(item.id)
        return item
    }

    func loadPreviewIfNeeded() async {
        previewImage = nil
        chunkedText = ChunkedTextState()
        isExtractingText = false

        guard let item = selectedItem else { return }

        if ClipboardItemTypeRegistry.supportsImageAssets(for: item) {
            previewImage = loadPreviewImage(for: item)
        } else if ClipboardItemTypeRegistry.supportsTextChunks(for: item), item.isFileBacked {
            await loadInitialChunk(for: item)
        } else {
            chunkedText.visibleText = ClipboardItemTypeRegistry.pastedText(for: item, store: store) ?? ""
            chunkedText.reachedEOF = true
        }
    }

    func extractSelectedImageText() async {
        guard let item = selectedItem else { return }
        await extractImageText(for: item)
    }

    func extractImageText(for item: ClipboardItem) async {
        isExtractingText = true

        let image: NSImage?
        if selectedItem?.id == item.id {
            image = previewImage ?? loadPreviewImage(for: item)
        } else {
            image = loadPreviewImage(for: item)
        }

        guard let image else {
            isExtractingText = false
            return
        }

        let result = await ocrService.recognizeText(from: image)
        store.setOCRText(result ?? "No text found in this image.", for: item)
        isExtractingText = false
    }

    func loadNextChunk() async {
        guard let item = selectedItem else { return }
        guard !chunkedText.isLoadingMore && chunkedText.hasMore else { return }

        chunkedText.isLoadingMore = true
        let nextCharCount = chunkedText.loadedCharCount + ChunkedTextState.chunkSize

        if let result = store.textChunk(for: item, charCount: nextCharCount) {
            chunkedText.visibleText = result.text
            chunkedText.totalBytes = result.totalBytes
            chunkedText.loadedCharCount = result.text.count
            chunkedText.reachedEOF = result.reachedEOF
        }

        chunkedText.isLoadingMore = false
    }

    private func loadPreviewImage(for item: ClipboardItem) -> NSImage? {
        store.image(for: item)
    }

    private func loadInitialChunk(for item: ClipboardItem) async {
        chunkedText.isLoadingMore = true

        if let result = store.textChunk(for: item, charCount: ChunkedTextState.initialChars) {
            chunkedText.visibleText = result.text
            chunkedText.totalBytes = result.totalBytes
            chunkedText.loadedCharCount = result.text.count
            chunkedText.reachedEOF = result.reachedEOF
        }

        chunkedText.isLoadingMore = false
    }

    private func syncSelection(preferredID: UUID? = nil) {
        keyboardNavigationRequest = nil

        guard !filteredItems.isEmpty else {
            clearSelection()
            return
        }

        let validIDs = Set(filteredItems.map(\.id))
        selectedIDs = selectedIDs.intersection(validIDs)
        selectedActionOrderIDs.removeAll { !validIDs.contains($0) }
        if let preferredID, validIDs.contains(preferredID) {
            if let index = filteredItems.firstIndex(where: { $0.id == preferredID }) {
                applySingleSelection(preferredID, index: index)
            }
            return
        }

        if !selectedIDs.isEmpty {
            if selectedActionOrderIDs.isEmpty {
                selectedActionOrderIDs = selectedItems.map(\.id)
            }

            if let currentSelectedID = selectedID, validIDs.contains(currentSelectedID),
               let index = filteredItems.firstIndex(where: { $0.id == currentSelectedID }) {
                selectedIndex = index
            } else if let fallbackID = selectedActionOrderIDs.first ?? selectedItems.first?.id,
                      let fallbackIndex = filteredItems.firstIndex(where: { $0.id == fallbackID }) {
                selectedID = fallbackID
                selectedIndex = fallbackIndex
            }

            selectionAnchor = selectionAnchor.flatMap { validIDs.contains($0) ? $0 : nil } ?? selectedID
            return
        }

        let targetID = selectedID.flatMap { validIDs.contains($0) ? $0 : nil } ?? preferredTopSelectionID()
        guard let targetID,
              let index = filteredItems.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        applySingleSelection(targetID, index: index)
    }

    private func preferredTopSelectionID() -> UUID? {
        if settingsManager.historyWindowOpenBehavior == .selectFirstNonPinnedItem {
            return filteredItems.first(where: { !$0.isPinned })?.id ?? filteredItems.first?.id
        }

        return filteredItems.first?.id
    }

    private func quickPasteRelevantFlags(from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .shift, .option, .control])
    }

    private var quickPasteAddressableItems: [ClipboardItem] {
        let itemsToAddress: [ClipboardItem]

        switch settingsManager.quickPasteNumberingStart {
        case .pinnedSection:
            itemsToAddress = filteredItems
        case .normalEntries:
            let unpinnedItems = filteredItems.filter { !$0.isPinned }
            itemsToAddress = unpinnedItems.isEmpty ? filteredItems : unpinnedItems
        }

        return Array(itemsToAddress.prefix(settingsManager.quickPasteEntryCount))
    }

    private func quickPasteBadgeNumber(for index: Int) -> Int {
        if index == 9 {
            return 0
        }

        return index + 1
    }

    private func rebuildFilteredItems(preferredID: UUID? = nil) {
        filteredItems = Self.makeFilteredItems(from: store.items, query: searchText, store: store)
        syncSelection(preferredID: preferredID)
    }

    private func requestKeyboardNavigation(by delta: Int) {
        if let pendingRequest = keyboardNavigationRequest {
            completeKeyboardNavigation(pendingRequest)
        }

        let baseIndex = keyboardNavigationRequest?.targetIndex ?? selectedIndex
        let targetIndex = baseIndex + delta

        guard filteredItems.indices.contains(targetIndex),
              let itemID = filteredItems[safe: targetIndex]?.id else {
            return
        }

        keyboardNavigationGenerationCounter &+= 1
        keyboardNavigationRequest = KeyboardNavigationRequest(
            itemID: itemID,
            targetIndex: targetIndex,
            generation: keyboardNavigationGenerationCounter
        )
    }

    private func preferredSelectionID(afterDeleting items: [ClipboardItem]) -> UUID? {
        let deletedIDs = Set(items.map(\.id))
        guard !deletedIDs.isEmpty else { return nil }

        let remainingItems = filteredItems.filter { !deletedIDs.contains($0.id) }
        guard !remainingItems.isEmpty else { return nil }

        let deletedIndices = items.compactMap { item in
            filteredItems.firstIndex(where: { $0.id == item.id })
        }
        guard let deletedIndex = deletedIndices.min() else {
            return remainingItems.first?.id
        }

        if let nextVisible = filteredItems[deletedIndex...].first(where: { !deletedIDs.contains($0.id) }) {
            return nextVisible.id
        }

        if deletedIndex > 0 {
            return filteredItems[0..<deletedIndex].last(where: { !deletedIDs.contains($0.id) })?.id
        }

        return remainingItems.first?.id
    }

    private func consumePendingPreferredSelectionID() -> UUID? {
        let preferredID = pendingPreferredSelectionID
        pendingPreferredSelectionID = nil
        return preferredID
    }

    private func logJumpToHistory(_ message: @autoclosure () -> String) {
#if DEBUG
        let resolvedMessage = message()
        BufferLogger.ui.debug("\(resolvedMessage, privacy: .public)")
#endif
    }

    private static func makeFilteredItems(from items: [ClipboardItem], query: String, store: ClipboardStore) -> [ClipboardItem] {
        let baseItems: [ClipboardItem]

        if query.isEmpty {
            baseItems = items
        } else {
            baseItems = items.filter { item in
                store.searchableText(for: item).localizedCaseInsensitiveContains(query)
            }
        }

        return baseItems.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }

            if lhs.isPinned, rhs.isPinned {
                let lhsPinnedAt = lhs.pinnedAt ?? lhs.timestamp
                let rhsPinnedAt = rhs.pinnedAt ?? rhs.timestamp

                if lhsPinnedAt != rhsPinnedAt {
                    return lhsPinnedAt < rhsPinnedAt
                }
            }

            return lhs.timestamp > rhs.timestamp
        }
    }

    private func applySingleSelection(_ id: UUID, index: Int? = nil) {
        selectedIDs = [id]
        selectedActionOrderIDs = [id]
        selectionAnchor = id
        selectedID = id

        if let index {
            selectedIndex = index
        } else if let index = filteredItems.firstIndex(where: { $0.id == id }) {
            selectedIndex = index
        }
    }

    private func clearSelection() {
        selectedIDs = []
        selectedActionOrderIDs = []
        selectionAnchor = nil
        selectedID = nil
        selectedIndex = 0
    }

    private func nearestSelectedID(around index: Int) -> UUID? {
        guard !selectedIDs.isEmpty else { return nil }

        if let next = filteredItems[index...].first(where: { selectedIDs.contains($0.id) }) {
            return next.id
        }

        if index > 0 {
            return filteredItems[0..<index].last(where: { selectedIDs.contains($0.id) })?.id
        }

        return nil
    }
}
