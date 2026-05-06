import AppKit
import SwiftUI

struct HistoryDetailPane: View {
    let selectionCount: Int
    let isSingleImageSelection: Bool
    let selectedItemIsPinned: Bool
    let canExtractSelectedImageText: Bool
    let isExtractingText: Bool
    let selectedItemSourceName: String?
    let selectedItemCopiedAtText: String?
    let selectedItemsTotalSizeText: String
    let textSelectionCount: Int
    let imageSelectionCount: Int
    let firstTextPreview: String?
    let selectedItem: ClipboardItem?
    let previewImage: NSImage?
    let chunkedText: ChunkedTextState
    let onCopy: () -> Void
    let onSaveImage: () -> Void
    let onExtractText: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    let onDownloadAllImages: () -> Void
    let onCopyOCRText: (String) -> Void
    let onLoadNextChunk: (ClipboardItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HistoryDetailHeader(
                selectionCount: selectionCount,
                isSingleImageSelection: isSingleImageSelection,
                selectedItemIsPinned: selectedItemIsPinned,
                canExtractSelectedImageText: canExtractSelectedImageText,
                isExtractingText: isExtractingText,
                sourceAppName: selectedItemSourceName,
                copiedAtText: selectedItemCopiedAtText,
                onCopy: onCopy,
                onSaveImage: onSaveImage,
                onExtractText: onExtractText,
                onTogglePin: onTogglePin,
                onDelete: onDelete
            )

            Divider()

            HistoryDetailScrollView {
                if selectionCount > 1 {
                    HistoryMultiSelectionSummary(
                        selectionCount: selectionCount,
                        selectedItemsTotalSizeText: selectedItemsTotalSizeText,
                        textCount: textSelectionCount,
                        imageCount: imageSelectionCount,
                        firstTextPreview: firstTextPreview,
                        onDownloadAllImages: onDownloadAllImages
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                } else if let selectedItem {
                    HistoryItemDetailContent(
                        item: selectedItem,
                        previewImage: previewImage,
                        chunkedText: chunkedText,
                        isExtractingText: isExtractingText,
                        onCopyOCRText: onCopyOCRText,
                        onLoadNextChunk: onLoadNextChunk
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .opacity(0.16)
        }
    }
}
