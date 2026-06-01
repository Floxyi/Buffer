import AppKit

enum PastePayload {
    case string(String)
    case fileURLs([URL])
    case tiff(Data)
}

struct PasteBatchPayload {
    let textPayload: String?
    let imageFileURLs: [URL]

    var hasContent: Bool {
        textPayload?.isEmpty == false || !imageFileURLs.isEmpty
    }
}

@MainActor
protocol PasteImageExporting {
    func saveImageToTemp(_ image: NSImage, fileName: String) -> URL?
    func saveImageToDisk(_ image: NSImage)
}

@MainActor
struct PastePayloadBuilder {
    private let store: ClipboardStoreReading
    private let imageExporter: PasteImageExporting

    init(store: ClipboardStoreReading, imageExporter: PasteImageExporting) {
        self.store = store
        self.imageExporter = imageExporter
    }

    func copyPayload(for item: ClipboardItem) -> PastePayload? {
        if let text = ClipboardItemTypeRegistry.pastedText(for: item, store: store) {
            return .string(text)
        }

        guard ClipboardItemTypeRegistry.supportsImageAssets(for: item),
              let image = store.image(for: item),
              let tiffData = image.tiffRepresentation else {
            return nil
        }

        return .tiff(tiffData)
    }

    func copyPayload(for items: [ClipboardItem]) -> PastePayload? {
        guard !items.isEmpty else { return nil }
        guard items.count > 1 else { return copyPayload(for: items[0]) }

        let textItems = items.compactMap { ClipboardItemTypeRegistry.pastedText(for: $0, store: store) }
        if !textItems.isEmpty {
            return .string(textItems.joined(separator: "\n"))
        }

        let imageURLs = imageFileURLs(for: items)
        guard !imageURLs.isEmpty else { return nil }
        return .fileURLs(imageURLs)
    }

    func pastePayload(for item: ClipboardItem) -> PastePayload? {
        if let text = ClipboardItemTypeRegistry.pastedText(for: item, store: store) {
            return .string(text)
        }

        guard ClipboardItemTypeRegistry.supportsImageAssets(for: item),
              let image = store.image(for: item) else {
            return nil
        }

        if let fileURL = imageExporter.saveImageToTemp(image, fileName: "image-0001.png") {
            return .fileURLs([fileURL])
        }

        guard let tiffData = image.tiffRepresentation else {
            return nil
        }

        return .tiff(tiffData)
    }

    func batchPayload(for items: [ClipboardItem]) -> PasteBatchPayload {
        let textPayload = items
            .compactMap { ClipboardItemTypeRegistry.pastedText(for: $0, store: store) }
            .joined(separator: "\n")

        return PasteBatchPayload(
            textPayload: textPayload.isEmpty ? nil : textPayload,
            imageFileURLs: imageFileURLs(for: items.filter { ClipboardItemTypeRegistry.supportsImageAssets(for: $0) })
        )
    }

    private func imageFileURLs(for items: [ClipboardItem]) -> [URL] {
        items.enumerated().compactMap { index, item -> URL? in
            guard let image = store.image(for: item) else { return nil }
            let paddedNumber = String(format: "%04d", index + 1)
            return imageExporter.saveImageToTemp(image, fileName: "image-\(paddedNumber).png")
        }
    }
}
