import Foundation

struct TextItemContent: Codable, Equatable, Sendable {
    let inlineText: String?
    let fileName: String?
    let isTruncated: Bool
    let originalSizeBytes: Int?

    init(
        inlineText: String?,
        fileName: String? = nil,
        isTruncated: Bool = false,
        originalSizeBytes: Int? = nil
    ) {
        self.inlineText = inlineText
        self.fileName = fileName
        self.isTruncated = isTruncated
        self.originalSizeBytes = originalSizeBytes
    }
}
