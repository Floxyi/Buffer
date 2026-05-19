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
    let selectedItemIsPinned: Bool
    let canExtractSelectedImageText: Bool
    let isExtractingText: Bool
    let showsJumpToHistory: Bool
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
    let onPasteItem: (ClipboardItem) -> Void
    let onCopyItem: (ClipboardItem) -> Void
    let onTogglePinItem: (ClipboardItem) -> Void
    let onDeleteItem: (ClipboardItem) -> Void
    let onJumpToHistoryItem: ((ClipboardItem) -> Void)?
    let onCopy: () -> Void
    let onSaveImage: () -> Void
    let onExtractText: () -> Void
    let onOpenLink: () -> Void
    let onJumpToHistory: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    let onDownloadAllImages: () -> Void
    let onCopyOCRText: (String) -> Void
    let onCopyColorVariant: (String) -> Void
    let onLoadNextChunk: (ClipboardItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let selectedItem, selectionCount == 1 {
                HistoryDetailHeader(
                    item: selectedItem,
                    selectedItemIsPinned: selectedItemIsPinned,
                    canExtractSelectedImageText: canExtractSelectedImageText,
                    isExtractingText: isExtractingText,
                    showsJumpToHistory: showsJumpToHistory,
                    sourceAppName: selectedItemSourceName,
                    copiedAtText: selectedItemCopiedAtText,
                    onCopy: onCopy,
                    onSaveImage: onSaveImage,
                    onExtractText: onExtractText,
                    onOpenLink: onOpenLink,
                    onJumpToHistory: onJumpToHistory,
                    onTogglePin: onTogglePin,
                    onDelete: onDelete
                )
            } else {
                HistoryMultiSelectionHeader(
                    selectionCount: selectionCount,
                    selectedItemIsPinned: selectedItemIsPinned,
                    onCopy: onCopy,
                    onTogglePin: onTogglePin,
                    onDelete: onDelete
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
                        onPasteItem: onPasteItem,
                        onCopyItem: onCopyItem,
                        onTogglePinItem: onTogglePinItem,
                        onDeleteItem: onDeleteItem,
                        onJumpToHistoryItem: onJumpToHistoryItem,
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
