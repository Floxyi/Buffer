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
    let selectionCount: Int
    let selectedItem: ClipboardItem?
    let selectedItems: [ClipboardItem]
    let isExtractingText: Bool
    let selectedItemSourceName: String?
    let selectedItemCopiedAtText: String?
    let selectedItemsTotalSizeText: String
    let textSelectionCount: Int
    let imageSelectionCount: Int
    let colorSelectionCount: Int
    let linkSelectionCount: Int
    let firstTextPreview: String?
    let previewImage: NSImage?
    let chunkedText: ChunkedTextState
    let textDetailFontStyle: TextDetailFontStyle
    let textDetailFontSize: TextDetailFontSize
    let enableWebsitePreviews: Bool
    let store: ClipboardStore
    let actions: [HistoryItemActionDescriptor]
    let actionsForItem: (ClipboardItem) -> [HistoryItemActionDescriptor]
    let onSelectItemAction: (ClipboardItem, HistoryItemAction) -> Void
    let onSelectAction: (HistoryItemAction) -> Void
    let onDownloadAllImages: () -> Void
    let onCopyOCRText: (String) -> Void
    let onCopyColorVariant: (String) -> Void
    let onLoadNextChunk: (ClipboardItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let selectedItem, selectionCount == 1 {
                HistoryDetailHeader(
                    item: selectedItem,
                    sourceAppName: selectedItemSourceName,
                    copiedAtText: selectedItemCopiedAtText,
                    actions: actions,
                    onSelectAction: onSelectAction
                )
            } else {
                HistoryMultiSelectionHeader(
                    selectionCount: selectionCount,
                    actions: actions,
                    onSelectAction: onSelectAction
                )
            }

            BufferPanelSeparator(isVertical: false)

            HistoryDetailScrollView {
                if selectionCount > 1 {
                    HistoryMultiSelectionSummary(
                        items: selectedItems,
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
                } else if let selectedItem {
                    HistoryItemDetailContent(
                        item: selectedItem,
                        previewImage: previewImage,
                        chunkedText: chunkedText,
                        isExtractingText: isExtractingText,
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
