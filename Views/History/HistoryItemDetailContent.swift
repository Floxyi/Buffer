import AppKit
import SwiftUI

struct HistoryItemDetailContent: View {
    let item: ClipboardItem
    let previewImage: NSImage?
    let chunkedText: ChunkedTextState
    let isExtractingText: Bool
    let textDetailFontStyle: TextDetailFontStyle
    let textDetailFontSize: TextDetailFontSize
    let enableWebsitePreviews: Bool
    let onCopyOCRText: (String) -> Void
    let onCopyColorVariant: (String) -> Void
    let onLoadNextChunk: (ClipboardItem) -> Void

    var body: some View {
        switch ClipboardItemTypeRegistry.definition(for: item).detailContentKind {
        case .text:
            HistoryTextDetailContent(
                item: item,
                chunkedText: chunkedText,
                textDetailFontStyle: textDetailFontStyle,
                textDetailFontSize: textDetailFontSize,
                onLoadNextChunk: onLoadNextChunk
            )
        case .image:
            HistoryImageDetailContent(
                item: item,
                previewImage: previewImage,
                isExtractingText: isExtractingText,
                onCopyOCRText: onCopyOCRText
            )
        case .color:
            HistoryColorDetailContent(
                item: item,
                textDetailFontStyle: textDetailFontStyle,
                textDetailFontSize: textDetailFontSize,
                onCopyColorVariant: onCopyColorVariant
            )
        case .link:
            HistoryLinkDetailContent(
                item: item,
                enableWebsitePreviews: enableWebsitePreviews
            )
        }
    }
}
