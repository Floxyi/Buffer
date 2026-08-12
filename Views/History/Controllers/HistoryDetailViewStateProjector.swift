import Foundation

@MainActor
struct HistoryDetailViewStateProjector {
    func project(
        selectedItem: ClipboardItem?,
        selectedItemsInVisualOrder: [ClipboardItem],
        selectedItemsInActionOrder: [ClipboardItem],
        searchText: String,
        previewState: HistoryPreviewState,
        selectedItemsTotalSizeBytes: Int?,
        actionResolver: HistoryActionResolver,
        copiedAtFormatter: HistoryCopiedAtFormatter
    ) -> HistoryDetailViewState {
        let selectionCount = selectedItemsInVisualOrder.count
        let actionTargets = selectedActionTargets(
            selectedItem: selectedItem,
            selectedItemsInActionOrder: selectedItemsInActionOrder
        )
        let canSaveSelectedImage = selectionCount <= 1 && ClipboardItemTypeRegistry.canSaveImage(for: selectedItem)
        let canExtractSelectedImageText =
            selectionCount <= 1
            && ClipboardItemTypeRegistry.canExtractImageText(for: selectedItem)
            && selectedItem?.ocrText == nil
            && !previewState.isExtractingText
        let canJumpToHistorySelection = selectionCount == 1 && selectedItem != nil && !searchText.isEmpty

        return HistoryDetailViewState(
            selectionCount: selectionCount,
            selectedItem: selectedItem,
            selectedItems: selectedItemsInVisualOrder,
            previewImage: previewState.previewImage,
            chunkedText: previewState.chunkedText,
            isExtractingText: previewState.isExtractingText,
            selectedItemSourceName: selectedItem?.sourceAppDisplayName,
            selectedItemCopiedAtText: selectedItem.map { copiedAtFormatter.string(for: $0.timestamp) },
            selectedItemsTotalSizeText: selectedItemsTotalSizeBytes.map(AppFormatting.formattedByteCount)
                ?? AppFormatting.formattedByteCount(0),
            textSelectionCount: selectedItemsInVisualOrder.filter { $0.kind == .text }.count,
            imageSelectionCount: selectedItemsInVisualOrder.filter { $0.kind == .image }.count,
            colorSelectionCount: selectedItemsInVisualOrder.filter { $0.kind == .color }.count,
            linkSelectionCount: selectedItemsInVisualOrder.filter { $0.kind == .link }.count,
            firstTextPreview: selectedItemsInVisualOrder.first(where: {
                $0.kind == .text || $0.kind == .color || $0.kind == .link
            }).map {
                String(ClipboardItemPresentation.previewText(for: $0).prefix(200))
            },
            actions: actionResolver.resolveActions(
                for: actionTargets,
                allowsJumpToHistory: canJumpToHistorySelection,
                isExtractingText: previewState.isExtractingText
            ),
            canSaveSelectedImage: canSaveSelectedImage,
            canExtractSelectedImageText: canExtractSelectedImageText,
            selectedItemIsPinned: !actionTargets.isEmpty && actionTargets.allSatisfy(\.isPinned),
            canJumpToHistorySelection: canJumpToHistorySelection
        )
    }

    private func selectedActionTargets(
        selectedItem: ClipboardItem?,
        selectedItemsInActionOrder: [ClipboardItem]
    ) -> [ClipboardItem] {
        if !selectedItemsInActionOrder.isEmpty {
            return selectedItemsInActionOrder
        }

        return selectedItem.map { [$0] } ?? []
    }
}
