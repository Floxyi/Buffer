import Foundation

enum ClipboardDetailContentKind: Sendable {
    case text
    case image
    case color
    case link
    case email
}

enum ClipboardDetailAction: String, Sendable, CaseIterable, Hashable {
    case saveImage
    case extractImageText
    case openLink
    case composeEmail
}

enum ClipboardLeadingVisualStyle: Sendable {
    case document
    case image
    case colorSwatch(ClipboardColorValue)
    case link
    case email
}

struct ClipboardItemPresentationDefinition: Sendable {
    let displayName: String
    let detailContentKind: ClipboardDetailContentKind
    let detailActions: Set<ClipboardDetailAction>
}

enum ClipboardItemPresentation {
    private static let definitions: [ClipboardItemKind: ClipboardItemPresentationDefinition] = [
        .text: ClipboardItemPresentationDefinition(
            displayName: "Text",
            detailContentKind: .text,
            detailActions: []
        ),
        .image: ClipboardItemPresentationDefinition(
            displayName: "Image",
            detailContentKind: .image,
            detailActions: [.saveImage, .extractImageText]
        ),
        .color: ClipboardItemPresentationDefinition(
            displayName: "Color",
            detailContentKind: .color,
            detailActions: []
        ),
        .link: ClipboardItemPresentationDefinition(
            displayName: "Link",
            detailContentKind: .link,
            detailActions: [.openLink]
        ),
        .email: ClipboardItemPresentationDefinition(
            displayName: "Email",
            detailContentKind: .email,
            detailActions: [.composeEmail]
        )
    ]

    static func definition(for item: ClipboardItem) -> ClipboardItemPresentationDefinition {
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
        case .email(let payload):
            return payload.originalText
        }
    }

    static func primaryLabelText(for item: ClipboardItem) -> String {
        switch item.content {
        case .image:
            return definition(for: item).displayName
        case .text, .color, .link, .email:
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
        case .email:
            return .email
        }
    }

    static func showsSourceApplication(for item: ClipboardItem?) -> Bool {
        guard let item else { return false }
        return item.kind != .color && item.kind != .link && item.kind != .email
    }
}
