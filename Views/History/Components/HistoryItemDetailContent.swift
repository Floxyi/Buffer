import AppKit
import SwiftUI

struct HistoryItemDetailContent: View {
    let item: ClipboardItem
    let previewImage: NSImage?
    let chunkedText: ChunkedTextState
    let isExtractingText: Bool
    let textDetailFontStyle: TextDetailFontStyle
    let textDetailFontSize: TextDetailFontSize
    let showsSpacesAndTabs: Bool
    let enableWebsitePreviews: Bool
    let onCopyOCRText: (String) -> Void
    let onCopyColorVariant: (String) -> Void
    let onLoadNextChunk: (ClipboardItem) -> Void

    var body: some View {
        switch ClipboardItemPresentation.definition(for: item).detailContentKind {
        case .text:
            HistoryTextDetailContent(
                item: item,
                chunkedText: chunkedText,
                textDetailFontStyle: textDetailFontStyle,
                textDetailFontSize: textDetailFontSize,
                showsSpacesAndTabs: showsSpacesAndTabs,
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
        case .email:
            HistoryEmailDetailContent(
                item: item,
                textDetailFontStyle: textDetailFontStyle,
                textDetailFontSize: textDetailFontSize
            )
        }
    }
}

struct HistoryEmailDetailContent: View {
    let item: ClipboardItem
    let textDetailFontStyle: TextDetailFontStyle
    let textDetailFontSize: TextDetailFontSize

    var body: some View {
        SelectableMonospacedTextView(
            text: item.emailPayload?.originalText ?? "",
            fontSize: CGFloat(textDetailFontSize.rawValue),
            usesMonospacedFont: textDetailFontStyle == .monospaced
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
