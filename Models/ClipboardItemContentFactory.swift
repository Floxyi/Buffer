import Foundation

enum ClipboardItemContentFactory {
    static func makeContent(
        type: ClipboardItemType,
        textContent: String?,
        textFilename: String?,
        imageFilename: String?,
        ocrText: String?,
        isTruncated: Bool,
        originalSizeBytes: Int?
    ) -> ClipboardItemContent {
        switch type {
        case .text:
            return .text(
                TextItemContent(
                    inlineText: textContent,
                    fileName: textFilename,
                    isTruncated: isTruncated,
                    originalSizeBytes: originalSizeBytes
                )
            )
        case .image:
            return .image(ImageItemContent(filename: imageFilename ?? "", ocrText: ocrText))
        case .color:
            let originalText = textContent ?? ""
            let parsedValue = ClipboardColorValue.parse(originalText) ?? .fallback(from: originalText)
            return .color(ColorItemContent(value: parsedValue, originalText: originalText))
        case .link:
            let originalText = textContent ?? ""
            let parsedURL =
                ClipboardLinkValue.parseExplicit(originalText)
                ?? ClipboardLinkValue.parseImplicitWebsiteCandidate(originalText)
                ?? URL(string: "https://example.com")!
            return .link(LinkItemContent(url: parsedURL, originalText: originalText))
        case .email:
            let originalText = textContent ?? ""
            let payload =
                ClipboardEmailValue.parse(originalText)
                ?? EmailItemContent(
                    address: originalText.trimmingCharacters(in: .whitespacesAndNewlines),
                    originalText: originalText
                )
            return .email(payload)
        }
    }
}
