import SwiftUI

struct HistoryMultiSelectionSummary: View {
    let items: [ClipboardItem]
    let assetProvider: any ClipboardItemAssetProviding
    let textDetailFontStyle: TextDetailFontStyle
    let textDetailFontSize: TextDetailFontSize
    let enableWebsitePreviews: Bool
    let actionsForItem: (ClipboardItem) -> [HistoryItemActionDescriptor]
    let onSelectAction: (ClipboardItem, HistoryItemAction) -> Void
    let onCopyOCRText: (String) -> Void
    let onCopyColorVariant: (String) -> Void

    @State private var expandedTextItemIDs: Set<UUID> = []
    @State private var collapsedItemIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                HistoryMultiSelectionCard(
                    item: item,
                    assetProvider: assetProvider,
                    isCollapsed: collapsedItemIDs.contains(item.id),
                    isTextExpanded: expandedTextItemIDs.contains(item.id),
                    textDetailFontStyle: textDetailFontStyle,
                    textDetailFontSize: textDetailFontSize,
                    enableWebsitePreviews: enableWebsitePreviews,
                    actions: actionsForItem(item),
                    onToggleCollapsed: {
                        toggleCollapsed(item.id)
                    },
                    onToggleExpandedText: {
                        toggleExpandedText(item.id)
                    },
                    onSelectAction: { action in
                        onSelectAction(item, action)
                    },
                    onCopyOCRText: onCopyOCRText,
                    onCopyColorVariant: onCopyColorVariant
                )
            }
        }
    }

    private func toggleExpandedText(_ itemID: UUID) {
        if expandedTextItemIDs.contains(itemID) {
            expandedTextItemIDs.remove(itemID)
        } else {
            expandedTextItemIDs.insert(itemID)
        }
    }

    private func toggleCollapsed(_ itemID: UUID) {
        if collapsedItemIDs.contains(itemID) {
            collapsedItemIDs.remove(itemID)
        } else {
            expandedTextItemIDs.remove(itemID)
            collapsedItemIDs.insert(itemID)
        }
    }
}
