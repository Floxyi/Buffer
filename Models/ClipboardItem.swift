import Foundation

struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let sourceApp: String?
    let sourceAppBundleIdentifier: String?
    let sourceAppBundlePath: String?
    var isPinned: Bool
    var pinnedAt: Date?
    var content: ClipboardItemContent

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        sourceApp: String? = nil,
        sourceAppBundleIdentifier: String? = nil,
        sourceAppBundlePath: String? = nil,
        isPinned: Bool = false,
        pinnedAt: Date? = nil,
        content: ClipboardItemContent
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sourceApp = sourceApp
        self.sourceAppBundleIdentifier = sourceAppBundleIdentifier
        self.sourceAppBundlePath = sourceAppBundlePath
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
        self.content = content
    }

    init(
        id: UUID = UUID(),
        type: ClipboardItemType,
        timestamp: Date = Date(),
        sourceApp: String? = nil,
        sourceAppBundleIdentifier: String? = nil,
        sourceAppBundlePath: String? = nil,
        textContent: String? = nil,
        textFilename: String? = nil,
        imageFilename: String? = nil,
        isPinned: Bool = false,
        pinnedAt: Date? = nil,
        ocrText: String? = nil,
        isTruncated: Bool = false,
        originalSizeBytes: Int? = nil
    ) {
        self.init(
            id: id,
            timestamp: timestamp,
            sourceApp: sourceApp,
            sourceAppBundleIdentifier: sourceAppBundleIdentifier,
            sourceAppBundlePath: sourceAppBundlePath,
            isPinned: isPinned,
            pinnedAt: pinnedAt,
            content: ClipboardItemContentFactory.makeContent(
                type: type,
                textContent: textContent,
                textFilename: textFilename,
                imageFilename: imageFilename,
                ocrText: ocrText,
                isTruncated: isTruncated,
                originalSizeBytes: originalSizeBytes
            )
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, sourceApp, sourceAppBundleIdentifier, sourceAppBundlePath, content
        case type, textContent, textFilename, imageFilename
        case isBookmarked, isPinned, pinnedAt, ocrText, isTruncated, originalSizeBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        sourceApp = try container.decodeIfPresent(String.self, forKey: .sourceApp)
        sourceAppBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .sourceAppBundleIdentifier)
        sourceAppBundlePath = try container.decodeIfPresent(String.self, forKey: .sourceAppBundlePath)

        let legacyBookmarked = try container.decodeIfPresent(Bool.self, forKey: .isBookmarked) ?? false
        let pinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isPinned = pinned || legacyBookmarked
        pinnedAt = try container.decodeIfPresent(Date.self, forKey: .pinnedAt)

        if let content = try container.decodeIfPresent(ClipboardItemContent.self, forKey: .content) {
            self.content = content
            return
        }

        let type = try container.decode(ClipboardItemType.self, forKey: .type)
        let textContent = try container.decodeIfPresent(String.self, forKey: .textContent)
        let textFilename = try container.decodeIfPresent(String.self, forKey: .textFilename)
        let imageFilename = try container.decodeIfPresent(String.self, forKey: .imageFilename)
        let ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText)
        let isTruncated = try container.decodeIfPresent(Bool.self, forKey: .isTruncated) ?? false
        let originalSizeBytes = try container.decodeIfPresent(Int.self, forKey: .originalSizeBytes)

        content = ClipboardItemContentFactory.makeContent(
            type: type,
            textContent: textContent,
            textFilename: textFilename,
            imageFilename: imageFilename,
            ocrText: ocrText,
            isTruncated: isTruncated,
            originalSizeBytes: originalSizeBytes
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(sourceApp, forKey: .sourceApp)
        try container.encodeIfPresent(sourceAppBundleIdentifier, forKey: .sourceAppBundleIdentifier)
        try container.encodeIfPresent(sourceAppBundlePath, forKey: .sourceAppBundlePath)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(pinnedAt, forKey: .pinnedAt)
        try container.encode(content, forKey: .content)
    }

    static func text(_ content: String, sourceApp: SourceApplicationInfo? = nil) -> ClipboardItem {
        let sourceApplication = sourceApplicationValues(from: sourceApp)
        return ClipboardItem(
            sourceApp: sourceApplication.name,
            sourceAppBundleIdentifier: sourceApplication.bundleIdentifier,
            sourceAppBundlePath: sourceApplication.bundlePath,
            content: .text(TextItemContent(inlineText: content))
        )
    }

    static func color(_ value: ClipboardColorValue, originalText: String, sourceApp: SourceApplicationInfo? = nil) -> ClipboardItem {
        let sourceApplication = sourceApplicationValues(from: sourceApp)
        return ClipboardItem(
            sourceApp: sourceApplication.name,
            sourceAppBundleIdentifier: sourceApplication.bundleIdentifier,
            sourceAppBundlePath: sourceApplication.bundlePath,
            content: .color(ColorItemContent(value: value, originalText: originalText))
        )
    }

    static func link(_ url: URL, originalText: String, sourceApp: SourceApplicationInfo? = nil) -> ClipboardItem {
        let sourceApplication = sourceApplicationValues(from: sourceApp)
        return ClipboardItem(
            sourceApp: sourceApplication.name,
            sourceAppBundleIdentifier: sourceApplication.bundleIdentifier,
            sourceAppBundlePath: sourceApplication.bundlePath,
            content: .link(LinkItemContent(url: url, originalText: originalText))
        )
    }

    static func email(_ payload: EmailItemContent, sourceApp: SourceApplicationInfo? = nil) -> ClipboardItem {
        let sourceApplication = sourceApplicationValues(from: sourceApp)
        return ClipboardItem(
            sourceApp: sourceApplication.name,
            sourceAppBundleIdentifier: sourceApplication.bundleIdentifier,
            sourceAppBundlePath: sourceApplication.bundlePath,
            content: .email(payload)
        )
    }

    static func image(filename: String, sourceApp: SourceApplicationInfo? = nil) -> ClipboardItem {
        let sourceApplication = sourceApplicationValues(from: sourceApp)
        return ClipboardItem(
            sourceApp: sourceApplication.name,
            sourceAppBundleIdentifier: sourceApplication.bundleIdentifier,
            sourceAppBundlePath: sourceApplication.bundlePath,
            content: .image(ImageItemContent(filename: filename))
        )
    }

    static func largeText(preview: String, filename: String, sourceApp: SourceApplicationInfo? = nil) -> ClipboardItem {
        let sourceApplication = sourceApplicationValues(from: sourceApp)
        return ClipboardItem(
            sourceApp: sourceApplication.name,
            sourceAppBundleIdentifier: sourceApplication.bundleIdentifier,
            sourceAppBundlePath: sourceApplication.bundlePath,
            content: .text(TextItemContent(inlineText: preview, fileName: filename))
        )
    }

    static func truncatedText(_ preview: String, originalSizeBytes: Int, sourceApp: SourceApplicationInfo?) -> ClipboardItem {
        let sourceApplication = sourceApplicationValues(from: sourceApp)
        return ClipboardItem(
            sourceApp: sourceApplication.name,
            sourceAppBundleIdentifier: sourceApplication.bundleIdentifier,
            sourceAppBundlePath: sourceApplication.bundlePath,
            content: .text(
                TextItemContent(
                    inlineText: preview,
                    fileName: nil,
                    isTruncated: true,
                    originalSizeBytes: originalSizeBytes
                )
            )
        )
    }

    var kind: ClipboardItemKind {
        content.kind
    }

    var type: ClipboardItemType {
        kind
    }

    var textPayload: TextItemContent? {
        guard case .text(let payload) = content else { return nil }
        return payload
    }

    var imagePayload: ImageItemContent? {
        guard case .image(let payload) = content else { return nil }
        return payload
    }

    var colorPayload: ColorItemContent? {
        guard case .color(let payload) = content else { return nil }
        return payload
    }

    var linkPayload: LinkItemContent? {
        guard case .link(let payload) = content else { return nil }
        return payload
    }

    var emailPayload: EmailItemContent? {
        guard case .email(let payload) = content else { return nil }
        return payload
    }

    var textContent: String? {
        textPayload?.inlineText
    }

    var textFilename: String? {
        textPayload?.fileName
    }

    var imageFilename: String? {
        imagePayload?.filename
    }

    var ocrText: String? {
        imagePayload?.ocrText
    }

    var isTruncated: Bool {
        textPayload?.isTruncated == true
    }

    var originalSizeBytes: Int? {
        textPayload?.originalSizeBytes
    }

    var isFileBacked: Bool {
        textPayload?.fileName != nil
    }

    var contentHash: Int {
        ClipboardItemTypeRegistry.contentHash(for: self)
    }

    func updatingOCRText(_ text: String) -> ClipboardItem {
        guard case .image(let payload) = content else { return self }
        var updated = self
        updated.content = .image(payload.updatingOCRText(text))
        return updated
    }
}
