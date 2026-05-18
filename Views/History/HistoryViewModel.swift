import AppKit
import Combine
import SwiftUI

@MainActor
final class HistoryViewModel: ObservableObject {
    struct OpenListScrollRequest: Equatable {
        enum Mode: Equatable {
            case restoreOffset(CGFloat)
            case scrollToTop
            case scrollToItem(UUID)
        }

        let mode: Mode
    }

    struct JumpToHistoryRequest: Equatable {
        let itemID: UUID
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
    @Published private(set) var openListScrollRequest = OpenListScrollRequest(mode: .restoreOffset(0))
    @Published private(set) var openListScrollRequestToken = 0
    @Published private(set) var jumpToHistoryState = JumpToHistoryState.idle

    @Published var scrollTrigger = false
    @Published var hoveredItemID: UUID?

    private let store: ClipboardStore
    private let settingsManager: SettingsManager
    private let ocrService: OCRServicing

    private var selectionAnchor: UUID?
    private var quickPasteNeedsModifierReset = false
    private var isApplyingProgrammaticSearchChange = false
    private var pendingPreferredSelectionID: UUID?
    private var lastListScrollOffset = CGFloat.zero
    private var cancellables: Set<AnyCancellable> = []

    private var jumpToHistoryGenerationCounter: UInt = 0
    private var jumpToHistoryFailureCount = 0
    private let maxJumpToHistoryRetryCount = 2

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
        selectedItems.first
    }

    var selectedItems: [ClipboardItem] {
        filteredItems.filter { selectedIDs.contains($0.id) }
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
        selectedItem?.isPinned == true
    }

    var canJumpToHistorySelection: Bool {
        selectedItem != nil && !searchText.isEmpty
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
            syncSelection(preferredID: selectedID ?? preferredTopSelectionID())
            openListScrollRequest = OpenListScrollRequest(mode: .restoreOffset(lastListScrollOffset))
        } else {
            syncSelection(preferredID: preferredTopSelectionID())
            openListScrollRequest = OpenListScrollRequest(mode: .scrollToTop)
        }

        openListScrollRequestToken &+= 1
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
        selectedIDs = [id]
        selectionAnchor = id
        selectedID = id

        if let index = filteredItems.firstIndex(where: { $0.id == id }) {
            selectedIndex = index
        }
    }

    @discardableResult
    func selectPreferredTopItem() -> UUID? {
        guard let preferredTopSelectionID = preferredTopSelectionID() else {
            selectedIDs = []
            selectionAnchor = nil
            selectedID = nil
            selectedIndex = 0
            return nil
        }

        syncSelection(preferredID: preferredTopSelectionID)
        return preferredTopSelectionID
    }

    func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }

        selectionAnchor = id

        if let index = filteredItems.firstIndex(where: { $0.id == id }) {
            selectedIndex = index
            selectedID = id
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

        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedIDs = Set(filteredItems[range].map(\.id))
        selectedIndex = targetIndex
        selectedID = targetID
    }

    func navigateUp() {
        guard selectedIndex > 0 else { return }

        scrollTrigger = true
        selectedIndex -= 1
        syncSelection(preferredID: filteredItems[safe: selectedIndex]?.id)
    }

    func navigateDown() {
        guard selectedIndex < filteredItems.count - 1 else { return }

        scrollTrigger = true
        selectedIndex += 1
        syncSelection(preferredID: filteredItems[safe: selectedIndex]?.id)
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
        selectionAnchor = selectionAnchor ?? currentItem.id
        selectedIndex = nextIndex
        selectedID = nextItem.id
    }

    func togglePinForSelectedItem() {
        guard let item = selectedItem else { return }

        let selectedItemID = item.id
        store.togglePin(for: item)
        syncSelection(preferredID: selectedItemID)
    }

    func deleteSelectedItem() {
        guard let item = selectedItem else { return }

        pendingPreferredSelectionID = preferredSelectionID(afterDeleting: item)
        store.delete(item)
    }

    func togglePin(for item: ClipboardItem) {
        selectSingle(item.id)
        store.togglePin(for: item)
        syncSelection(preferredID: item.id)
    }

    func delete(_ item: ClipboardItem) {
        selectSingle(item.id)
        pendingPreferredSelectionID = preferredSelectionID(afterDeleting: item)
        store.delete(item)
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

    func setHoveredItemID(_ itemID: UUID?, isHovered: Bool) {
        hoveredItemID = isHovered ? itemID : nil
    }

    func updateLastListScrollOffset(_ offset: CGFloat) {
        lastListScrollOffset = max(0, offset)
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

        isExtractingText = true

        let image = previewImage ?? loadPreviewImage(for: item)
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
        guard !filteredItems.isEmpty else {
            selectedIDs = []
            selectionAnchor = nil
            selectedID = nil
            selectedIndex = 0
            return
        }

        let targetID = preferredID ?? selectedID ?? selectedIDs.first ?? preferredTopSelectionID()
        guard let targetID,
              let index = filteredItems.firstIndex(where: { $0.id == targetID }) else {
            if let fallbackID = preferredTopSelectionID(),
               let fallbackIndex = filteredItems.firstIndex(where: { $0.id == fallbackID }) {
                selectedIDs = [fallbackID]
                selectionAnchor = fallbackID
                selectedID = fallbackID
                selectedIndex = fallbackIndex
            }
            return
        }

        selectedIDs = [targetID]
        selectionAnchor = targetID
        selectedID = targetID
        selectedIndex = index
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

    private func preferredSelectionID(afterDeleting item: ClipboardItem) -> UUID? {
        guard let deletedIndex = filteredItems.firstIndex(where: { $0.id == item.id }) else {
            return nil
        }

        let nextIndex = deletedIndex + 1
        if let nextID = filteredItems[safe: nextIndex]?.id {
            return nextID
        }

        if deletedIndex > 0 {
            return filteredItems[safe: deletedIndex - 1]?.id
        }

        return nil
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
}
