import AppKit
import Combine
import SwiftUI

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var searchText = "" {
        didSet {
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
    @Published var scrollTrigger = false
    @Published var hoveredItemID: UUID?

    private let store: ClipboardStore
    private let settingsManager: SettingsManager
    private let ocrService: OCRServicing
    private var selectionAnchor: UUID?
    private var quickPasteNeedsModifierReset = false
    private var cancellables: Set<AnyCancellable> = []
    private static let copiedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
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
                self.syncSelection()
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
        selectionCount <= 1 && selectedItem?.type == .image
    }

    var canExtractSelectedImageText: Bool {
        isSingleImageSelection && selectedItem?.ocrText == nil && !isExtractingText
    }

    var selectedItemIsPinned: Bool {
        selectedItem?.isPinned == true
    }

    var textSelectionCount: Int {
        selectedItems.filter { $0.type == .text }.count
    }

    var imageSelectionCount: Int {
        selectedItems.filter { $0.type == .image }.count
    }

    var firstTextPreview: String? {
        selectedItems.first(where: { $0.type == .text }).map { String(($0.textContent ?? "").prefix(200)) }
    }

    var selectedItemSourceName: String? {
        selectedItem?.sourceAppDisplayName
    }

    var selectedItemCopiedAtText: String? {
        guard let timestamp = selectedItem?.timestamp else { return nil }
        return Self.copiedAtFormatter.string(from: timestamp)
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
        syncSelection(preferredID: preferredInitialSelectionID())
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
            showsQuickPasteNumbers = relevantFlags == .command
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

    func selectSingle(_ id: UUID) {
        selectedIDs = [id]
        selectionAnchor = id
        selectedID = id
        if let index = filteredItems.firstIndex(where: { $0.id == id }) {
            selectedIndex = index
        }
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
        store.delete(item)
    }

    func setHoveredItemID(_ itemID: UUID?, isHovered: Bool) {
        hoveredItemID = isHovered ? itemID : nil
    }

    func performQuickPaste(at index: Int) -> ClipboardItem? {
        guard let item = filteredItems[safe: index] else { return nil }
        selectSingle(item.id)
        return item
    }

    func loadPreviewIfNeeded() async {
        previewImage = nil
        chunkedText = ChunkedTextState()
        isExtractingText = false

        guard let item = selectedItem else { return }

        if item.type == .image {
            previewImage = loadPreviewImage(for: item)
        } else if item.isFileBacked {
            await loadInitialChunk(for: item)
        } else {
            chunkedText.visibleText = item.textContent ?? ""
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

        let targetID = preferredID ?? selectedID ?? selectedIDs.first ?? preferredInitialSelectionID()
        guard let targetID,
              let index = filteredItems.firstIndex(where: { $0.id == targetID }) else {
            if let fallbackID = preferredInitialSelectionID(),
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

    private func preferredInitialSelectionID() -> UUID? {
        if settingsManager.preferInitialSelectionFromFirstNonPinnedItem {
            return filteredItems.first(where: { !$0.isPinned })?.id ?? filteredItems.first?.id
        }

        return filteredItems.first?.id
    }

    private func quickPasteRelevantFlags(from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .shift, .option, .control])
    }

    private func rebuildFilteredItems(preferredID: UUID? = nil) {
        filteredItems = Self.makeFilteredItems(from: store.items, query: searchText, store: store)
        syncSelection(preferredID: preferredID)
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
