import AppKit
import SwiftUI

struct HistoryPanelSurfaceBackground: View {
    var body: some View {
        Rectangle()
            .fill(.regularMaterial)
            .opacity(0.16)
    }
}

struct HistoryDetailPane: View {
    let detailState: HistoryDetailViewState
    let textDetailFontStyle: TextDetailFontStyle
    let textDetailFontSize: TextDetailFontSize
    let enableWebsitePreviews: Bool
    let store: ClipboardStore
    let actionsForItem: (ClipboardItem) -> [HistoryItemActionDescriptor]
    let onSelectItemAction: (ClipboardItem, HistoryItemAction) -> Void
    let onSelectAction: (HistoryItemAction) -> Void
    let onDownloadAllImages: () -> Void
    let onCopyOCRText: (String) -> Void
    let onCopyColorVariant: (String) -> Void
    let onLoadNextChunk: (ClipboardItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let selectedItem = detailState.selectedItem, detailState.selectionCount == 1 {
                HistoryDetailHeader(
                    item: selectedItem,
                    sourceAppName: detailState.selectedItemSourceName,
                    copiedAtText: detailState.selectedItemCopiedAtText,
                    actions: detailState.actions,
                    onSelectAction: onSelectAction
                )
            } else {
                HistoryMultiSelectionHeader(
                    selectionCount: detailState.selectionCount,
                    actions: detailState.actions,
                    onSelectAction: onSelectAction
                )
            }

            BufferPanelSeparator(isVertical: false)

            HistoryDetailScrollView {
                if detailState.selectionCount > 1 {
                    HistoryMultiSelectionSummary(
                        items: detailState.selectedItems,
                        store: store,
                        textDetailFontStyle: textDetailFontStyle,
                        textDetailFontSize: textDetailFontSize,
                        enableWebsitePreviews: enableWebsitePreviews,
                        actionsForItem: actionsForItem,
                        onSelectAction: onSelectItemAction,
                        onCopyOCRText: onCopyOCRText,
                        onCopyColorVariant: onCopyColorVariant
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                } else if let selectedItem = detailState.selectedItem {
                    HistoryItemDetailContent(
                        item: selectedItem,
                        previewImage: detailState.previewImage,
                        chunkedText: detailState.chunkedText,
                        isExtractingText: detailState.isExtractingText,
                        textDetailFontStyle: textDetailFontStyle,
                        textDetailFontSize: textDetailFontSize,
                        enableWebsitePreviews: enableWebsitePreviews,
                        onCopyOCRText: onCopyOCRText,
                        onCopyColorVariant: onCopyColorVariant,
                        onLoadNextChunk: onLoadNextChunk
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(.trailing, 1)
        }
        .background {
            HistoryPanelSurfaceBackground()
        }
    }
}
