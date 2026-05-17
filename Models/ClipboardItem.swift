import AppKit
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
            content: ClipboardItem.makeContent(
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

        content = ClipboardItem.makeContent(
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
        ClipboardItem(
            sourceApp: sourceApp?.name,
            sourceAppBundleIdentifier: sourceApp?.bundleIdentifier,
            sourceAppBundlePath: sourceApp?.bundlePath,
            content: .text(TextItemContent(inlineText: content))
        )
    }

    static func color(_ value: ClipboardColorValue, originalText: String, sourceApp: SourceApplicationInfo? = nil) -> ClipboardItem {
        ClipboardItem(
            sourceApp: sourceApp?.name,
            sourceAppBundleIdentifier: sourceApp?.bundleIdentifier,
            sourceAppBundlePath: sourceApp?.bundlePath,
            content: .color(ColorItemContent(value: value, originalText: originalText))
        )
    }

    static func link(_ url: URL, originalText: String, sourceApp: SourceApplicationInfo? = nil) -> ClipboardItem {
        ClipboardItem(
            sourceApp: sourceApp?.name,
            sourceAppBundleIdentifier: sourceApp?.bundleIdentifier,
            sourceAppBundlePath: sourceApp?.bundlePath,
            content: .link(LinkItemContent(url: url, originalText: originalText))
        )
    }

    static func image(filename: String, sourceApp: SourceApplicationInfo? = nil) -> ClipboardItem {
        ClipboardItem(
            sourceApp: sourceApp?.name,
            sourceAppBundleIdentifier: sourceApp?.bundleIdentifier,
            sourceAppBundlePath: sourceApp?.bundlePath,
            content: .image(ImageItemContent(filename: filename))
        )
    }

    static func largeText(preview: String, filename: String, sourceApp: SourceApplicationInfo? = nil) -> ClipboardItem {
        ClipboardItem(
            sourceApp: sourceApp?.name,
            sourceAppBundleIdentifier: sourceApp?.bundleIdentifier,
            sourceAppBundlePath: sourceApp?.bundlePath,
            content: .text(TextItemContent(inlineText: preview, fileName: filename))
        )
    }

    static func truncatedText(_ preview: String, originalSizeBytes: Int, sourceApp: SourceApplicationInfo?) -> ClipboardItem {
        ClipboardItem(
            sourceApp: sourceApp?.name,
            sourceAppBundleIdentifier: sourceApp?.bundleIdentifier,
            sourceAppBundlePath: sourceApp?.bundlePath,
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

    var previewText: String {
        ClipboardItemTypeRegistry.previewText(for: self)
    }

    var contentHash: Int {
        ClipboardItemTypeRegistry.contentHash(for: self)
    }

    var sourceAppDisplayName: String? {
        if let sourceApp, !sourceApp.isEmpty {
            return sourceApp
        }

        if let sourceAppBundlePath, !sourceAppBundlePath.isEmpty {
            return URL(fileURLWithPath: sourceAppBundlePath)
                .deletingPathExtension()
                .lastPathComponent
        }

        if let sourceAppBundleIdentifier, !sourceAppBundleIdentifier.isEmpty {
            return sourceAppBundleIdentifier
        }

        return nil
    }

    func updatingOCRText(_ text: String) -> ClipboardItem {
        guard case .image(let payload) = content else { return self }
        var updated = self
        updated.content = .image(payload.updatingOCRText(text))
        return updated
    }

    private static func makeContent(
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
            let parsedURL = ClipboardLinkValue.parse(originalText) ?? URL(string: "https://example.com")!
            return .link(LinkItemContent(url: parsedURL, originalText: originalText))
        }
    }
}

enum ClipboardItemContent: Codable, Equatable, Sendable {
    case text(TextItemContent)
    case image(ImageItemContent)
    case color(ColorItemContent)
    case link(LinkItemContent)

    enum CodingKeys: String, CodingKey {
        case kind, text, image, color, link
    }

    var kind: ClipboardItemKind {
        switch self {
        case .text:
            return .text
        case .image:
            return .image
        case .color:
            return .color
        case .link:
            return .link
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(ClipboardItemKind.self, forKey: .kind)

        switch kind {
        case .text:
            self = .text(try container.decode(TextItemContent.self, forKey: .text))
        case .image:
            self = .image(try container.decode(ImageItemContent.self, forKey: .image))
        case .color:
            self = .color(try container.decode(ColorItemContent.self, forKey: .color))
        case .link:
            self = .link(try container.decode(LinkItemContent.self, forKey: .link))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)

        switch self {
        case .text(let payload):
            try container.encode(payload, forKey: .text)
        case .image(let payload):
            try container.encode(payload, forKey: .image)
        case .color(let payload):
            try container.encode(payload, forKey: .color)
        case .link(let payload):
            try container.encode(payload, forKey: .link)
        }
    }
}

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

struct ImageItemContent: Codable, Equatable, Sendable {
    let filename: String
    let ocrText: String?

    init(filename: String, ocrText: String? = nil) {
        self.filename = filename
        self.ocrText = ocrText
    }

    func updatingOCRText(_ text: String) -> ImageItemContent {
        ImageItemContent(filename: filename, ocrText: text)
    }
}

struct ColorItemContent: Codable, Equatable, Sendable {
    let value: ClipboardColorValue
    let originalText: String

    var formattedVariants: [ClipboardColorVariant] {
        ClipboardColorFormat.allCases.map { format in
            ClipboardColorVariant(
                format: format,
                label: format.label,
                value: self.value.formatted(as: format)
            )
        }
    }
}

struct LinkItemContent: Codable, Equatable, Sendable {
    let url: URL
    let originalText: String

    var websiteName: String {
        ClipboardLinkValue.websiteName(for: url)
    }

    var displayURL: String {
        url.absoluteString
    }
}

struct ClipboardColorVariant: Equatable, Sendable {
    let format: ClipboardColorFormat
    let label: String
    let value: String
}

enum ClipboardColorFormat: String, CaseIterable, Codable, Sendable {
    case hex
    case rgb
    case hsl

    var label: String {
        rawValue.uppercased()
    }
}

struct ClipboardColorValue: Codable, Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    var nsColor: NSColor {
        NSColor(
            calibratedRed: red.clamped(to: 0...1),
            green: green.clamped(to: 0...1),
            blue: blue.clamped(to: 0...1),
            alpha: alpha.clamped(to: 0...1)
        )
    }

    var isOpaque: Bool {
        abs(alpha.clamped(to: 0...1) - 1.0) < 0.000_1
    }

    static func parse(_ string: String) -> ClipboardColorValue? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("#"), let parsed = parseHex(String(trimmed.dropFirst())) {
            return parsed
        }

        if trimmed.hasPrefix("rgb"), let parsed = parseRGB(trimmed) {
            return parsed
        }

        if trimmed.hasPrefix("hsl"), let parsed = parseHSL(trimmed) {
            return parsed
        }

        return nil
    }

    static func fallback(from string: String) -> ClipboardColorValue {
        parse(string) ?? ClipboardColorValue(red: 0, green: 0, blue: 0, alpha: 1)
    }

    func formatted(as format: ClipboardColorFormat) -> String {
        switch format {
        case .hex:
            return formattedHex
        case .rgb:
            return formattedRGB
        case .hsl:
            return formattedHSL
        }
    }

    private var formattedHex: String {
        let redComponent = Int((red.clamped(to: 0...1) * 255.0).rounded())
        let greenComponent = Int((green.clamped(to: 0...1) * 255.0).rounded())
        let blueComponent = Int((blue.clamped(to: 0...1) * 255.0).rounded())
        let alphaComponent = Int((alpha.clamped(to: 0...1) * 255.0).rounded())

        if isOpaque {
            return String(format: "#%02X%02X%02X", redComponent, greenComponent, blueComponent)
        }

        return String(format: "#%02X%02X%02X%02X", redComponent, greenComponent, blueComponent, alphaComponent)
    }

    private var formattedRGB: String {
        let redComponent = Int((red.clamped(to: 0...1) * 255.0).rounded())
        let greenComponent = Int((green.clamped(to: 0...1) * 255.0).rounded())
        let blueComponent = Int((blue.clamped(to: 0...1) * 255.0).rounded())

        if isOpaque {
            return "rgb(\(redComponent), \(greenComponent), \(blueComponent))"
        }

        return "rgba(\(redComponent), \(greenComponent), \(blueComponent), \(formattedAlphaComponent))"
    }

    private var formattedHSL: String {
        let hsl = toHSL()
        let hue = Int(hsl.hue.rounded())
        let saturation = Int((hsl.saturation * 100.0).rounded())
        let lightness = Int((hsl.lightness * 100.0).rounded())

        if isOpaque {
            return "hsl(\(hue), \(saturation)%, \(lightness)%)"
        }

        return "hsla(\(hue), \(saturation)%, \(lightness)%, \(formattedAlphaComponent))"
    }

    private var formattedAlphaComponent: String {
        let rounded = (alpha.clamped(to: 0...1) * 100.0).rounded() / 100.0
        if rounded == floor(rounded) {
            return String(format: "%.0f", rounded)
        }

        return String(format: "%.2f", rounded)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    private static func parseHex(_ hexString: String) -> ClipboardColorValue? {
        let hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hex.isEmpty else { return nil }
        guard hex.range(of: #"^[0-9a-f]{3}$|^[0-9a-f]{6}$|^[0-9a-f]{8}$"#, options: .regularExpression) != nil else {
            return nil
        }

        if hex.count == 3 {
            let expanded = hex.map { "\($0)\($0)" }.joined()
            return parseHex6(expanded)
        }

        if hex.count == 6 {
            return parseHex6(hex)
        }

        if hex.count == 8 {
            return parseHex8(hex)
        }

        return nil
    }

    private static func parseHex6(_ hex: String) -> ClipboardColorValue? {
        guard let value = UInt64(hex, radix: 16) else { return nil }
        return ClipboardColorValue(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0,
            alpha: 1
        )
    }

    private static func parseHex8(_ hex: String) -> ClipboardColorValue? {
        guard let value = UInt64(hex, radix: 16) else { return nil }
        return ClipboardColorValue(
            red: Double((value >> 24) & 0xFF) / 255.0,
            green: Double((value >> 16) & 0xFF) / 255.0,
            blue: Double((value >> 8) & 0xFF) / 255.0,
            alpha: Double(value & 0xFF) / 255.0
        )
    }

    private static func parseRGB(_ string: String) -> ClipboardColorValue? {
        let isRGBA = string.hasPrefix("rgba")
        let startOffset = isRGBA ? 5 : 4

        guard string.count > startOffset + 1, string.hasSuffix(")") else { return nil }

        let startIndex = string.index(string.startIndex, offsetBy: startOffset)
        let endIndex = string.index(before: string.endIndex)
        let content = String(string[startIndex..<endIndex]).trimmingCharacters(in: .whitespaces)
        let components = content.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        guard components.count >= 3,
              let red = Double(components[0]),
              let green = Double(components[1]),
              let blue = Double(components[2]) else {
            return nil
        }

        let alpha = isRGBA && components.count >= 4 ? (Double(components[3]) ?? 1) : 1

        return ClipboardColorValue(
            red: red / 255.0,
            green: green / 255.0,
            blue: blue / 255.0,
            alpha: alpha
        )
    }

    private static func parseHSL(_ string: String) -> ClipboardColorValue? {
        let isHSLA = string.hasPrefix("hsla")
        let startOffset = isHSLA ? 5 : 4

        guard string.count > startOffset + 1, string.hasSuffix(")") else { return nil }

        let startIndex = string.index(string.startIndex, offsetBy: startOffset)
        let endIndex = string.index(before: string.endIndex)
        let content = String(string[startIndex..<endIndex]).trimmingCharacters(in: .whitespaces)
        let components = content.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        guard components.count >= 3 else { return nil }

        func parsePercent(_ value: String) -> Double? {
            guard value.hasSuffix("%") else { return nil }
            return Double(value.dropLast()).map { $0 / 100.0 }
        }

        let hueValue = components[0].hasSuffix("deg")
            ? String(components[0].dropLast(3))
            : components[0]

        guard let hue = Double(hueValue),
              let saturation = parsePercent(components[1]),
              let lightness = parsePercent(components[2]) else {
            return nil
        }

        let alpha = isHSLA && components.count >= 4 ? (Double(components[3]) ?? 1) : 1
        return hsl(hue: hue, saturation: saturation, lightness: lightness, alpha: alpha)
    }

    private static func hsl(
        hue: Double,
        saturation: Double,
        lightness: Double,
        alpha: Double
    ) -> ClipboardColorValue {
        let normalizedHue = ((hue.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360) / 360.0

        if saturation == 0 {
            return ClipboardColorValue(red: lightness, green: lightness, blue: lightness, alpha: alpha)
        }

        let q = lightness < 0.5
            ? lightness * (1 + saturation)
            : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q

        func hueToRGB(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t

            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6.0 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2.0 { return q }
            if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6 }
            return p
        }

        return ClipboardColorValue(
            red: hueToRGB(p, q, normalizedHue + 1.0 / 3.0),
            green: hueToRGB(p, q, normalizedHue),
            blue: hueToRGB(p, q, normalizedHue - 1.0 / 3.0),
            alpha: alpha
        )
    }

    private func toHSL() -> (hue: Double, saturation: Double, lightness: Double) {
        let red = red.clamped(to: 0...1)
        let green = green.clamped(to: 0...1)
        let blue = blue.clamped(to: 0...1)

        let maxComponent = max(red, green, blue)
        let minComponent = min(red, green, blue)
        let delta = maxComponent - minComponent
        let lightness = (maxComponent + minComponent) / 2.0

        guard delta > 0 else {
            return (0, 0, lightness)
        }

        let saturation = lightness > 0.5
            ? delta / (2.0 - maxComponent - minComponent)
            : delta / (maxComponent + minComponent)

        let hueSegment: Double
        if maxComponent == red {
            hueSegment = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxComponent == green {
            hueSegment = ((blue - red) / delta) + 2
        } else {
            hueSegment = ((red - green) / delta) + 4
        }

        let hue = ((hueSegment * 60.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
        return (hue, saturation, lightness)
    }
}

enum ClipboardItemKind: String, Codable, Sendable, CaseIterable {
    case text
    case image
    case color
    case link
}

typealias ClipboardItemType = ClipboardItemKind

enum ClipboardDetailContentKind: Sendable {
    case text
    case image
    case color
    case link
}

enum ClipboardDetailAction: String, Sendable, CaseIterable, Hashable {
    case saveImage
    case extractImageText
    case openLink
}

enum ClipboardLeadingVisualStyle {
    case document
    case image
    case colorSwatch(ClipboardColorValue)
    case link
}

struct ClipboardItemTypeDefinition {
    let kind: ClipboardItemKind
    let displayName: String
    let detailContentKind: ClipboardDetailContentKind
    let detailActions: Set<ClipboardDetailAction>
}

enum ClipboardItemTypeRegistry {
    private static let definitions: [ClipboardItemKind: ClipboardItemTypeDefinition] = [
        .text: ClipboardItemTypeDefinition(
            kind: .text,
            displayName: "Text",
            detailContentKind: .text,
            detailActions: []
        ),
        .image: ClipboardItemTypeDefinition(
            kind: .image,
            displayName: "Image",
            detailContentKind: .image,
            detailActions: [.saveImage, .extractImageText]
        ),
        .color: ClipboardItemTypeDefinition(
            kind: .color,
            displayName: "Color",
            detailContentKind: .color,
            detailActions: []
        ),
        .link: ClipboardItemTypeDefinition(
            kind: .link,
            displayName: "Link",
            detailContentKind: .link,
            detailActions: [.openLink]
        )
    ]

    static func definition(for item: ClipboardItem) -> ClipboardItemTypeDefinition {
        definitions[item.kind]!
    }

    static func previewText(for item: ClipboardItem) -> String {
        switch item.content {
        case .text(let payload):
            let text = payload.inlineText ?? ""
            if text.count > 200 {
                return String(text.prefix(200)) + "…"
            }
            return text
        case .image:
            return definition(for: item).displayName
        case .color(let payload):
            return payload.originalText
        case .link(let payload):
            return payload.originalText
        }
    }

    static func primaryLabelText(for item: ClipboardItem) -> String {
        switch item.content {
        case .image:
            return definition(for: item).displayName
        case .text, .color, .link:
            let rawText = previewText(for: item)
            let collapsed = rawText
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if collapsed.count > 50 {
                return String(collapsed.prefix(50)) + "…"
            }

            return collapsed
        }
    }

    @MainActor
    static func searchableText(for item: ClipboardItem, store: ClipboardStore) -> String {
        switch item.content {
        case .text:
            return store.fullText(for: item) ?? item.textContent ?? ""
        case .image(let payload):
            return payload.ocrText ?? ""
        case .color(let payload):
            return payload.originalText
        case .link(let payload):
            return payload.originalText
        }
    }

    @MainActor
    static func pastedText(for item: ClipboardItem, store: ClipboardStore) -> String? {
        switch item.content {
        case .text:
            return store.fullText(for: item) ?? item.textContent
        case .color(let payload):
            return payload.originalText
        case .link(let payload):
            return payload.originalText
        case .image:
            return nil
        }
    }

    static func contentHash(for item: ClipboardItem) -> Int {
        switch item.content {
        case .text(let payload):
            return payload.fileName?.hashValue ?? payload.inlineText?.hashValue ?? 0
        case .image(let payload):
            return payload.filename.hashValue
        case .color(let payload):
            return payload.originalText.hashValue
        case .link(let payload):
            return payload.originalText.hashValue
        }
    }

    static func leadingVisualStyle(for item: ClipboardItem) -> ClipboardLeadingVisualStyle {
        switch item.content {
        case .text:
            return .document
        case .image:
            return .image
        case .color(let payload):
            return .colorSwatch(payload.value)
        case .link:
            return .link
        }
    }

    static func supportsImageAssets(for item: ClipboardItem) -> Bool {
        item.kind == .image
    }

    static func supportsTextChunks(for item: ClipboardItem) -> Bool {
        definition(for: item).detailContentKind == .text
    }

    static func detailActions(for item: ClipboardItem) -> Set<ClipboardDetailAction> {
        definition(for: item).detailActions
    }

    static func canSaveImage(for item: ClipboardItem?) -> Bool {
        guard let item else { return false }
        return detailActions(for: item).contains(.saveImage)
    }

    static func canExtractImageText(for item: ClipboardItem?) -> Bool {
        guard let item else { return false }
        return detailActions(for: item).contains(.extractImageText)
    }

    static func canOpenLink(for item: ClipboardItem?) -> Bool {
        guard let item else { return false }
        return detailActions(for: item).contains(.openLink)
    }

    static func showsSourceApplication(for item: ClipboardItem?) -> Bool {
        guard let item else { return false }
        return item.kind != .color && item.kind != .link
    }
}

enum ClipboardLinkValue {
    static func parse(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }

        if let directURL = normalizedWebURL(from: trimmed) {
            return directURL
        }

        guard !trimmed.contains("://") else { return nil }
        return normalizedWebURL(from: "https://\(trimmed)")
    }

    static func websiteName(for url: URL) -> String {
        let host = (url.host ?? url.absoluteString)
            .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)

        let labels = host
            .split(separator: ".")
            .map(String.init)

        let baseLabel: String
        if labels.count >= 3,
           labels[labels.count - 1].count == 2,
           labels[labels.count - 2].count <= 3 {
            baseLabel = labels[labels.count - 3]
        } else if labels.count >= 2 {
            baseLabel = labels[labels.count - 2]
        } else {
            baseLabel = labels.first ?? host
        }

        return baseLabel
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { segment in
                let word = String(segment)
                guard !word.isEmpty else { return word }
                return word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    private static func normalizedWebURL(from string: String) -> URL? {
        guard var components = URLComponents(string: string) else { return nil }
        guard let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              hostLooksWebLike(host) else {
            return nil
        }

        components.scheme = scheme
        return components.url
    }

    private static func hostLooksWebLike(_ host: String) -> Bool {
        host.contains(".")
            && host.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) != nil
            && !host.contains("..")
    }
}
