import AppKit
import SwiftUI

struct HistoryItemDetailContent: View {
    let item: ClipboardItem
    let previewImage: NSImage?
    let chunkedText: ChunkedTextState
    let isExtractingText: Bool
    let onCopyOCRText: (String) -> Void
    let onLoadNextChunk: (ClipboardItem) -> Void

    var body: some View {
        switch item.type {
        case .text:
            HistoryTextDetailContent(
                item: item,
                chunkedText: chunkedText,
                onLoadNextChunk: onLoadNextChunk
            )
        case .image:
            HistoryImageDetailContent(
                item: item,
                previewImage: previewImage,
                isExtractingText: isExtractingText,
                onCopyOCRText: onCopyOCRText
            )
        }
    }
}
