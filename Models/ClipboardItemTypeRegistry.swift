import Foundation

enum ClipboardItemTypeRegistry {
    @MainActor
    static func searchableText(for item: ClipboardItem, store: any ClipboardStoreReading) -> String {
        switch item.content {
        case .text:
            return store.fullText(for: item) ?? item.textContent ?? ""
        case .image(let payload):
            return payload.ocrText ?? ""
        case .color(let payload):
            return payload.originalText
        case .link(let payload):
            return payload.originalText
        case .email(let payload):
            return payload.originalText
        }
    }

    @MainActor
    static func pastedText(for item: ClipboardItem, store: any ClipboardStoreReading) -> String? {
        switch item.content {
        case .text:
            return store.fullText(for: item) ?? item.textContent
        case .color(let payload):
            return payload.originalText
        case .link(let payload):
            return payload.originalText
        case .email(let payload):
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
            return payload.filename.hashValue ^ (payload.ocrText?.hashValue ?? 0)
        case .color(let payload):
            return payload.originalText.hashValue
        case .link(let payload):
            return payload.originalText.hashValue
        case .email(let payload):
            return payload.originalText.hashValue
        }
    }

    static func supportsImageAssets(for item: ClipboardItem) -> Bool {
        item.kind == .image
    }

    static func supportsTextChunks(for item: ClipboardItem) -> Bool {
        item.kind == .text
    }

    static func canSaveImage(for item: ClipboardItem?) -> Bool {
        guard let item else { return false }
        return item.kind == .image
    }

    static func canExtractImageText(for item: ClipboardItem?) -> Bool {
        guard let item else { return false }
        return item.kind == .image
    }

    static func canOpenLink(for item: ClipboardItem?) -> Bool {
        guard let item else { return false }
        return item.kind == .link
    }

    static func canComposeEmail(for item: ClipboardItem?) -> Bool {
        item?.emailPayload?.mailtoURL != nil
    }
}
